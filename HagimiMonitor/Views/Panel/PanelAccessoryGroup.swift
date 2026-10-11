import SwiftUI

/// 同一设备或风扇系统的共同内衬，不增加独立材质采样。
struct PanelAccessoryGroup<Content: View>: View {
    let theme: MonitorPanelTheme
    @ViewBuilder var content: Content

    var body: some View {
        content.background {
            RoundedRectangle(cornerRadius: AccessoryDetailSizing.cornerRadius, style: .continuous)
                .fill(theme.trackFill)
        }
    }
}

/// 数量决定行数；末行不足列数时，实际项目平分整行，不生成空设备占位。
struct PanelAccessoryGrid<Content: View>: View {
    let count: Int
    let columns: Int
    let kind: MonitorKind
    let theme: MonitorPanelTheme
    @ViewBuilder var content: (Int) -> Content

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<((count + columns - 1) / columns), id: \.self) { row in
                if row > 0 {
                    Rectangle().fill(theme.rowSeparator(for: kind)).frame(height: 1)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach((row * columns)..<min((row + 1) * columns, count), id: \.self) { index in
                        content(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) {
                                if index % columns > 0 {
                                    Rectangle().fill(theme.rowSeparator(for: kind))
                                        .frame(width: 1)
                                        .padding(.vertical, AccessoryDetailSizing.inset)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
