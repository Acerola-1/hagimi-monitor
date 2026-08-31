import CoreFoundation
import Foundation

/// Direct 版专用的分项功耗读数。所有字段均为最近两个应用采样帧之间的平均功率(W)。
struct IOReportPowerSample {
    var displayWatts: Double? = nil
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
}

/// 复用电池模块既有刷新节奏读取 IOReport 累计能量，不创建定时器，也不在采样线程 sleep。
///
/// 数据口径：
/// - 内建屏：DCP / display stats / power，实测为累计微焦耳；
/// - CPU/GPU：Energy Model 下各自的 Energy channel，按 channel 自带 unit 解码。
///
/// IOReport 为私有 API，因此本文件只属于未沙盒化的 Direct target。
final class IOReportPowerSampler {
    private enum ChannelID: Hashable {
        case display
        case cpu
        case gpu
    }

    private struct Counter {
        let value: Int64
        let joulesPerCount: Double
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
        channelNames: ["CPU Energy", "GPU Energy"]
    )
    private var baselines: [ChannelID: Baseline] = [:]

    func sample() -> IOReportPowerSample {
        let uptime = ProcessInfo.processInfo.systemUptime
        var counters: [ChannelID: Counter] = [:]

        if let channel = displaySubscription?.sampleChannels()["power"] {
            // DCP 的 power channel unit 标记为 dimensionless，但实测计数是累计 µJ。
            counters[.display] = Counter(value: channel.value, joulesPerCount: 1e-6)
        }

        if let energyChannels = energySubscription?.sampleChannels() {
            if let channel = energyChannels["CPU Energy"],
               let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                counters[.cpu] = Counter(value: channel.value, joulesPerCount: scale)
            }
            if let channel = energyChannels["GPU Energy"],
               let scale = Self.energyJoulesPerCount(unit: channel.unit) {
                counters[.gpu] = Counter(value: channel.value, joulesPerCount: scale)
            }
        }

        return IOReportPowerSample(
            displayWatts: watts(for: .display, counter: counters[.display], uptime: uptime),
            cpuWatts: watts(for: .cpu, counter: counters[.cpu], uptime: uptime),
            gpuWatts: watts(for: .gpu, counter: counters[.gpu], uptime: uptime)
        )
    }

    private func watts(for id: ChannelID, counter: Counter?, uptime: TimeInterval) -> Double? {
        guard let counter else { return nil }
        defer { baselines[id] = Baseline(value: counter.value, uptime: uptime) }

        guard let baseline = baselines[id] else { return nil }
        let elapsed = uptime - baseline.uptime
        let (delta, overflow) = counter.value.subtractingReportingOverflow(baseline.value)

        // 首帧无基线；睡眠/长暂停后的跨窗口均值没有实时展示意义。
        guard !overflow, elapsed > 0, elapsed <= 30, delta >= 0 else { return nil }
        let result = Double(delta) * counter.joulesPerCount / elapsed
        guard result.isFinite, result >= 0, result <= 1_000 else { return nil }
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

    init?(group: String, subgroup: String?, channelNames: Set<String>) {
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
            return channelNames.contains(stringName) && foundNames.insert(stringName).inserted
        }
        guard foundNames == channelNames,
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
