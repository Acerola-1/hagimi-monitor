import CoreFoundation
import Foundation

/// Direct 版专用的分项硬件遥测读数。所有功率字段为平均功率(W)，内存带宽为字节率(Bytes/s)。
struct IOReportPowerSample {
    var displayWatts: Double? = nil
    var gpuWatts: Double? = nil
    var memoryBandwidthBytesPerSec: Double? = nil
}

/// 复用统一刷新节奏读取 IOReport 累计能量与总线吞吐，不创建独立轮询定时器，也不在采样线程 sleep。
///
/// 数据口径：
/// - 内建屏：DCP / display stats / power，实测为累计微焦耳；
/// - GPU：Energy Model 下的 GPU Energy channel，按 channel 自带 unit 解码；
/// - 内存总线：PMP / DSID Stats 下的各组 Misses 计数，计数单位即字节（多线程流式读负载实测：
///   本计数净增速率与负载实际字节速率之比 ≈1.05，每次 Miss 对应 64B 的假设已被否定）。
///
/// IOReport 为私有 API，因此本文件只属于未沙盒化的 Direct target。
final class IOReportPowerSampler {
    static let shared = IOReportPowerSampler()

    private enum ChannelID: Hashable {
        case display
        case gpu
        case memory
    }

    private struct Counter {
        let value: Int64
        let scale: Double
    }

    private struct Baseline {
        let value: Int64
        let uptime: TimeInterval
    }

    private let displaySubscription = Subscription(
        group: "DCP",
        subgroup: "display stats",
        channelNames: ["power"]
    )
    private let energySubscription = Subscription(
        group: "Energy Model",
        subgroup: nil,
        channelNames: ["GPU Energy"]
    )
    private let memorySubscription = Subscription(
        group: "PMP",
        subgroup: "DSID Stats",
        filter: { $0.hasSuffix("Misses") }
    )

    private var baselines: [ChannelID: Baseline] = [:]
    private var lastSample = IOReportPowerSample()
    private var lastSampleUptime: TimeInterval = 0
    /// 互斥保护 baselines/lastSample，使 sample() 可安全跨线程调用。
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
            if let channel = energyChannels["GPU Energy"],
               let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                counters[.gpu] = Counter(value: channel.value, scale: scale)
            }
        }

        if let memChannels = memorySubscription?.sampleChannels(), !memChannels.isEmpty {
            let totalMisses = memChannels.values.reduce(Int64(0)) { $0 + $1.value }
            counters[.memory] = Counter(value: totalMisses, scale: 1.0)
        }

        let sample = IOReportPowerSample(
            displayWatts: rate(for: .display, counter: counters[.display], uptime: uptime, maxRate: 1_000),
            gpuWatts: rate(for: .gpu, counter: counters[.gpu], uptime: uptime, maxRate: 1_000),
            memoryBandwidthBytesPerSec: rate(for: .memory, counter: counters[.memory], uptime: uptime, maxRate: 2_000_000_000_000)
        )
        lastSample = sample
        lastSampleUptime = uptime
        return sample
    }

    private func rate(for id: ChannelID, counter: Counter?, uptime: TimeInterval, maxRate: Double) -> Double? {
        guard let counter else { return nil }
        defer { baselines[id] = Baseline(value: counter.value, uptime: uptime) }

        guard let baseline = baselines[id] else { return nil }
        let elapsed = uptime - baseline.uptime
        let (delta, overflow) = counter.value.subtractingReportingOverflow(baseline.value)

        // 首帧无基线；睡眠/长暂停后的跨窗口均值没有实时展示意义。
        guard !overflow, elapsed > 0, elapsed <= 30, delta >= 0 else { return nil }
        let result = Double(delta) * counter.scale / elapsed
        guard result.isFinite, result >= 0, result <= maxRate else { return nil }
        return result
    }

    /// IOReport unit:高 8 位为 quantity(3 = Energy)，bits 32...39 的 SI exponent
    /// 使用 excess-127 编码。CPU 实测为 10^-3 J/count，GPU 为 10^-9 J/count。
    static func energyJoulesPerCount(unit: UInt64) -> Double? {
        let quantity = UInt8((unit >> 56) & 0xff)
        let encodedExponent = UInt8((unit >> 32) & 0xff)
        guard quantity == 3, encodedExponent != 0 else { return nil }
        return pow(10, Double(Int(encodedExponent) - 127))
    }
}

private final class Subscription {
    struct ChannelValue {
        let value: Int64
        let unit: UInt64
    }

    private let subscription: CFTypeRef
    private let subscribedChannels: CFMutableDictionary

    init?(group: String, subgroup: String?, channelNames: Set<String>? = nil, filter: ((String) -> Bool)? = nil) {
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

        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let createdSubscription = IOReportCreateSubscription(
            nil,
            mutableChannels,
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
}
