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

/// 菜单栏指标的前缀形态:SF 图标(紧凑)或文字(CPU/GPU…)。
enum MenuBarMetricPrefixStyle: String, CaseIterable, Identifiable {
    case icon
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon:
            String(localized: "menu-bar-metric-prefix.icon")
        case .text:
            String(localized: "menu-bar-metric-prefix.text")
        }
    }
}

enum MenuBarMetricKind: String, CaseIterable, Identifiable {
    case cpuUsage
    case gpuUsage
    case memoryUsage
    case batteryLevel
    case networkDownload
    case networkUpload
    case cpuTemperature
    case storageFree

    static let defaultSelection: [MenuBarMetricKind] = [.cpuUsage]
    static let maximumSelectionCount = 4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuUsage:
            String(localized: "menu-bar-metric.cpu-usage")
        case .gpuUsage:
            String(localized: "menu-bar-metric.gpu-usage")
        case .memoryUsage:
            String(localized: "menu-bar-metric.memory-usage")
        case .batteryLevel:
            String(localized: "menu-bar-metric.battery-level")
        case .networkDownload:
            String(localized: "menu-bar-metric.network-download")
        case .networkUpload:
            String(localized: "menu-bar-metric.network-upload")
        case .cpuTemperature:
            String(localized: "menu-bar-metric.cpu-temperature")
        case .storageFree:
            String(localized: "menu-bar-metric.storage-free")
        }
    }

    var symbol: String {
        switch self {
        case .cpuUsage:
            "cpu"
        case .gpuUsage:
            "display"
        case .memoryUsage:
            "memorychip"
        case .batteryLevel:
            "battery.75percent"
        case .networkDownload:
            "arrow.down"
        case .networkUpload:
            "arrow.up"
        case .cpuTemperature:
            "thermometer.medium"
        case .storageFree:
            "externaldrive"
        }
    }

    var menuBarPrefix: String {
        switch self {
        case .cpuUsage:
            "CPU"
        case .gpuUsage:
            "GPU"
        case .memoryUsage:
            "MEM"
        case .batteryLevel:
            "BAT"
        case .networkDownload:
            ""
        case .networkUpload:
            ""
        case .cpuTemperature:
            "TEMP"
        case .storageFree:
            "FREE"
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

    private static func compactCapacity(_ value: Double) -> String {
        let safeValue = max(0, value)
        let units = ["B", "K", "M", "G", "T"]
        var scaled = safeValue
        var unitIndex = 0

        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
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

        while scaled >= 1024, unitIndex < units.count - 1 {
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
