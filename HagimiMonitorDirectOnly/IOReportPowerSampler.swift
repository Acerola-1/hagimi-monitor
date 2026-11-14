import CoreFoundation
import CoreGraphics
import Foundation

nonisolated struct IOReportPowerSample: Sendable {
    var displayWatts: Double? = nil
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
    var aneWatts: Double? = nil
    var memoryBandwidthBytesPerSec: Double? = nil
    var gpuClock: GPUClockStateReadout? = nil
    var readings: [String: PowerReading] = [:]
}
nonisolated protocol IOReportPowerSampling: Sendable {
    func sample() -> IOReportPowerSample
}
/// 私有 API、订阅和基线统一由 sampleLock 保护，并复用现有采样循环。
nonisolated final class IOReportPowerSampler: IOReportPowerSampling, @unchecked Sendable {
    static let shared = IOReportPowerSampler()
    private let sampleLock = NSLock()
    private var displaySubscription = PowerSubscriptionRecovery<IOReportSubscription>()
    private var energySubscription = PowerSubscriptionRecovery<IOReportSubscription>()
    private var clpcSubscription = PowerSubscriptionRecovery<IOReportSubscription>()
    private var memorySubscription = PowerSubscriptionRecovery<IOReportSubscription>()
    private var clockSubscription = PowerSubscriptionRecovery<IOReportSubscription>()
    private var display = PowerCounterTracker()
    private var cpuLegacy = PowerCounterTracker()
    private var cpuCLPC = PowerCounterTracker()
    private var gpu = PowerCounterTracker()
    private var aneLegacy = PowerCounterTracker()
    private var aneCLPC = PowerCounterTracker()
    private var cpuSelector = PowerSourceSelector()
    private var aneSelector = PowerSourceSelector()
    private var lastSample = IOReportPowerSample()
    private var lastSampleAt: TimeInterval?
    private var previousClockStateReport: CFDictionary?
    private var clockGeneration: UInt64 = 0
    private var clockReport: CFDictionary?
    private var memoryBaseline: (identity: String, values: [Int64], time: TimeInterval)?
    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1e9
    }()
    static var continuousTime: TimeInterval { Double(mach_continuous_time()) * timebase }

    func sample() -> IOReportPowerSample {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        let now = Self.continuousTime
        if let lastSampleAt, now - lastSampleAt < 0.25 { return lastSample }
        if let lastSampleAt, now - lastSampleAt > PowerCounterTracker.maximumGap {
            displaySubscription.invalidate(at: now)
            energySubscription.invalidate(at: now)
            clpcSubscription.invalidate(at: now)
            memorySubscription.invalidate(at: now)
            clockSubscription.invalidate(at: now)
            previousClockStateReport = nil
            memoryBaseline = nil
        }
        defer { lastSampleAt = now }
        let screenSnapshot = Self.snapshot(&displaySubscription, at: now) {
            IOReportSubscription(group: "DCP", subgroup: "display stats", accepts: { $0 == "power" })
        }
        let energySnapshot = Self.snapshot(&energySubscription, at: now) {
            IOReportSubscription(group: "Energy Model", subgroup: nil,
                accepts: { $0 == "CPU Energy" || $0 == "GPU Energy" || $0.hasPrefix("ANE") })
        }
        let clpcSnapshot = Self.snapshot(&clpcSubscription, at: now) { IOReportSubscription.clpc() }
        let memorySnapshot = Self.snapshot(&memorySubscription, at: now) {
            IOReportSubscription(group: "PMP", subgroup: "DSID Stats", accepts: { $0.hasSuffix("Misses") })
        }
        clockReport = clockSubscription.sample(at: now, create: {
            IOReportSubscription(group: "GPU Stats", subgroup: nil, accepts: { _ in true }, subgroupFilter: {
                ["GPU Performance States", "CLTM-induced GPU Performance States", "PPM Target as % of Max GPU Power"].contains($0)
            })
        }, read: { $0.report() })
        if clockGeneration != clockSubscription.generation {
            previousClockStateReport = nil
            clockGeneration = clockSubscription.generation
        }
        let displayCounters = screenSnapshot?.counters(named: { $0 == "power" }, display: true)
        // 屏幕功率只在存在唯一内屏通道时计算，其余情况保持缺失。
        let screen = display.update(displayCounters?.count == 1 ? displayCounters : nil,
            at: now, source: .display, screen: Self.screenActivity(), maximumWatts: 100)
        let cpu = Self.component(preferredSnapshot: clpcSnapshot, fallbackSnapshot: energySnapshot,
            named: { $0 == "CPU Energy" }, preferredTracker: &cpuCLPC, fallbackTracker: &cpuLegacy,
            selector: &cpuSelector, at: now, maximumWatts: 500)
        let ane = Self.component(preferredSnapshot: clpcSnapshot, fallbackSnapshot: energySnapshot,
            named: { $0.hasPrefix("ANE") }, preferredTracker: &aneCLPC, fallbackTracker: &aneLegacy,
            selector: &aneSelector, at: now, maximumWatts: 100)
        let gpuCounters = energySnapshot?.counters(named: { $0 == "GPU Energy" })
        let graphics = gpu.update(gpuCounters?.count == 1 ? gpuCounters : nil, at: now, source: .energyModel)
        let result = IOReportPowerSample(displayWatts: screen.watts, cpuWatts: cpu.watts,
            gpuWatts: graphics.watts, aneWatts: ane.watts, memoryBandwidthBytesPerSec: memoryRate(memorySnapshot, at: now),
            gpuClock: clockState(), readings: ["display-power": screen, "cpu-power": cpu, "gpu-power": graphics, "ane-power": ane])
        lastSample = result
        return result
    }
    private static func snapshot(_ recovery: inout PowerSubscriptionRecovery<IOReportSubscription>, at time: TimeInterval,
                                 create: () -> IOReportSubscription?) -> PowerChannelSnapshot? {
        let report = recovery.sample(at: time, create: create, read: { $0.report() })
        guard let report, let handle = recovery.handle else { return nil }
        return handle.snapshot(in: report, generation: recovery.generation)
    }
    private static func component(preferredSnapshot: PowerChannelSnapshot?, fallbackSnapshot: PowerChannelSnapshot?,
                                  named accepts: (String) -> Bool,
                                  preferredTracker: inout PowerCounterTracker, fallbackTracker: inout PowerCounterTracker,
                                  selector: inout PowerSourceSelector, at time: TimeInterval, maximumWatts: Double) -> PowerReading {
        let preferredCounters = preferredSnapshot?.counters(named: accepts)
        let fallbackCounters = fallbackSnapshot?.counters(named: accepts)
        let preferred = preferredTracker.update(preferredCounters, at: time, source: .clpc,
            requiresPositiveEvidence: true, maximumWatts: maximumWatts,
            allowsUntimedGrowth: preferredCounters?.allSatisfy { $0.timestamp == 0 } == true)
        let fallback = fallbackTracker.update(fallbackCounters, at: time, source: .energyModel, maximumWatts: maximumWatts)
        let decision = selector.choose(preferred: preferred, preferredReady: preferredTracker.canSelect,
            fallback: fallback, fallbackReady: fallbackTracker.canSelect, at: time,
            hardFailure: preferredSnapshot != nil && preferredCounters == nil)
        if decision.changed, decision.selection != nil {
            if decision.selection == .preferred { preferredTracker.rebaseForSelection() }
            else { fallbackTracker.rebaseForSelection() }
            let candidate = decision.selection == .preferred ? preferred : fallback
            return .missing(.warmingUp, source: candidate.source, at: time, identity: candidate.identity)
        }
        if let selection = decision.selection { return selection == .preferred ? preferred : fallback }
        if preferred.state == .unverified { return preferred }
        return fallback.state == .unavailable && preferredSnapshot != nil ? preferred : fallback
    }
    private func memoryRate(_ snapshot: PowerChannelSnapshot?, at time: TimeInterval) -> Double? {
        guard let snapshot, !snapshot.expected.isEmpty,
              Set(snapshot.records.map(\.descriptor)) == snapshot.expected,
              snapshot.records.count == snapshot.expected.count else { memoryBaseline = nil; return nil }
        let records = snapshot.records.sorted { $0.descriptor.identity < $1.descriptor.identity }
        let identity = "\(snapshot.generation):" + records.map { $0.descriptor.identity }.joined(separator: "|")
        let values = records.map(\.value)
        defer { memoryBaseline = (identity, values, time) }
        guard let baseline = memoryBaseline, baseline.identity == identity,
              time > baseline.time, time - baseline.time <= 30 else { return nil }
        var delta = 0.0
        for (previous, current) in zip(baseline.values, values) {
            let (difference, overflow) = current.subtractingReportingOverflow(previous)
            guard !overflow, difference >= 0 else { return nil }
            delta += Double(difference)
        }
        let result = delta / (time - baseline.time)
        return result.isFinite && result <= 2e12 ? result : nil
    }
    private static func screenActivity() -> PowerScreenActivity {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return .unknown }
        let builtIn = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
        guard !builtIn.isEmpty else { return .absent }
        return builtIn.contains { CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0 } ? .active : .inactive
    }
    static func energyJoulesPerCount(unit: UInt64) -> Double? { PowerEnergyUnit.joulesPerCount(unit) }
    private func clockState() -> GPUClockStateReadout? {
        guard let current = clockReport else {
            previousClockStateReport = nil
            return nil
        }
        defer { previousClockStateReport = current }
        guard let previous = previousClockStateReport,
              let delta = IOReportCreateSamplesDelta(previous, current, nil)?.takeRetainedValue() else {
            return nil
        }
        var dominant: (name: String, percent: Double)?
        var throttlePercent = 0.0
        var powerCapPercent: Double?
        var sawAny = false
        for series in clockSubscription.handle?.stateSeries(in: delta) ?? [] {
            switch series.subgroup {
            case "GPU Performance States":
                sawAny = true
                dominant = GPUClockStateMath.dominantState(series.states)
            case "CLTM-induced GPU Performance States":
                sawAny = true
                throttlePercent = GPUClockStateMath.throttlePercent(series.states)
            case "PPM Target as % of Max GPU Power":
                sawAny = true
                powerCapPercent = GPUClockStateMath.powerCapPercent(series.states)
            default:
                break
            }
        }
        guard sawAny else { return nil }
        return GPUClockStateReadout(
            dominantState: dominant?.name,
            dominantResidencyPercent: dominant?.percent,
            throttlePercent: throttlePercent,
            powerCapPercent: powerCapPercent
        )
    }

}
