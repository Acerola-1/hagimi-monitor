import AppKit
import SwiftUI

/// 智能洞察建议视图：输出周期环比变化、压力归因、长期趋势与覆盖提示，并支持一键跳转定位。
struct ReportInsightsView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
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
        let tint = palette.insightTint(for: item.severity, colorName: item.colorName)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemIcon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
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

            if item.destination != nil {
                Button {
                    viewModel.focusOnInsight(item)
                } label: {
                    HStack(spacing: 4) {
                        Text(item.actionTitle ?? String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.insightFill(for: item.severity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(palette.insightBorder(for: item.severity), lineWidth: 0.75)
        }
    }
}
