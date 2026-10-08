import SwiftUI

/// 成对读数共用标签、数值与几何，网络和电源行保持一致的高度和右缘对齐。
enum RowHeaderPillMetrics {
    static let width: CGFloat = 70
    static let height: CGFloat = 26
    static let labelSize: CGFloat = 9
    static let valueSize: CGFloat = 10
    static let horizontalPadding: CGFloat = 5
    static let verticalPadding = (MonitorConstants.panelRowHeaderHeight - height) / 2
    static let spacing: CGFloat = 6
}

struct MetricLabelPill: View {
    let title: String
    let value: String
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: RowHeaderPillMetrics.labelSize))
                .foregroundStyle(theme.secondaryText.opacity(0.72))
                .fixedSize()
            Text(value)
                .font(.system(size: RowHeaderPillMetrics.valueSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
                .fixedSize()
        }
        .padding(.horizontal, RowHeaderPillMetrics.horizontalPadding)
        .frame(width: RowHeaderPillMetrics.width, height: RowHeaderPillMetrics.height)
        .background(Capsule().fill(theme.trackFill))
        .accessibilityElement(children: .combine)
    }
}

struct NetworkHeaderPills: View {
    let upload: String
    let download: String
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: RowHeaderPillMetrics.spacing) {
            MetricLabelPill(title: String(localized: "panel.network.upload"), value: upload, theme: theme)
            MetricLabelPill(title: String(localized: "panel.network.download"), value: download, theme: theme)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
