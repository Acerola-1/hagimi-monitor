import SwiftUI

/// 面板内紧凑型胶囊切换器 (Mini Pill Tabs / Segmented Control)。
///
/// 设计语言严格遵循液态玻璃与面板规范:
/// - 静置态:圆角 3.5pt 的 `theme.trackFill` 衬底与 `theme.captionText` 弱对比字;
/// - 激活态:模块品牌色 `tint` 纯色圆角块与白色粗体文字;
/// - 交互动效:解析弹簧(`MonitorConstants.panelExpansionSpringResponse` / `panelExpansionSpringDamping`)无阶平滑过渡;
/// - 显示形态:支持文字胶囊或紧凑 SF Symbol 图标胶囊（跨语言无溢出），带原生 `.help` 悬浮气泡;
/// - 适用场景:行卡片标题右侧或展开区顶部的子视图切换(如时域切换、图表模式切换、多页翻页等)。
struct PanelCapsulePicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    var title: ((T) -> String)? = nil
    var icon: ((T) -> String)? = nil
    var tooltip: ((T) -> String)? = nil
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.id) { item in
                let isSelected = selection == item
                Button {
                    guard selection != item else { return }
                    withAnimation(
                        .spring(
                            response: MonitorConstants.panelExpansionSpringResponse,
                            dampingFraction: MonitorConstants.panelExpansionSpringDamping
                        )
                    ) {
                        selection = item
                    }
                } label: {
                    Group {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 8.5, weight: isSelected ? .bold : .medium))
                                .frame(width: 20, height: 16)
                        } else if let titleText = title?(item) {
                            Text(titleText)
                                .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 16, maxHeight: 16)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : theme.captionText)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(isSelected ? tint : theme.trackFill)
                    )
                }
                .buttonStyle(.plain)
                .help(tooltip?(item) ?? title?(item) ?? "")
            }
        }
    }
}

extension PanelCapsulePicker {
    /// 纯文本模式构造函数。
    init(
        selection: Binding<T>,
        items: [T],
        title: @escaping (T) -> String,
        tooltip: ((T) -> String)? = nil,
        tint: Color,
        theme: MonitorPanelTheme
    ) {
        self._selection = selection
        self.items = items
        self.title = title
        self.icon = nil
        self.tooltip = tooltip
        self.tint = tint
        self.theme = theme
    }

    /// 纯图标模式构造函数（宽度固定 20pt，杜绝多语言截断）。
    init(
        selection: Binding<T>,
        items: [T],
        icon: @escaping (T) -> String,
        tooltip: ((T) -> String)? = nil,
        tint: Color,
        theme: MonitorPanelTheme
    ) {
        self._selection = selection
        self.items = items
        self.title = nil
        self.icon = icon
        self.tooltip = tooltip
        self.tint = tint
        self.theme = theme
    }
}

extension PanelCapsulePicker where T: CaseIterable {
    /// CaseIterable 枚举便捷构造：文本模式。
    init(
        selection: Binding<T>,
        title: @escaping (T) -> String,
        tooltip: ((T) -> String)? = nil,
        tint: Color,
        theme: MonitorPanelTheme
    ) {
        self.init(
            selection: selection,
            items: Array(T.allCases),
            title: title,
            tooltip: tooltip,
            tint: tint,
            theme: theme
        )
    }

    /// CaseIterable 枚举便捷构造：图标模式。
    init(
        selection: Binding<T>,
        icon: @escaping (T) -> String,
        tooltip: ((T) -> String)? = nil,
        tint: Color,
        theme: MonitorPanelTheme
    ) {
        self.init(
            selection: selection,
            items: Array(T.allCases),
            icon: icon,
            tooltip: tooltip,
            tint: tint,
            theme: theme
        )
    }
}
