import Foundation
import IOKit

nonisolated struct PowerChannelDescriptor: Hashable, Sendable {
    let driver: UInt64
    let channel: UInt64
    let name: String
    let format: Int32
    let unit: UInt64
    var identity: String { "\(driver):\(channel):\(format):\(unit)" }

    static func read(_ channel: CFDictionary) -> Self? {
        guard let name = IOReportChannelGetChannelName(channel)?.takeUnretainedValue() as String? else { return nil }
        return Self(driver: IOReportChannelGetDriverID(channel), channel: IOReportChannelGetChannelID(channel),
                    name: name, format: IOReportChannelGetFormat(channel), unit: IOReportChannelGetUnit(channel))
    }
}

nonisolated struct PowerChannelRecord: Sendable {
    let descriptor: PowerChannelDescriptor
    let value: Int64
    let timestamp: UInt64

    static func decode(descriptor: PowerChannelDescriptor, bytes: Data, value: Int64, clock: UInt64) -> Self? {
        guard bytes.count >= 64 else { return nil }
        return bytes.withUnsafeBytes { raw in
            let driver = raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self)
            let id = raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
            let stamp = raw.loadUnaligned(fromByteOffset: 24, as: UInt64.self)
            guard driver == descriptor.driver, id == descriptor.channel, stamp <= clock else { return nil }
            return Self(descriptor: descriptor, value: value, timestamp: stamp)
        }
    }
}

nonisolated struct PowerChannelSnapshot: Sendable {
    let expected: Set<PowerChannelDescriptor>
    let records: [PowerChannelRecord]
    let generation: UInt64

    /// 必需成员完整匹配；任一成员缺失或单位不符时整组拒绝。
    func counters(named accepts: (String) -> Bool, display: Bool = false) -> [PowerEnergyCounter]? {
        let wanted = expected.filter { accepts($0.name) }
        guard !wanted.isEmpty else { return nil }
        let wantedIDs = Set(wanted.map { "\($0.driver):\($0.channel)" })
        let actual = records.filter { wantedIDs.contains("\($0.descriptor.driver):\($0.descriptor.channel)") }
        guard actual.count == wanted.count, Set(actual.map(\.descriptor)) == wanted else { return nil }
        var result: [PowerEnergyCounter] = []
        for record in actual {
            guard record.descriptor.format == 1 else { return nil }
            let scale: Double?
            if display {
                // DCP 以事件单位发布累计 µJ，按已确认编码换算。
                scale = record.descriptor.unit == 0x6400000000000000 ? 1e-6 : nil
            } else {
                scale = PowerEnergyUnit.joulesPerCount(record.descriptor.unit)
            }
            guard let scale else { return nil }
            result.append(PowerEnergyCounter(identity: "\(generation):\(record.descriptor.identity)",
                value: record.value, joulesPerCount: scale, timestamp: record.timestamp))
        }
        return result
    }
}

/// 底层订阅仅由采样器锁内访问；请求集合和实际返回分别校验。
nonisolated final class IOReportSubscription {
    struct StateSeries {
        let subgroup: String
        let states: [(name: String, ticks: Int64)]
    }
    private let subscription: CFTypeRef
    private let channels: CFMutableDictionary
    let expected: Set<PowerChannelDescriptor>

    convenience init?(group: String, subgroup: String?, accepts: (String) -> Bool,
                      subgroupFilter: ((String) -> Bool)? = nil) {
        guard let copied = IOReportCopyChannelsInGroup(group as CFString, subgroup as CFString?, 0, 0)?.takeRetainedValue(),
              let all = (copied as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return nil }
        let selected = all.filter { channel in
            let cf = channel as CFDictionary
            guard let name = IOReportChannelGetChannelName(cf)?.takeUnretainedValue() as String?, accepts(name) else { return false }
            if let subgroupFilter {
                let subgroup = IOReportChannelGetSubGroup(cf)?.takeUnretainedValue() as String? ?? ""
                return subgroupFilter(subgroup)
            }
            return true
        }
        self.init(requested: selected)
    }

    init?(requested: [NSDictionary]) {
        var descriptors = Set<PowerChannelDescriptor>()
        let selected = requested.filter { channel in
            guard let descriptor = PowerChannelDescriptor.read(channel as CFDictionary) else { return false }
            return descriptors.insert(descriptor).inserted
        }
        guard !selected.isEmpty,
              let request = CFDictionaryCreateMutableCopy(nil, 0, ["IOReportChannels": selected] as CFDictionary) else { return nil }
        var output: Unmanaged<CFMutableDictionary>?
        guard let created = IOReportCreateSubscription(nil, request, &output, 0, nil)?.takeRetainedValue(),
              let subscribed = output?.takeRetainedValue() else { return nil }
        subscription = created
        channels = subscribed
        expected = descriptors
    }

    func report() -> CFDictionary? {
        guard let report = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue(),
              let values = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary],
              !values.isEmpty else { return nil }
        return report
    }

    func snapshot(in report: CFDictionary, generation: UInt64) -> PowerChannelSnapshot? {
        guard let all = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return nil }
        var records: [PowerChannelRecord] = []
        for channel in all {
            let cf = channel as CFDictionary
            guard let descriptor = PowerChannelDescriptor.read(cf) else { continue }
            guard let bytes = channel["RawElements"] as? Data,
                  let record = PowerChannelRecord.decode(descriptor: descriptor, bytes: bytes,
                      value: IOReportSimpleGetIntegerValue(cf, 0), clock: mach_absolute_time()) else { continue }
            records.append(record)
        }
        return PowerChannelSnapshot(expected: expected, records: records, generation: generation)
    }

    static func clpc() -> IOReportSubscription? {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleCLPC"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var requested: [NSDictionary] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var driver: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &driver) == KERN_SUCCESS,
                  let bundle = IORegistryEntryCreateCFProperty(service, "CFBundleIdentifier" as CFString, nil, 0)?.takeRetainedValue() as? String,
                  let reports = CLPCPowerChannels.reports(bundle: bundle, majorVersion: 27) else { continue }
            for report in reports {
                let dictionary: NSDictionary = [
                    "DriverID": NSNumber(value: driver), "DriverName": "AppleCLPC",
                    "IOReportGroupName": "CLPC", "IOReportSubGroupName": "Energy Counters",
                    "IOReportChannelInfo": ["IOReportChannelUnit": NSNumber(value: CLPCPowerChannels.nanojoules)],
                    "LegendChannel": [NSNumber(value: report.id), NSNumber(value: UInt64(1 | (2 << 16) | (1 << 32))), report.name]
                ]
                // IOReport getters 会缓存派生字段，传入可变 CF 字典。
                if let mutable = CFDictionaryCreateMutableCopy(nil, 0, dictionary as CFDictionary) {
                    requested.append(mutable as NSDictionary)
                }
            }
        }
        return IOReportSubscription(requested: requested)
    }

    func stateSeries(in report: CFDictionary) -> [StateSeries] {
        guard let channels = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return [] }
        return channels.compactMap { channel in
            let cf = channel as CFDictionary
            guard IOReportChannelGetFormat(cf) == 2 else { return nil }
            let count = IOReportStateGetCount(cf)
            guard count > 0 else { return nil }
            let states: [(name: String, ticks: Int64)] = (0..<count).map { index in
                let name = IOReportStateGetNameForIndex(cf, index)?.takeUnretainedValue() as String? ?? "\(index)"
                return (name, IOReportStateGetResidency(cf, index))
            }
            return StateSeries(subgroup: IOReportChannelGetSubGroup(cf)?.takeUnretainedValue() as String? ?? "", states: states)
        }
    }
}
