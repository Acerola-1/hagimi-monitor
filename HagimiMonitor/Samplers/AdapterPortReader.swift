import Foundation
import IOKit

/// 充电端口的物理标识与同口并行通道。
struct AdapterPortInfo: Equatable {
    /// 物理端口标签,如 "USB-C 4";端口类型读不到时退化为号数,全缺为 nil。
    var portLabel: String?
    /// 同口活动的数据通道,如 "DP·USB2";只有功率协商通道时为 nil。
    var transports: String?
}

/// 读充电端口的两类 IOPort 节点(App Store / Direct 通用,纯 IORegistry 读取,
/// 不含 IOServiceOpen,单次双类查找实测约 0.3 ms):
///   - `IOPortFeaturePowerSource`:随 PD 伙伴接入出现的供电源节点,携带所属端口;
///   - `IOAccessoryManagerUSBC`:该端口的链路状态,携带当前活动的传输通道。
/// 先由前者定位「本轮胜出的供电口」,再到后者取该口的通道列表;定位不到返回 nil。
enum AdapterPortReader {
    static func read() -> AdapterPortInfo? {
        guard let power = winningPowerSource() else { return nil }
        var info = AdapterPortInfo(portLabel: power.label)
        if let number = power.portNumber {
            info.transports = activeTransports(portNumber: number)
        }
        return info
    }

    // MARK: - 胜出的供电口

    private struct PowerSource {
        var portNumber: Int?
        var label: String?
    }

    /// 胜出的供电源节点:接入 PD 伙伴的口带 `WinningPowerSourceOption`,
    /// 未接入的同族节点(如 Brick ID,Priority -500)没有 winner。
    /// 有 winner 的优先,同为 winner(或同为无 winner)时取 Priority 高者。
    private static func winningPowerSource() -> PowerSource? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortFeaturePowerSource"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: (score: Int, source: PowerSource)?
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard let props = properties(of: entry),
                  (props["PowerSourceName"] as? String) == "USB-PD" else { continue }
            let number = props["ParentPortNumber"] as? Int
            let type = (props["ParentPortTypeDescription"] as? String)?.trimmingCharacters(in: .whitespaces)
            let source = PowerSource(portNumber: number, label: portLabel(type: type, number: number))
            // 胜出档位抬高一个量级,保证「有 winner 的节点」恒优于同族无 winner 者,
            // 同档内再比固件的 Priority。
            let score = (props["WinningPowerSourceOption"] != nil ? 1_000_000 : 0) + (intValue(props["Priority"]) ?? 0)
            if let current = best, current.score >= score { continue }
            best = (score: score, source: source)
        }
        return best?.source
    }

    /// 端口标签:类型 + 号数(如 "USB-C 4")。号数只在 USB-C 家族附加——
    /// 同机型有多个同型口,号数是唯一的物理区分;MagSafe 全机一个,固件的内部
    /// 索引与用户看到的 "MagSafe 3" 对不上,只留类型。
    private static func portLabel(type: String?, number: Int?) -> String? {
        guard let type, !type.isEmpty else { return number.map(String.init) }
        guard let number, type.uppercased().contains("USB") else { return type }
        return "\(type) \(number)"
    }

    // MARK: - 同口传输通道

    /// 该端口当前活动的传输通道。功率协商通道(CC)不参与展示:它随 PD 供电必然
    /// 存在,显示它等于每行重复一次「在充电」;DP / USB 才回答「这个口还跑了什么」。
    private static func activeTransports(portNumber: Int) -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccessoryManagerUSBC"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard let props = properties(of: entry),
                  (props["PortNumber"] as? Int) == portNumber,
                  let active = props["TransportsActive"] as? [String] else { continue }
            return shortTransports(active)
        }
        return nil
    }

    /// 通道短名与固定显示序;未登记的通道名不展示(固件新增通道时宁缺勿猜)。
    private static let transportNames: [(match: (String) -> Bool, short: String)] = [
        ({ $0.caseInsensitiveCompare("DisplayPort") == .orderedSame }, "DP"),
        ({ $0.uppercased().hasPrefix("USB3") }, "USB3"),
        ({ $0.uppercased().hasPrefix("USB2") }, "USB2"),
        ({ $0.caseInsensitiveCompare("CIO") == .orderedSame }, "CIO")
    ]

    private static func shortTransports(_ active: [String]) -> String? {
        let names = transportNames.compactMap { entry in
            active.contains(where: entry.match) ? entry.short : nil
        }
        return names.isEmpty ? nil : names.joined(separator: "·")
    }

    // MARK: - IORegistry 读取

    private static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return props?.takeRetainedValue() as? [String: Any]
    }

    private static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}
