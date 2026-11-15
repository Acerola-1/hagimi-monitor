import CoreFoundation
import Foundation

/// Direct 版专用的分项硬件遥测读数。所有功率字段为平均功率(W)，内存带宽为字节率(Bytes/s)。
nonisolated struct IOReportPowerSample: Sendable {
    var displayWatts: Double? = nil
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
    var aneWatts: Double? = nil
    var memoryBandwidthBytesPerSec: Double? = nil
    /// GPU 时钟态驻留/限频/功耗上限；首帧无 delta 基线时为 nil。
    var gpuClock: GPUClockStateReadout? = nil
}

/// 复用统一刷新节奏读取 IOReport 累计能量与总线吞吐，不创建独立轮询定时器，也不在采样线程 sleep。
///
/// 数据口径：
/// - 内建屏：DCP / display stats / power，按累计微焦耳处理；M3/macOS 27 的无效零增量按缺失返回；
/// - CPU / GPU / ANE：Energy Model 下的 CPU Energy / GPU Energy / ANE* 通道，按 channel 自带 unit 解码；
///   M3/macOS 27 优先订阅 CLPC 的独立 nJ 计数，避免旧 Energy Model 冻结；其他机型保留原路径；
/// - 内存总线：PMP / DSID Stats 下的各组 Misses 计数，计数单位即字节（多线程流式读负载实测：
///   本计数净增速率与负载实际字节速率之比 ≈1.05，每次 Miss 对应 64B 的假设已被否定）。
///
/// IOReport 为私有 API，因此本文件只属于未沙盒化的 Direct target。
/// 线程安全不变量：内部状态由 sampleLock(NSLock) 互斥保护，支持跨线程安全调用 sample()。
nonisolated final class IOReportPowerSampler: @unchecked Sendable {
    static let shared = IOReportPowerSampler()

    private enum ChannelID: Hashable {
        case display
        case cpu
        case gpu
        case ane
        case memory
    }

    private struct Counter {
        let value: Int64
        let scale: Double
    }

    // 启动时固定来源，单帧缺报不切回可能按分钟批量更新的旧计数。
    private let clpcSubscription = Subscription(descriptors: CLPCEnergyChannels.currentDescriptors())
    private let displayZeroIsUnavailable = CLPCEnergyChannels.displayZeroIsUnavailable(
        osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        cpuBrand: HardwareSysctl.string("machdep.cpu.brand_string")
    )
    private let displaySubscription = Subscription(
        group: "DCP",
        subgroup: "display stats",
        channelNames: ["power"]
    )
    private let energySubscription = Subscription(
        group: "Energy Model",
        subgroup: nil,
        channelNames: ["CPU Energy", "GPU Energy"]
    )
    /// Neural Engine 功耗：不同芯片是单路 `ANE` 或多路 `ANE0`/`ANE1`，按前缀收全；
    /// 收不到（部分机型该 rail 不在 Energy Model 下）时该项自然为 nil。
    private let aneSubscription = Subscription(
        group: "Energy Model",
        subgroup: nil,
        filter: { $0.hasPrefix("ANE") }
    )
    private let memorySubscription = Subscription(
        group: "PMP",
        subgroup: "DSID Stats",
        filter: { $0.hasSuffix("Misses") }
    )
    /// GPU 时钟态遥测的三个子组，各只有一个状态通道：时钟态驻留、热限频、功耗上限。
    /// 名字取自驱动；任一子组缺失时该项自然为 nil，不影响其余读数。
    private static let clockStateSubgroups: Set<String> = [
        "GPU Performance States",
        "CLTM-induced GPU Performance States",
        "PPM Target as % of Max GPU Power"
    ]
    private let clockStateSubscription = Subscription(
        group: "GPU Stats",
        subgroup: nil,
        subgroupFilter: { IOReportPowerSampler.clockStateSubgroups.contains($0) }
    )

    /// 相邻两次样本的报告，用于生成状态驻留的 delta。
    private var previousClockStateReport: CFDictionary?

    private var rates: [ChannelID: IOReportCounterRate] = [:]
    private var lastSample = IOReportPowerSample()
    private var lastSampleUptime: TimeInterval = 0
    /// 互斥保护 rates/lastSample，使 sample() 可安全跨线程调用。
    private let sampleLock = NSLock()

    func sample() -> IOReportPowerSample {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastSampleUptime < 0.25 {
            return lastSample
        }

        var counters: [ChannelID: Counter] = [:]

        if let channel = displaySubscription?.sampleChannels()["power"] {
            // DCP 的 power channel unit 标记为 dimensionless，但实测计数是累计 µJ。
            counters[.display] = Counter(value: channel.value, scale: 1e-6)
        }

        if let energyChannels = energySubscription?.sampleChannels() {
            if clpcSubscription == nil, let channel = energyChannels["CPU Energy"],
               let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                counters[.cpu] = Counter(value: channel.value, scale: scale)
            }
            if let channel = energyChannels["GPU Energy"],
               let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                counters[.gpu] = Counter(value: channel.value, scale: scale)
            }
        }

        if let clpcSubscription {
            let channels = clpcSubscription.sampleChannels()
            for (id, name) in [(ChannelID.cpu, "CPU Energy"), (.ane, "ANE")] {
                if let channel = channels[name], let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                    counters[id] = Counter(value: channel.value, scale: scale)
                }
            }
        } else if let aneChannels = aneSubscription?.sampleChannels(), !aneChannels.isEmpty {
            counters[.ane] = Self.aggregatedCounter(aneChannels.values)
        }

        if let memChannels = memorySubscription?.sampleChannels(), !memChannels.isEmpty {
            let totalMisses = memChannels.values.reduce(Int64(0)) { $0 + $1.value }
            counters[.memory] = Counter(value: totalMisses, scale: 1.0)
        }

        let sample = IOReportPowerSample(
            displayWatts: rate(for: .display, counter: counters[.display], uptime: uptime, maxRate: 1_000,
                               zeroDeltaIsUnavailable: displayZeroIsUnavailable),
            cpuWatts: rate(for: .cpu, counter: counters[.cpu], uptime: uptime, maxRate: 1_000,
                           zeroDeltaIsUnavailable: clpcSubscription == nil),
            gpuWatts: rate(for: .gpu, counter: counters[.gpu], uptime: uptime, maxRate: 1_000),
            aneWatts: rate(for: .ane, counter: counters[.ane], uptime: uptime, maxRate: 1_000,
                           zeroDeltaIsUnavailable: clpcSubscription == nil),
            memoryBandwidthBytesPerSec: rate(for: .memory, counter: counters[.memory], uptime: uptime, maxRate: 2_000_000_000_000),
            gpuClock: clockState()
        )
        lastSample = sample
        lastSampleUptime = uptime
        return sample
    }

    /// 状态驻留只在两份样本的 delta 上有区间含义：普通样本报告给的是自开机起的
    /// 累计 tick，直接读会得到一条几乎不动的曲线。首帧只存基线、返回 nil。
    private func clockState() -> GPUClockStateReadout? {
        guard let current = clockStateSubscription?.sampleReport() else { return nil }
        defer { previousClockStateReport = current }
        guard let previous = previousClockStateReport,
              let delta = IOReportCreateSamplesDelta(previous, current, nil)?.takeRetainedValue() else {
            return nil
        }
        var dominant: (name: String, percent: Double)?
        var throttlePercent = 0.0
        var powerCapPercent: Double?
        var sawAny = false
        for series in clockStateSubscription?.stateSeries(in: delta) ?? [] {
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

    /// 缺报会清除该通道基线；CLPC 允许真实零值，旧 CPU/ANE 冻结计数按缺失处理。
    private func rate(
        for id: ChannelID,
        counter: Counter?,
        uptime: TimeInterval,
        maxRate: Double,
        zeroDeltaIsUnavailable: Bool = false
    ) -> Double? {
        rates[id, default: IOReportCounterRate()].sample(
            value: counter?.value, scale: counter?.scale ?? 1, uptime: uptime,
            maxRate: maxRate, zeroDeltaIsUnavailable: zeroDeltaIsUnavailable
        )
    }

    /// IOReport unit:高 8 位为 quantity(3 = Energy)，bits 32...39 的 SI exponent
    /// 使用 excess-127 编码。CPU 实测为 10^-3 J/count，GPU 为 10^-9 J/count。
    static func energyJoulesPerCount(unit: UInt64) -> Double? {
        let quantity = UInt8((unit >> 56) & 0xff)
        let encodedExponent = UInt8((unit >> 32) & 0xff)
        guard quantity == 3, encodedExponent != 0 else { return nil }
        return pow(10, Double(Int(encodedExponent) - 127))
    }

    /// 把多条同域能量通道折算成单一累计计数：各通道 J/count 不同，先各自换算成
    /// 微焦耳再求和，保留亚焦耳精度（1e-6 J/count 级计数除以 1e-6 还原）。
    /// 多路 rails（如 ANE0/ANE1）求和是功耗口径而非精度口径：与 powermetrics 对
    /// 同一域的多路相加一致。
    private static func aggregatedCounter(_ channels: Dictionary<String, Subscription.ChannelValue>.Values) -> Counter? {
        var microJoules = 0.0
        var sawAny = false
        for channel in channels {
            guard let scale = energyJoulesPerCount(unit: channel.unit) else { continue }
            microJoules += Double(channel.value) * scale * 1e6
            sawAny = true
        }
        guard sawAny else { return nil }
        return Counter(value: Int64(microJoules.rounded()), scale: 1e-6)
    }
}

/// 单通道累计计数的差分状态；时间和计数由调用方注入，可独立验证恢复行为。
nonisolated struct IOReportCounterRate {
    private var baseline: (value: Int64, scale: Double, uptime: TimeInterval)?

    mutating func sample(value: Int64?, scale: Double, uptime: TimeInterval, maxRate: Double,
                         zeroDeltaIsUnavailable: Bool = false) -> Double? {
        guard let value, value >= 0, scale.isFinite, scale > 0, uptime.isFinite, uptime >= 0 else {
            baseline = nil
            return nil
        }
        defer { baseline = (value, scale, uptime) }
        guard let baseline, baseline.scale == scale else { return nil }
        let elapsed = uptime - baseline.uptime
        let (delta, overflow) = value.subtractingReportingOverflow(baseline.value)
        guard !overflow, elapsed > 0, elapsed <= 30, delta >= 0 else { return nil }
        guard !(zeroDeltaIsUnavailable && delta == 0) else { return nil }
        let result = Double(delta) * scale / elapsed
        return result.isFinite && result >= 0 && result <= maxRate ? result : nil
    }
}

/// 线程安全不变量：Subscription 仅由 IOReportPowerSampler 私有持有，并通过 sampleLock 互斥调用底层 IOReport C API。
private nonisolated final class Subscription: @unchecked Sendable {
    struct ChannelValue {
        let value: Int64
        let unit: UInt64
    }

    /// 一个状态通道在区间内的各状态 tick。tick 未归一化，需除以合计。
    struct StateSeries {
        let subgroup: String
        let states: [(name: String, ticks: Int64)]
    }

    private let subscription: CFTypeRef
    private let subscribedChannels: CFMutableDictionary

    convenience init?(
        group: String,
        subgroup: String?,
        channelNames: Set<String>? = nil,
        filter: ((String) -> Bool)? = nil,
        subgroupFilter: ((String) -> Bool)? = nil
    ) {
        guard let copiedChannels = IOReportCopyChannelsInGroup(
            group as CFString,
            subgroup as CFString?,
            0,
            0
        )?.takeRetainedValue(),
        let sourceChannels = (copiedChannels as NSDictionary)["IOReportChannels"] as? [NSDictionary] else {
            return nil
        }

        var foundNames = Set<String>()
        let filteredChannels = sourceChannels.filter { channel in
            guard let name = IOReportChannelGetChannelName(channel as CFDictionary)?.takeUnretainedValue() else {
                return false
            }
            let stringName = name as String
            if let channelNames, !channelNames.contains(stringName) {
                return false
            }
            if let filter, !filter(stringName) {
                return false
            }
            if let subgroupFilter {
                let subgroupName = IOReportChannelGetSubGroup(channel as CFDictionary)?
                    .takeUnretainedValue() as String? ?? ""
                if !subgroupFilter(subgroupName) {
                    return false
                }
            }
            return foundNames.insert(stringName).inserted
        }
        guard !filteredChannels.isEmpty,
              let mutableChannels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, copiedChannels) else {
            return nil
        }

        let key = "IOReportChannels" as CFString
        let values = filteredChannels as CFArray
        CFDictionarySetValue(
            mutableChannels,
            Unmanaged.passUnretained(key).toOpaque(),
            Unmanaged.passUnretained(values).toOpaque()
        )

        self.init(channels: mutableChannels)
    }

    convenience init?(descriptors: [NSMutableDictionary]) {
        guard !descriptors.isEmpty,
              let channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0,
                  ["IOReportChannels": descriptors] as CFDictionary) else { return nil }
        self.init(channels: channels)
    }

    private init?(channels: CFMutableDictionary) {
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let createdSubscription = IOReportCreateSubscription(
            nil,
            channels,
            &subscribed,
            0,
            nil
        )?.takeRetainedValue(),
        let subscribedChannels = subscribed?.takeRetainedValue() else {
            return nil
        }

        subscription = createdSubscription
        self.subscribedChannels = subscribedChannels
    }

    func sampleChannels() -> [String: ChannelValue] {
        guard let report = IOReportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue(),
              let channels = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary] else {
            return [:]
        }

        var result: [String: ChannelValue] = [:]
        for channel in channels {
            let cfChannel = channel as CFDictionary
            guard let name = IOReportChannelGetChannelName(cfChannel)?.takeUnretainedValue() else {
                continue
            }
            result[name as String] = ChannelValue(
                value: IOReportSimpleGetIntegerValue(cfChannel, 0),
                unit: IOReportChannelGetUnit(cfChannel)
            )
        }
        return result
    }

    /// 原始报样本报告。状态通道的驻留需要相邻两份报告做 delta，故这里不解析。
    func sampleReport() -> CFDictionary? {
        IOReportCreateSamples(subscription, subscribedChannels, nil)?.takeRetainedValue()
    }

    /// 从报告里取出状态通道（kIOReportFormatState）的各状态 tick。
    func stateSeries(in report: CFDictionary) -> [StateSeries] {
        guard let channels = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary] else {
            return []
        }
        var result: [StateSeries] = []
        for channel in channels {
            let cfChannel = channel as CFDictionary
            guard IOReportChannelGetFormat(cfChannel) == 2 else { continue }
            let count = IOReportStateGetCount(cfChannel)
            guard count > 0 else { continue }
            let subgroup = IOReportChannelGetSubGroup(cfChannel)?.takeUnretainedValue() as String? ?? ""
            var states: [(name: String, ticks: Int64)] = []
            for index in 0..<count {
                let name = IOReportStateGetNameForIndex(cfChannel, index)?
                    .takeUnretainedValue() as String? ?? "\(index)"
                states.append((name, IOReportStateGetResidency(cfChannel, index)))
            }
            result.append(StateSeries(subgroup: subgroup, states: states))
        }
        return result
    }
}
