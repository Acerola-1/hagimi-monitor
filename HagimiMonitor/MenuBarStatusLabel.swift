import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var store: MonitorStore
    let darkMode: Bool

    var body: some View {
        switch store.settings.menuBarDisplayMode {
        case .ring:
            Image(nsImage: MenuBarComputeRingIcon.image(
                load: store.loadAnimator.displayedComputeLoad,
                darkMode: darkMode,
                loadLevel: store.haloRingLoadLevel
            ))
            .resizable()
            .frame(width: 18, height: 18)
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

struct MenuBarMetricLabel: View {
    enum Style {
        case menuBar
        case preview
    }

    let items: [MenuBarMetricItem]
    var style: Style = .menuBar
    var layoutStyle: MenuBarMetricLayoutStyle = .icon

    var body: some View {
        HStack(spacing: interCellSpacing) {
            ForEach(items) { item in
                cell(for: item)
            }
        }
        .font(labelFont)
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
    }

    /// 每个指标占一个独立的固定宽度单元:前缀(SF 图标 / CPU / ↑↓ 等)固定在左侧,
    /// 数值放进按「最大可能值」测得的定宽框(等宽数字字体)、**统一左对齐**贴住前缀。
    /// 每格宽度恒定,数值在最大/最小值间切换、乃至位数变化(9%→100%、0B→1.5M)时
    /// 都不改变格宽,故整个菜单栏图标宽度稳定、不左右抖动。
    ///
    /// 所有指标(含末位)一律左对齐,是为了让每个指标的「前缀→数值」间距完全一致:
    /// 若单独把末位改成右对齐,末位短值时预留空白会落在图标与数值之间,该处间距
    /// 明显大于其它指标、视觉突兀。代价是末位短值时预留空白落在整个图标最右侧,
    /// 形成一小段恒定留白(不抖动)——这是「间距一致 + 宽度稳定」下不可避免的取舍。
    @ViewBuilder
    private func cell(for item: MenuBarMetricItem) -> some View {
        switch layoutStyle {
        case .icon, .text:
            HStack(spacing: symbolSpacing) {
                leading(for: item.kind)
                Text(numericValue(for: item))
                    .frame(width: valueWidth(for: item.kind), alignment: .leading)
            }
        case .compact:
            compactCell(for: item)
        }
    }

    /// 紧凑模式:文字标签(小)在上、数值(大)在下的双层排布,专为窄屏机型省空间设计。
    /// 标签与数值都居中对齐,且始终按 `compactCellWidth` 定宽(含末位指标),
    /// 避免数值位数变化(如 8% → 18%)时上下两行、乃至整个图标宽度跟着跳动。
    private func compactCell(for item: MenuBarMetricItem) -> some View {
        VStack(alignment: .center, spacing: -1) {
            Text(textPrefix(for: item.kind))
                .font(compactLabelFont)
            Text(numericValue(for: item))
                .font(compactValueFont)
        }
        .frame(width: compactCellWidth(for: item.kind))
    }

    /// 前缀视图:图标模式用 SF Symbol,文字模式用 CPU/GPU… 或网络的 ↑↓。
    /// 仅由 `cell(for:isTrailing:)` 的 `.icon, .text` 分支调用,紧凑模式走独立的
    /// `compactCell`、不经过这里——故此处不需要处理 `.compact`。
    @ViewBuilder
    private func leading(for kind: MenuBarMetricKind) -> some View {
        switch layoutStyle {
        case .icon:
            // icon 字号比文本小 1pt,让数字视觉上比 icon 略大一圈(贴近 iStat Menus
            // "数字突出、icon 作标识" 的视觉权重);父级 .font 不继承到此。
            Image(systemName: kind.symbol)
                .font(.system(size: iconFontSize, weight: .medium))
        default:
            Text(textPrefix(for: kind))
        }
    }

    /// 文字前缀:带 `menuBarPrefix` 的直接用,网络无前缀则用方向箭头。
    private func textPrefix(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .networkDownload:
            "↓"
        case .networkUpload:
            "↑"
        default:
            kind.menuBarPrefix
        }
    }

    /// 纯数值:trim 掉格式化补的空白,并剥掉网络值里内嵌的 ↑/↓ 箭头
    /// (箭头由前缀部分统一呈现),宽度交给定宽框控制。
    private func numericValue(for item: MenuBarMetricItem) -> String {
        var value = Substring(item.value)
        if let first = value.first, first == "↑" || first == "↓" {
            value = value.dropFirst()
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// 数值框固定宽度:按该指标可能达到的最宽字符串测量(等宽数字字体),
    /// 保证数值在最大/最小值间切换时右对齐、右边缘不动。
    private func valueWidth(for kind: MenuBarMetricKind) -> CGFloat {
        let sample = reservedNumericValue(for: kind)
        let width = (sample as NSString).size(withAttributes: [.font: measuringFont]).width
        return ceil(width) + 2
    }

    private func reservedNumericValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage, .gpuUsage, .memoryUsage, .memoryPressure, .batteryLevel:
            "100%"
        case .networkDownload, .networkUpload:
            "888M"
        case .cpuTemperature:
            "888°"
        case .storageFree:
            "888G"
        case .systemPower:
            "888W"
        }
    }

    /// 紧凑模式的双层列宽:取「标签」与「数值最大可能宽度」两者中较宽的一个,
    /// 保证上下两行都不会因为对方更宽而在切换时左右跳动。
    /// +2 与 valueWidth 同源:测量与渲染的亚像素取整差异会让实测宽度卡在边界,
    /// 差零点几 pt 时数值被截断成「9…」,预留余量兜底。
    private func compactCellWidth(for kind: MenuBarMetricKind) -> CGFloat {
        let labelWidth = (textPrefix(for: kind) as NSString)
            .size(withAttributes: [.font: compactLabelMeasuringFont]).width
        let valueWidth = (reservedNumericValue(for: kind) as NSString)
            .size(withAttributes: [.font: compactValueMeasuringFont]).width
        return ceil(max(labelWidth, valueWidth)) + 2
    }

    private var labelFont: Font {
        .system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    private var measuringFont: NSFont {
        Self.roundedMeasuringFont(size: fontSize, weight: .medium, monospacedDigit: true)
    }

    private var compactLabelFont: Font {
        .system(size: compactLabelFontSize, weight: .semibold, design: .rounded)
    }

    private var compactValueFont: Font {
        .system(size: compactValueFontSize, weight: .bold, design: .rounded).monospacedDigit()
    }

    private var compactLabelMeasuringFont: NSFont {
        Self.roundedMeasuringFont(size: compactLabelFontSize, weight: .semibold, monospacedDigit: false)
    }

    private var compactValueMeasuringFont: NSFont {
        Self.roundedMeasuringFont(size: compactValueFontSize, weight: .bold, monospacedDigit: true)
    }

    /// 与显示字体同为 rounded 设计的测量字体。此前用默认 SF 测、SF Rounded 显:
    /// rounded 的数字字形略宽,测量系统性偏小,定宽框在取整边界上放不下实际
    /// 渲染结果,数值偶发被截断成「9…」(紧凑模式温度尤其明显)。
    private static func roundedMeasuringFont(size: CGFloat, weight: NSFont.Weight, monospacedDigit: Bool) -> NSFont {
        let base = monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }

    private var fontSize: CGFloat { 11 }

    /// icon 字号:固定 9pt,始终比数字(fontSize=11pt)小 2pt,让数字视觉上更突出。
    /// 不能用 fontSize - 1 跟随,因为文本调字号时不应带动 icon。
    private var iconFontSize: CGFloat { 9 }

    /// 紧凑模式上层标签字号:比数值小一档,弱化标签、突出数值。
    private var compactLabelFontSize: CGFloat { 7 }

    /// 紧凑模式下层数值字号:菜单栏 22pt 高度预算内,双层叠加后仍留有余量。
    private var compactValueFontSize: CGFloat { 10 }

    /// 指标之间的间距。
    private var interCellSpacing: CGFloat { 2 }

    /// 前缀与数值之间的间距(图标比文字略需留白)。
    private var symbolSpacing: CGFloat {
        layoutStyle == .icon ? 2 : 2
    }
}
