import SwiftUI

/// 成对读数共用标签、数值与几何，网络和电源行保持一致的高度和右缘对齐。
enum RowHeaderPillMetrics {
    static let width: CGFloat = 70
    static let height: CGFloat = 26
    static let cornerRadius = CGFloat(MonitorConstants.rowCornerRadius) - verticalPadding
    static let labelSize: CGFloat = 9
    static let valueSize: CGFloat = 10
    static let horizontalPadding: CGFloat = 5
    static let verticalPadding = (MonitorConstants.panelRowHeaderHeight - height) / 2
    /// 右缘与上下留白等距，内层转角沿主行轮廓内缩。
    static let trailingPadding = verticalPadding
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
        .accessibilityElement(children: .combine)
    }
}

struct NetworkHeaderPills: View {
    let upload: String
    let download: String
    let theme: MonitorPanelTheme

    var body: some View {
        PairedHeaderReadings(theme: theme) {
            MetricLabelPill(title: String(localized: "panel.network.upload"), value: upload, theme: theme)
            MetricLabelPill(title: String(localized: "panel.network.download"), value: download, theme: theme)
        }
    }
}

/// 一层浅底承载成对读数，避免重复的独立轮廓与主行争夺视觉重点。
struct PairedHeaderReadings<Content: View>: View {
    let theme: MonitorPanelTheme
    let content: Content

    init(theme: MonitorPanelTheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        HStack(spacing: RowHeaderPillMetrics.spacing) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
        .background {
            RoundedRectangle(cornerRadius: RowHeaderPillMetrics.cornerRadius, style: .continuous)
                .fill(theme.trackFill)
        }
    }
}
