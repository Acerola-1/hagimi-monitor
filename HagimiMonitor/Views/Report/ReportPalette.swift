import AppKit
import SwiftUI

/// 原生报表统一调色板：基于 `MonitorPalette` 派生，保证明暗外观及活力/平衡主题全模块视觉一致。
struct ReportPalette {
    let base: MonitorPalette
    let colorScheme: ColorScheme

    init(preference: MonitorColorSchemePreference, colorScheme: ColorScheme) {
        self.base = MonitorPalette(preference: preference, colorScheme: colorScheme)
        self.colorScheme = colorScheme
    }

    private var isDark: Bool { colorScheme == .dark }

    // MARK: - 表面与描边层级（消除浅色灰底灰卡反差不足）

    var cardFill: Color {
        isDark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.55)
            : Color(nsColor: .controlBackgroundColor).opacity(0.84)
    }

    var cardHoverFill: Color {
        isDark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.75)
            : Color(nsColor: .controlBackgroundColor).opacity(0.96)
    }

    var cardBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var insetFill: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.035)
    }

    var sidebarFill: Color {
        isDark
            ? Color(nsColor: .windowBackgroundColor).opacity(0.35)
            : Color(nsColor: .windowBackgroundColor).opacity(0.58)
    }

    var topBarFill: Color {
        isDark
            ? Color(nsColor: .windowBackgroundColor).opacity(0.50)
            : Color(nsColor: .windowBackgroundColor).opacity(0.72)
    }

    // MARK: - 结论横幅与洞察卡片语义表面

    func bannerFill(isElevated: Bool) -> Color {
        guard isElevated else {
            return isDark
                ? Color(nsColor: .controlBackgroundColor).opacity(0.60)
                : Color(nsColor: .controlBackgroundColor).opacity(0.88)
        }
        return base.severityTint(for: .warning).opacity(isDark ? 0.14 : 0.08)
    }

    func bannerBorder(isElevated: Bool) -> Color {
        guard isElevated else { return cardBorder }
        return base.severityTint(for: .warning).opacity(isDark ? 0.35 : 0.28)
    }

    func insightFill(for severity: ReportInsightItem.Severity) -> Color {
        switch severity {
        case .neutral: return cardFill
        case .info: return Color.accentColor.opacity(isDark ? 0.08 : 0.045)
        case .warning: return base.severityTint(for: .warning).opacity(isDark ? 0.12 : 0.065)
        case .critical: return base.severityTint(for: .critical).opacity(isDark ? 0.14 : 0.075)
        }
    }

    func insightBorder(for severity: ReportInsightItem.Severity) -> Color {
        switch severity {
        case .neutral: return cardBorder
        case .info: return Color.accentColor.opacity(0.20)
        case .warning: return base.severityTint(for: .warning).opacity(0.26)
        case .critical: return base.severityTint(for: .critical).opacity(0.30)
        }
    }

    func insightTint(for severity: ReportInsightItem.Severity, colorName: String) -> Color {
        switch severity {
        case .critical: return base.severityTint(for: .critical)
        case .warning: return base.severityTint(for: .warning)
        case .info:
            switch colorName {
            case "yellow": return power
            default: return Color.accentColor
            }
        case .neutral:
            switch colorName {
            case "green": return base.severityTint(for: .calm)
            case "blue": return Color.accentColor
            default: return .secondary
            }
        }
    }

    // MARK: - 评分与事件状态语义色

    func scoreTint(for level: StatisticsHealthScore.Level?) -> Color {
        guard let level else { return .secondary }
        switch level {
        case .low: return base.severityTint(for: .calm)
        case .mild: return Color.accentColor
        case .elevated: return base.severityTint(for: .warning)
        case .high: return base.severityTint(for: .critical)
        }
    }

    /// 压力事件胶囊配色：进行中的系统压力用 warning/critical；已恢复历史事件一律使用中性次要色，避免用绿色误导用户。
    func pressureEventChipTint(worstLevel: Int, isOngoing: Bool) -> Color {
        guard isOngoing else { return .secondary }
        return base.severityTint(for: worstLevel >= 2 ? .critical : .warning)
    }

    func eventStateTint(for state: ReportEventItem.State) -> Color {
        switch state {
        case .ongoing: return base.severityTint(for: .critical)
        case .interrupted: return base.severityTint(for: .warning)
        case .recovered: return .secondary
        }
    }

    func thermalLevelTint(_ level: Int?) -> Color {
        guard let level else { return .secondary }
        switch level {
        case 0: return base.severityTint(for: .calm)
        case 1: return base.severityTint(for: .warning)
        default: return base.severityTint(for: .critical)
        }
    }

    // MARK: - 模块与图表系列色（单源来自 MonitorPalette）

    var cpu: Color { base.moduleTint(for: .cpu) }
    var cpuPeak: Color { base.severityTint(for: .warning) }
    var pCore: Color { base.performanceCoreTint }
    var eCore: Color { base.efficiencyCoreTint }
    var cpuUser: Color { Color(hex: isDark ? 0x5CC8FF : 0x0284C7) }
    var cpuSystem: Color { base.displayTint }

    var gpu: Color { base.moduleTint(for: .gpu) }
    var gpuVram: Color { Color(hex: isDark ? 0xB388FF : 0x7C3AED) }

    var memory: Color { base.moduleTint(for: .memory) }
    var memoryUsageLine: Color { base.moduleTint(for: .memory).opacity(0.62) }
    var memoryCompressed: Color { Color(hex: isDark ? 0xF472B6 : 0xDB2777) }
    var memoryPressure: Color { base.severityTint(for: .critical) }
    var memorySwap: Color { Color(hex: isDark ? 0x818CF8 : 0x4F46E5) }

    var networkDown: Color { base.moduleTint(for: .network) }
    var networkUp: Color { Color(hex: isDark ? 0xA78BFA : 0x7C3AED) }

    var diskRead: Color { base.moduleTint(for: .storage) }
    var diskWrite: Color { Color(hex: isDark ? 0x2DD4BF : 0x0D9488) }

    var power: Color { base.moduleTint(for: .battery) }
    var battery: Color { base.severityTint(for: .calm) }
    var thermal: Color { base.severityTint(for: .critical) }
    var fan: Color { base.moduleTint(for: .fan) }
}
