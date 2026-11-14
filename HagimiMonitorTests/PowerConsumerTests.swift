import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct PowerConsumerTests {
    private func components() -> IOReportPowerSample {
        let reading = PowerReading(watts: 3, state: .valid, source: .clpc, identity: "fixture",
                                   intervalStart: 10, intervalEnd: 11)
        return IOReportPowerSample(displayWatts: 3, cpuWatts: 3, gpuWatts: 3,
            readings: ["display-power": reading, "cpu-power": reading, "gpu-power": reading,
                       "ane-power": .missing(.unverified, source: .clpc, at: 11)])
    }

    private func unavailable() -> MonitorModule {
        BatterySampler(powerSourceReader: { .unavailable }).sample(previous: nil, power: components())
    }

    @Test func failedIOPSOnlyExposesEnabledIndependentTopology() {
        let failed = unavailable()
        #expect(failed.isPlaceholder)
        #expect(failed.metrics.first { $0.name == "status" }?.value == "unknown")
        #expect(failed.summary == "--")
        let enabled = Set(failed.metrics.map(\.name)).union(["power", "health", "power-in", "battery-flow"])
        let presentation = BatteryPowerPresentation(module: failed, enabledNames: enabled)
        #expect(presentation.tabs(showPowerFlow: true) == [.flow])
        #expect(Set(presentation.metrics(for: .flow).map(\.name)) == BatteryPowerPresentation.independentNames)
        #expect(presentation.metrics(for: .health).isEmpty)
        #expect(presentation.metrics(for: .supply).isEmpty)
        #expect(presentation.metrics(for: .flow).first { $0.name == "cpu-power" }?.powerReading?.source == .clpc)
        let readings = PowerReadings(module: failed)
        #expect(!readings.connected && readings.status == "unknown")
        #expect(readings.inputText == "—" && readings.loadText == "—" && readings.batteryText == nil)
        #expect(ReportLiveReadings.readings(for: failed) == nil)
        #expect(BatteryPowerPresentation(module: failed, enabledNames: ["health", "power"]).tabs(showPowerFlow: true).isEmpty)

        let sampler = BatterySampler(powerSourceReader: { .unavailable })
        let missing = sampler.sample(previous: nil, power: IOReportPowerSample())
        let missingPresentation = BatteryPowerPresentation(module: missing, enabledNames: ["cpu-power"])
        #expect(missingPresentation.tabs(showPowerFlow: false) == [.flow])
        #expect(missingPresentation.metrics(for: .flow).first?.value == "--")
    }

    @Test func menuBarRejectsEveryMetricFromPlaceholderBattery() {
        for name in ["power", "gpu-power", "display-power"] {
            #expect(MonitorStore.numericMetricValue(name, in: unavailable()) == nil)
            #expect(MonitorStore.numericMetricValue(name, in: MonitorModule(
                kind: .battery, value: 50, summary: "50%",
                metrics: [MonitorMetric(name: name, value: "3.0 W", numericValue: 3)], samples: []
            )) == 3)
        }
    }

    @Test func cachedBatteryHistoryStopsAndRestartsAfterFailure() {
        let before = MonitorModule(kind: .battery, value: 45, summary: "45%", metrics: [], samples: [40, 42, 45])
        var failed = unavailable()
        let held = SystemMonitorSampler.historySamples(current: failed, previous: before)
        #expect(held == before.samples)
        failed.samples = held
        let after = MonitorModule(kind: .battery, value: 44, summary: "44%", metrics: [], samples: [])
        #expect(SystemMonitorSampler.historySamples(current: after, previous: failed) == [44])
        #expect(PowerReadings(module: failed).batteryText == nil)
    }

    @Test func independentComponentsDoNotEnterBatteryStatistics() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("power-isolation-\(UUID().uuidString).sqlite3")
        let recorder = StatisticsRecorder(databaseURL: url)
        let base = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60 - 600)
        let failed = unavailable()
        let cpu = MonitorModule(kind: .cpu, value: 40, summary: "40%", metrics: [], samples: [])
        let gpu = MonitorModule(kind: .gpu, value: 20, summary: "20%", metrics: [], samples: [])
        for t in 0..<3 {
            recorder.record(modules: [failed, cpu, gpu], fans: [], freshKinds: [.battery, .cpu, .gpu], at: base.addingTimeInterval(Double(t)))
        }
        recorder.sealCompletedMinuteForTesting()
        let row = recorder.reportDataProvider().loadMetricRows(now: base.addingTimeInterval(120))?.minutes.first
        #expect(row?.cpuAvg == 40 && row?.gpuAvg == 20)
        #expect(row?.battLevelAvg == nil && row?.battTempAvg == nil)
        #expect(row?.powerAvg == nil && row?.powerMax == nil)
        #expect(row?.acFrac == nil && row?.chargingFrac == nil)
        #expect(ReportLiveReadings.readings(for: failed) == nil)
    }

    @Test func sharedPowerFrameSamplesOnceAndRespectsRequestedKinds() {
        let power = CountingPowerSampler()
        let sampler = SystemMonitorSampler(powerSampler: power)
        _ = sampler.sample(kinds: [MonitorKind.cpu], previousModules: [])
        #expect(power.count == 0)
        _ = sampler.sample(kinds: [MonitorKind](), previousModules: [])
        #expect(power.count == 0)
        let first = sampler.sample(kinds: [MonitorKind.gpu, .memory, .battery], previousModules: [])
        #expect(power.count == 1)
        if case let .success(snapshot) = first {
            #expect(snapshot.modules.first { $0.kind == .battery }?.metrics.first { $0.name == "cpu-power" }?.numericValue == 1)
        }
        _ = sampler.sample(kinds: [MonitorKind.battery, .gpu], previousModules: [])
        #expect(power.count == 2)
    }

    @Test func missingAndIntervalHelpKeepBusinessExplanation() {
        let frozen = PowerReading.missing(.frozen, source: .energyModel, at: 3)
        let valid = PowerReading(watts: 1, state: .valid, source: .display, intervalStart: 1, intervalEnd: 3)
        #expect(PowerReadingPresentation.help(frozen)?.isEmpty == false)
        #expect(PowerReadingPresentation.help(valid)?.contains("2.0") == true)
        #expect(PowerReadingPresentation.help(nil) == nil)
    }
}

private nonisolated final class CountingPowerSampler: IOReportPowerSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func sample() -> IOReportPowerSample {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return IOReportPowerSample(cpuWatts: Double(calls))
    }
}
