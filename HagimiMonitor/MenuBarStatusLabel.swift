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
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                cell(for: item, isTrailing: index == items.count - 1)
            }
        }
        .font(labelFont)
        .lineLimit(1)
        .allowsTightening(false)
        .fixedSize()
    }

    /// 每个指标占一个独立的固定宽度单元:前缀(SF 图标 / CPU / ↑↓ 等)固定在左侧,
    /// 数值放进按「最大可能值」测得的定宽框、**左对齐**贴住前缀。短值时预留的
    /// 空白落在尾部,与指标间距合并成更大的「组间空隙」,视觉上数字始终跟自己的
    /// 前缀成一组。每格宽度仍固定,相邻指标位置不会左右抖动。
    /// 末位指标是整个菜单栏图标的右边缘,身后没有下一个指标可供分组,固定宽度
    /// 预留的尾部空白会直接变成图标右侧的空洞留白,故末位不做定宽预留,按实际
    /// 内容收紧,消除该处的空间浪费。
    @ViewBuilder
    private func cell(for item: MenuBarMetricItem, isTrailing: Bool) -> some View {
        switch layoutStyle {
        case .icon, .text:
            HStack(spacing: symbolSpacing) {
                leading(for: item.kind)
                if isTrailing {
                    Text(numericValue(for: item))
                } else {
                    Text(numericValue(for: item))
                        .frame(width: valueWidth(for: item.kind), alignment: .leading)
                }
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
            Image(systemName: kind.symbol)
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

    private var fontSize: CGFloat { 12 }

    /// 紧凑模式上层标签字号:比数值小一档,弱化标签、突出数值。
    private var compactLabelFontSize: CGFloat { 7 }

    /// 紧凑模式下层数值字号:菜单栏 22pt 高度预算内,双层叠加后仍留有余量。
    private var compactValueFontSize: CGFloat { 10 }

    /// 指标之间的间距。
    private var interCellSpacing: CGFloat { 6 }

    /// 前缀与数值之间的间距(图标比文字略需留白)。
    private var symbolSpacing: CGFloat {
        layoutStyle == .icon ? 3 : 2
    }
}
