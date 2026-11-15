import Foundation
import IOKit

/// macOS 27 的 M3 CLPC 能量报告。映射取自 macmon (MIT)，见 THIRD-PARTY-NOTICES.md。
/// https://github.com/vladkens/macmon/blob/6ebbd71c2930f1b9a25a68eaf857dfd134ade606/src/clpc.rs
/// 已与本机 macOS 27.2.1 的 AppleT8122CLPC 报告表核对；其他驱动和系统主版本不套用。
nonisolated enum CLPCEnergyChannels {
    static func descriptors(osMajor: Int, driverBundle: String, driverID: UInt64) -> [NSMutableDictionary] {
        guard osMajor == 27, driverBundle == "com.apple.driver.AppleT8122CLPC" else { return [] }

        let reports: [(id: UInt64, name: String)] = [
            (0x0000_0010_54b5_1c99, "CPU Energy"),
            (0x0000_0018_960a_fe2f, "ANE")
        ]
        // IOReportTypes.h：单元素整数、power category；单位 nJ。
        let channelType: Int64 = 1 | (2 << 16) | (1 << 32)
        let unit: Int64 = (3 << 56) | (118 << 32)
        return reports.map { report in
            NSMutableDictionary(dictionary: [
                "DriverID": NSNumber(value: driverID),
                "DriverName": "AppleCLPC",
                "IOReportGroupName": "CLPC",
                "IOReportSubGroupName": "Energy Counters",
                "IOReportChannelInfo": ["IOReportChannelUnit": NSNumber(value: unit)],
                "LegendChannel": [NSNumber(value: report.id), NSNumber(value: channelType), report.name]
            ])
        }
    }

    static func currentDescriptors() -> [NSMutableDictionary] {
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard osMajor == 27 else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleCLPC"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var driverID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &driverID) == KERN_SUCCESS,
                  let bundle = IORegistryEntryCreateCFProperty(service, "CFBundleIdentifier" as CFString,
                                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
                continue
            }
            let channels = descriptors(osMajor: osMajor, driverBundle: bundle, driverID: driverID)
            if !channels.isEmpty { return channels }
        }
        return []
    }

    /// M3/macOS 27 的 DCP 屏幕计数在亮度对照中始终为零，不能作为有效零功耗。
    static func displayZeroIsUnavailable(osMajor: Int, cpuBrand: String?) -> Bool {
        osMajor == 27 && cpuBrand == "Apple M3"
    }
}
