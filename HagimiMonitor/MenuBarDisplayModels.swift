import Foundation
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case ring
    case metrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ring:
            String(localized: "menu-bar-display.mode.ring")
        case .metrics:
            String(localized: "menu-bar-display.mode.metrics")
        }
    }
}

/// 菜单栏指标的显示布局:图标+数字、文字+数字(均为单行横排),或文字在上、数字在下的紧凑双层排布。
enum MenuBarMetricLayoutStyle: String, CaseIterable, Identifiable {
    case icon
    case text
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon:
            String(localized: "menu-bar-metric-layout.icon")
        case .text:
            String(localized: "menu-bar-metric-layout.text")
        case .compact:
            String(localized: "menu-bar-metric-layout.compact")
        }
    }
}

enum MenuBarMetricKind: String, CaseIterable, Identifiable {
    // CPU 组
    case cpuUsage
    case cpuTemperature
    // GPU 组
    case gpuUsage
    // 内存组
    case memoryUsage
    case memoryPressure
    // 网络组
    case networkDownload
    case networkUpload
    // 存储组
    case storageFree
    // 电源组
    case batteryLevel
    case systemPower
    // 散热组
    case fanSpeed

    /// 新用户默认勾选的菜单栏指标(最多 4 个)。
    /// CPU 温度依赖 SMC(AppleSMC user client),沙盒版无法读取,故仅在
    /// DISPLAY_CONTROL(GitHub 直连版)下纳入默认;沙盒版退化为 3 项,
    /// 避免「勾选了但选项列表里不存在」的幽灵指标。
    static let defaultSelection: [MenuBarMetricKind] = {
        var selection: [MenuBarMetricKind] = [.cpuUsage, .gpuUsage, .systemPower]
        #if DISPLAY_CONTROL
        selection.insert(.cpuTemperature, at: 1)
        #endif
        return selection
    }()
    static let maximumSelectionCount = 4

    /// 用户可选的菜单栏指标。温度与风扇均依赖 SMC(AppleSMC user client),
    /// App Store 沙盒版无法读取,故仅 DISPLAY_CONTROL(直连版)提供这两个选项。
    /// 风扇还需机器实际有风扇(FNum > 0),直连版运行时由 `hasFan` 参数门控,
    /// 无风扇机型设置里看不到该选项。
    static func userSelectableCases(hasFan: Bool) -> [MenuBarMetricKind] {
        var cases: [MenuBarMetricKind] = allCases
        #if !DISPLAY_CONTROL
        cases.removeAll { $0 == .cpuTemperature }
        cases.removeAll { $0 == .fanSpeed }
        #else
        if !hasFan {
            cases.removeAll { $0 == .fanSpeed }
        }
        #endif
        return cases
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuUsage:
            String(localized: "menu-bar-metric.cpu-usage")
        case .cpuTemperature:
            String(localized: "menu-bar-metric.cpu-temperature")
        case .gpuUsage:
            String(localized: "menu-bar-metric.gpu-usage")
        case .memoryUsage:
            String(localized: "menu-bar-metric.memory-usage")
        case .memoryPressure:
            String(localized: "menu-bar-metric.memory-pressure")
        case .networkDownload:
            String(localized: "menu-bar-metric.network-download")
        case .networkUpload:
            String(localized: "menu-bar-metric.network-upload")
        case .storageFree:
            String(localized: "menu-bar-metric.storage-free")
        case .batteryLevel:
            String(localized: "menu-bar-metric.battery-level")
        case .systemPower:
            String(localized: "menu-bar-metric.system-power")
        case .fanSpeed:
            String(localized: "menu-bar-metric.fan-speed")
        }
    }

    var symbol: String {
        switch self {
        case .cpuUsage:
            "cpu"
        case .cpuTemperature:
            "thermometer.medium"
        case .gpuUsage:
            "display"
        case .memoryUsage:
            "memorychip"
        case .memoryPressure:
            "gauge.medium"
        case .networkDownload:
            "arrow.down"
        case .networkUpload:
            "arrow.up"
        case .storageFree:
            "externaldrive"
        case .batteryLevel:
            "battery.75percent"
        case .systemPower:
            "bolt.fill"
        case .fanSpeed:
            "fan.fill"
        }
    }

    var menuBarPrefix: String {
        switch self {
        case .cpuUsage:
            String(localized: "menu-bar-metric-prefix.cpu-usage")
        case .cpuTemperature:
            String(localized: "menu-bar-metric-prefix.cpu-temperature")
        case .gpuUsage:
            String(localized: "menu-bar-metric-prefix.gpu-usage")
        case .memoryUsage:
            String(localized: "menu-bar-metric-prefix.memory-usage")
        case .memoryPressure:
            String(localized: "menu-bar-metric-prefix.memory-pressure")
        case .networkDownload:
            ""
        case .networkUpload:
            ""
        case .storageFree:
            String(localized: "menu-bar-metric-prefix.storage-free")
        case .batteryLevel:
            String(localized: "menu-bar-metric-prefix.battery-level")
        case .systemPower:
            String(localized: "menu-bar-metric-prefix.system-power")
        case .fanSpeed:
            String(localized: "menu-bar-metric-prefix.fan-speed")
        }
    }
}

