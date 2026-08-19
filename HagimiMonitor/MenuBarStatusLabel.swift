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
                items: store.menuBarMetricItems
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

    /// 每个指标占一个独立的固定宽度单元:文字标签(小)在上、数值(大)在下的双层排布,
    /// 专为窄屏机型省空间设计。
    /// 标签与数值都居中对齐,且始终按 `compactCellWidth` 定宽(含末位指标),
    /// 避免数值位数变化(如 8% → 18%)时上下两行、乃至整个图标宽度跟着跳动。
    @ViewBuilder
    private func cell(for item: MenuBarMetricItem) -> some View {
        VStack(alignment: .center, spacing: -1) {
            Text(Self.textPrefix(for: item.kind))
                .font(compactLabelFont)
            Text(numericValue(for: item))
                .font(compactValueFont)
        }
        .frame(width: compactCellWidth(for: item.kind))
    }

    /// 文字前缀:带 `menuBarPrefix` 的直接用,网络无前缀则用方向箭头。
    /// 输入与实例状态无关,故为 static(静态列宽缓存初始化时也需调用)。
    private static func textPrefix(for kind: MenuBarMetricKind) -> String {
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

    /// 各指标为定宽框预留的「最宽可能值」——紧凑列宽以此为测量样本。
    /// 输入与实例状态无关,故为 static。
    private static func reservedNumericValue(for kind: MenuBarMetricKind) -> String {
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
        case .fanSpeed:
            "9999"
        }
    }

    /// 双层列宽:取「标签」与「数值最大可能宽度」两者中较宽的一个,
    /// 保证上下两行都不会因为对方更宽而在切换时左右跳动。
    /// +2 兜底:测量与渲染的亚像素取整差异会让实测宽度卡在边界,
    /// 差零点几 pt 时数值被截断成「9…」,预留余量兜底。
    private func compactCellWidth(for kind: MenuBarMetricKind) -> CGFloat {
        Self.compactCellWidths[kind]!
    }

    private var labelFont: Font {
        .system(size: Self.fontSize, weight: .medium, design: .rounded).monospacedDigit()
    }

    private var compactLabelFont: Font {
        .system(size: Self.compactLabelFontSize, weight: .semibold, design: .rounded)
    }

    private var compactValueFont: Font {
        .system(size: Self.compactValueFontSize, weight: .bold, design: .rounded).monospacedDigit()
    }

    // MARK: - 静态缓存(消除每渲染周期重建 NSFont + 重复测量固定字符串的热点)

    /// 测量用 NSFont 按固定字号/字重/是否等宽数字各复用一个实例。字号在进程内恒定,
    /// 故用 static let 一次性构造,避免每次 body 都走 `roundedMeasuringFont` 新建字体。
    private static let compactLabelMeasuringFont: NSFont =
        roundedMeasuringFont(size: compactLabelFontSize, weight: .semibold, monospacedDigit: false)
    private static let compactValueMeasuringFont: NSFont =
        roundedMeasuringFont(size: compactValueFontSize, weight: .bold, monospacedDigit: true)

    /// 各指标的列宽:取「标签宽度」与「数值最大宽度」中较宽者,一次性测得并复用。
    private static let compactCellWidths: [MenuBarMetricKind: CGFloat] = {
        var cache: [MenuBarMetricKind: CGFloat] = [:]
        for kind in MenuBarMetricKind.allCases {
            let labelWidth = (textPrefix(for: kind) as NSString)
                .size(withAttributes: [.font: compactLabelMeasuringFont]).width
            let valueWidth = (reservedNumericValue(for: kind) as NSString)
                .size(withAttributes: [.font: compactValueMeasuringFont]).width
            cache[kind] = ceil(max(labelWidth, valueWidth)) + 2
        }
        return cache
    }()

    /// 与显示字体同为 rounded 设计的测量字体:rounded 的数字字形略宽,若用非 rounded
    /// 字体测量会系统性偏小,定宽框在取整边界上放不下实际渲染结果,数值偶发被截断
    /// 成「9…」(温度尤其明显)。
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

    private static var fontSize: CGFloat { 11 }

    /// 上层标签字号:比数值小一档,弱化标签、突出数值。
    private static var compactLabelFontSize: CGFloat { 7 }

    /// 下层数值字号:菜单栏 22pt 高度预算内,双层叠加后仍留有余量。
    private static var compactValueFontSize: CGFloat { 10 }

    /// 指标之间的间距。
    private var interCellSpacing: CGFloat { 2 }
}
