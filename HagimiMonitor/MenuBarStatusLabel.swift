import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: MonitorStore
    let darkMode: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        switch store.settings.menuBarDisplayMode {
        case .ring:
            MenuBarLoadRingPreview(
                animator: store.loadAnimator,
                darkMode: darkMode,
                side: 18,
                increaseContrast: colorSchemeContrast == .increased
            )
            .help("HagimiMonitor")
        case .metrics:
            MenuBarMetricLabel(
                items: store.menuBarMetricItems,
                layoutStyle: store.settings.menuBarMetricLayoutStyle
            )
            .help("HagimiMonitor")
        }
    }
}

/// 高频订阅止于图标叶子；设置页和面板不因负载环动画重算整个内容树。
struct MenuBarLoadRingPreview: View {
    @ObservedObject var animator: MenuBarLoadAnimator
    let darkMode: Bool
    var side: CGFloat = 21
    var increaseContrast: Bool = false

    var body: some View {
        Image(nsImage: MenuBarComputeRingIcon.image(
            load: animator.displayedComputeLoad,
            darkMode: darkMode,
            coreLevel: animator.displayedCoreLevel,
            increaseContrast: increaseContrast
        ))
            .resizable()
            .frame(width: side, height: side)
    }
}

struct MenuBarMetricLabel: View {
    enum Style {
        case menuBar
        case preview
    }

    let items: [MenuBarMetricItem]
    var style: Style = .menuBar
    var layoutStyle: MenuBarMetricLayoutStyle = .icon

    var body: some View {
        switch layoutStyle {
        case .icon, .text:
            horizontalBody
        case .compact:
            compactBody
        }
    }

    /// 横排(icon/text):总宽由 `MenuBarMetricWidthEngine` 按各指标的最大预留一次性算死,
    /// 与任何实时数值无关--左右边缘与邻居图标的距离恒定不动;每格区域按「常用宽度」
    /// 划定,常用范围内的位数变化被区域内空白吸收,位置纹丝不动,富余均摊为格间间距。
    /// 字体与菜单栏观感同族(SF Rounded,引擎同源 NSFont 桥接),尾部单位小一号弱化。
    private var horizontalBody: some View {
        let layout = MenuBarMetricWidthEngine.horizontalLayout(for: items, layout: layoutStyle)
        return HStack(spacing: layout.gap) {
            ForEach(items) { item in
                horizontalCell(for: item)
            }
        }
        .font(Font(MenuBarMetricWidthEngine.horizontalValueFont))
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
        .frame(width: layout.totalWidth, alignment: .leading)
    }

    /// 紧凑(compact):各指标双层列宽恒定,整体宽度天然稳定,字体同为 rounded。
    private var compactBody: some View {
        HStack(spacing: MenuBarMetricWidthEngine.compactInterCellSpacing) {
            ForEach(items) { item in
                compactCell(for: item)
            }
        }
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
    }

    /// 横排单格:按「常用宽度」划定最小区域,前缀(SF 图标 / CPU / ↑↓ 等)+ 数值紧贴成对。
    /// 常用范围内的位数变化只伸缩区域内空白,不推动任何相邻内容;
    /// 冲出常用宽度时该格临时变宽、轻微收缩格间距(引擎侧计算)。
    private func horizontalCell(for item: MenuBarMetricItem) -> some View {
        HStack(
            alignment: layoutStyle == .text ? .firstTextBaseline : .center,
            spacing: symbolSpacing
        ) {
            leading(for: item.kind)
            valueText(for: item)
        }
        .frame(minWidth: MenuBarMetricWidthEngine.commonPairWidth(for: item.kind, layout: layoutStyle), alignment: .leading)
    }

    /// 数值:数字部分主字号,尾部单位字形小一号、弱化透明度(iStat 式层次)。
    /// 拆分口径与引擎的 measuredValueWidth 一一对应,测量/渲染同源。
    @ViewBuilder
    private func valueText(for item: MenuBarMetricItem) -> some View {
        splitValueView(
            numericValue(for: item),
            digitFont: nil,
            unitFont: Font(MenuBarMetricWidthEngine.unitFont),
            unitOpacity: 0.75
        )
    }

    /// 前缀视图:图标模式用弱化透明度 SF Symbol,文字模式用小一号次级文本标签。
    /// 仅由横排分支调用,紧凑模式走独立的 `compactCell`、不经过这里。
    @ViewBuilder
    private func leading(for kind: MenuBarMetricKind) -> some View {
        switch layoutStyle {
        case .icon:
            // icon 字号比文本小 2pt 并降轻微透明,让数字视觉权重明显大于标识。
            Image(systemName: kind.symbol)
                .font(.system(size: Self.iconFontSize, weight: .medium))
                .opacity(0.78)
        default:
            Text(Self.textPrefix(for: kind))
                .font(Font(MenuBarMetricWidthEngine.horizontalTextPrefixFont))
                .opacity(0.68)
        }
    }

    /// 紧凑模式:轻量弱化标签在上、清晰数值 + 弱化单位在下的双层排布。
    /// 列宽固定在 `MenuBarMetricWidthEngine.compactCellWidth`，与单位拆分同源。
    private func compactCell(for item: MenuBarMetricItem) -> some View {
        VStack(alignment: .center, spacing: -0.5) {
            Text(Self.textPrefix(for: item.kind))
                .font(Font(MenuBarMetricWidthEngine.compactLabelFont))
                .opacity(0.64)
            compactValueText(for: item)
        }
        .frame(width: MenuBarMetricWidthEngine.compactCellWidth(for: item.kind))
    }

    @ViewBuilder
    private func compactValueText(for item: MenuBarMetricItem) -> some View {
        splitValueView(
            numericValue(for: item),
            digitFont: Font(MenuBarMetricWidthEngine.compactValueFont),
            unitFont: Font(MenuBarMetricWidthEngine.compactUnitFont),
            unitOpacity: 0.72
        )
    }

    @ViewBuilder
    private func splitValueView(
        _ rawValue: String,
        digitFont: Font?,
        unitFont: Font,
        unitOpacity: Double
    ) -> some View {
        let parts = MenuBarMetricWidthEngine.splitValueUnit(rawValue)
        if parts.unit.isEmpty {
            Text(parts.digits)
                .font(digitFont)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.digits)
                    .font(digitFont)
                Text(parts.unit)
                    .font(unitFont)
                    .opacity(unitOpacity)
            }
        }
    }

    /// 纯数值:trim/剥箭头逻辑同源在布局引擎,横排与紧凑共用。
    private func numericValue(for item: MenuBarMetricItem) -> String {
        MenuBarMetricWidthEngine.displayValue(for: item)
    }

    /// 文字前缀(横排文字模式/紧凑模式共用),同源在布局引擎。
    private static func textPrefix(for kind: MenuBarMetricKind) -> String {
        MenuBarMetricWidthEngine.textPrefix(for: kind)
    }

    /// icon 字号,同源在布局引擎(icon 测量与渲染必须一致)。
    private static var iconFontSize: CGFloat { MenuBarMetricWidthEngine.iconFontSize }

    /// 前缀与数值之间的间距,同源在布局引擎。
    private var symbolSpacing: CGFloat { MenuBarMetricWidthEngine.symbolSpacing }
}