struct MenuBarMetricItem: Identifiable, Equatable {
    let kind: MenuBarMetricKind
    let value: String

    var id: MenuBarMetricKind { kind }
}

enum MenuBarMetricFormatter {
    static let unavailable = "--"

    static func percentage(_ value: Double?) -> String {
        guard let value else { return unavailable }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }

    static func fixedPercentage(_ value: Double?) -> String {
        guard let value else { return " --%" }
        return String(format: "%3d%%", Int(min(100, max(0, value)).rounded()))
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return " --°" }
        return String(format: "%3d°", Int(value.rounded()))
    }

    static func throughput(_ value: Double?, direction: String) -> String {
        guard let value else { return direction + leftPad(unavailable, to: 4) }
        return direction + leftPad(compactRate(value), to: 4)
    }

    static func capacity(_ value: Double?) -> String {
        guard let value else { return leftPad(unavailable, to: 4) }
        return leftPad(compactCapacity(value), to: 4)
    }

    static func power(_ value: Double?) -> String {
        guard let value else { return leftPad(unavailable, to: 4) + "W" }
        return leftPad("\(Int(max(0, value).rounded()))", to: 3) + "W"
    }

    /// 风扇转速(单位 RPM)。固定 4 字符右对齐数字,无单位(参考 Stats 菜单栏):
    /// 9999 作 cap,极端值(Mac Pro 极限散热也很少破 8000 RPM)显示为 9999。
    /// nil(无风扇 / 读取失败)走 leftPad(unavailable, to: 4) 占位,保持 4 字符宽度。
    static func fanRPM(_ rpm: Int?) -> String {
        guard let rpm else { return leftPad(unavailable, to: 4) }
        let capped = min(rpm, 9999)
        return String(format: "%4d", capped)
    }

    private static func compactCapacity(_ value: Double) -> String {
        let safeValue = max(0, value)
        let units = ["B", "K", "M", "G", "T"]
        var scaled = safeValue
        var unitIndex = 0

        // 容量用1000进制(.file口径),与面板/Finder/系统设置的存储显示一致。
        while scaled >= 999.5, unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }

        if unitIndex == 0 || scaled >= 10 {
            return "\(Int(scaled.rounded()))\(units[unitIndex])"
        }
        return "\(String(format: "%.1f", scaled))\(units[unitIndex])"
    }

    private static func compactRate(_ value: Double) -> String {
        let safeValue = max(0, value)
        let units = ["B", "K", "M", "G"]
        var scaled = safeValue
        var unitIndex = 0

        while scaled >= 999.5, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 || scaled >= 10 {
            return "\(Int(scaled.rounded()))\(units[unitIndex])"
        }
        return "\(String(format: "%.1f", scaled))\(units[unitIndex])"
    }

    private static func leftPad(_ value: String, to length: Int) -> String {
        guard value.count < length else { return value }
        return String(repeating: " ", count: length - value.count) + value
    }
}
