import AppKit
import SwiftUI

/// 智能洞察建议视图：根据长周期与短周期监控数据，自动提炼系统负荷特征、峰值时段与调优建议。
struct ReportInsightsView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    var body: some View {
        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            insightsCard
        }
        .frame(maxWidth: .infinity)
    }

    private var insightsCard: some View {
        let items = viewModel.rangeModel?.insights ?? []

        return ReportCardView(
            title: String(localized: "stats.r.secInsights", defaultValue: "智能诊断与运行洞察"),
            icon: "sparkles"
        ) {
            // R04: 中性空态，不夸大“未发现瓶颈”
            if items.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyInsightsNeutral", defaultValue: "所选时间范围内未提炼出突出的运行建议或指标异动"))
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        insightRow(item: item)
                    }
                }
            }
        }
    }

    private func insightRow(item: ReportInsightItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor(for: item.colorName))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func iconColor(for colorName: String) -> Color {
        switch colorName {
        case "red": return Color(hex: 0xFF3B30)
        case "orange": return Color(hex: 0xFF9500)
        case "yellow": return Color(hex: 0xF5A623)
        case "green": return Color(hex: 0x34C759)
        case "blue": return Color(hex: 0x007AFF)
        default: return Color.accentColor
        }
    }
}
