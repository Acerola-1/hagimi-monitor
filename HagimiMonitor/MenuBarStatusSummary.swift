import Foundation

/// 菜单栏主状态项的悬停摘要与 VoiceOver 无障碍文本模型。
/// 保持纯值语义，只在悬停触发或状态项变化时按需格式化，避免秒级采样期间做多余的字符串拼接。
nonisolated struct MenuBarStatusSummary: Equatable, Sendable {
    let combinedLoad: Double
    let coreLevel: MenuBarCoreLevel
    let cpuUsage: Double
    let gpuUsage: Double
    let memoryPressure: MemoryPressureLevel
    let showsAlert: Bool
    let showsHUDBadge: Bool

    var roundedCombined: Int { Self.clampedRoundedPercentage(combinedLoad) }
    var roundedCPU: Int { Self.clampedRoundedPercentage(cpuUsage) }
    var roundedGPU: Int { Self.clampedRoundedPercentage(gpuUsage) }

    var tooltipText: String {
        var lines = [
            String(localized: "menu-bar-ring.tooltip.headline \(roundedCombined) \(levelTitle)"),
            String(localized: "menu-bar-ring.tooltip.breakdown \(roundedCPU) \(roundedGPU) \(memoryPressureTitle)")
        ]
        let badges = activeStatusBadges
        if !badges.isEmpty {
            lines.append(badges.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    var accessibilityValue: String {
        let base = String(
            localized: "menu-bar-ring.accessibility.value \(roundedCombined) \(levelTitle) \(roundedCPU) \(roundedGPU) \(memoryPressureTitle)"
        )
        let badges = activeStatusBadges
        guard !badges.isEmpty else { return base }
        return ([base] + badges).joined(separator: "; ")
    }

    private var levelTitle: String {
        switch coreLevel {
        case .normal:
            String(localized: "menu-bar-ring.level.normal")
        case .busy:
            String(localized: "menu-bar-ring.level.busy")
        case .stressed:
            String(localized: "menu-bar-ring.level.stressed")
        }
    }

    private var memoryPressureTitle: String {
        switch memoryPressure {
        case .normal:
            String(localized: "memory-pressure.normal")
        case .warning:
            String(localized: "memory-pressure.warning")
        case .critical:
            String(localized: "memory-pressure.critical")
        case .unknown:
            String(localized: "memory-pressure.unknown")
        }
    }

    private var activeStatusBadges: [String] {
        var result: [String] = []
        if showsAlert {
            result.append(String(localized: "menu-bar-ring.tooltip.alert"))
        }
        if showsHUDBadge {
            result.append(String(localized: "menu-bar-ring.tooltip.hud"))
        }
        return result
    }

    private static func clampedRoundedPercentage(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100.0, max(0.0, value)).rounded())
    }
}
