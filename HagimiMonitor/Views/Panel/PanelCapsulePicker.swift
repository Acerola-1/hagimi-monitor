import SwiftUI

/// 面板内紧凑型胶囊切换器 (Mini Pill Tabs / Segmented Control)。
///
/// 设计语言严格遵循液态玻璃与面板规范:
/// - 静置态:圆角 3.5pt 的 `theme.trackFill` 衬底与 `theme.captionText` 弱对比字;
/// - 激活态:模块品牌色 `tint` 纯色圆角块与白色粗体文字;
/// - 交互动效:解析弹簧(`MonitorConstants.panelExpansionSpringResponse` / `panelExpansionSpringDamping`)无阶平滑过渡;
/// - 适用场景:行卡片标题右侧或展开区顶部的子视图切换(如时域切换、图表模式切换、多页翻页等)。
struct PanelCapsulePicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let title: (T) -> String
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
                    Text(title(item))
                        .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : theme.captionText)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 16, maxHeight: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(isSelected ? tint : theme.trackFill)
                        )
                }
                .buttonStyle(.plain)
                .help(tooltip?(item) ?? title(item))
            }
        }
    }
}

extension PanelCapsulePicker where T: CaseIterable {
    /// 针对符合 `CaseIterable` 的枚举类型的便捷构造函数。
    init(
        selection: Binding<T>,
        title: @escaping (T) -> String,
        tooltip: ((T) -> String)? = nil,
        tint: Color,
        theme: MonitorPanelTheme
    ) {
        self._selection = selection
        self.items = Array(T.allCases)
        self.title = title
        self.tooltip = tooltip
        self.tint = tint
        self.theme = theme
    }
}
