import AppKit

/// 横排(icon/text)布局的「总宽预订」布局引擎。
///
/// 核心思路:菜单栏图标的左右边缘绝对不动,宽度问题全部在内部消化:
/// 1. **总宽一次性算死**:每个指标按「最宽可能值」预留一格,总宽 = Σ(前缀 + 最宽值) + 格间间距,
///    只随勾选的指标集合与布局样式变化,与任何实时数值无关;
/// 2. **内部自动铺开**:前缀 + 数值按内容自适应排布,预留的富余量均摊为等宽的格间间距--
///    数值位数变化(8% -> 18%、0B -> 1.5M)只让内部间距轻微呼吸,左右边缘与邻居图标的
///    距离恒定,不产生任何对外推挤。
///
/// 宽度全部由本引擎静态测量(NSString/NSImage 实测 + 缓存),不依赖 GeometryReader,
/// 与 ImageRenderer 快照管线兼容:快照宽度恒等于 totalWidth,状态项 length 恒定。
enum MenuBarMetricWidthEngine {

    // MARK: - 常量(与 `MenuBarMetricLabel` 渲染口径同源)

    /// 横排数值字号:与 `MenuBarMetricLabel.labelFont` 一致,测量与渲染必须同源。
    static let horizontalValueFontSize: CGFloat = 11

    /// icon 字号:比数值小 2pt,让数字视觉上比 icon 略大一圈(贴近 iStat Menus
    /// 「数字突出、icon 作标识」的视觉权重)。icon 与文本前缀共用此测量口径。
    static let iconFontSize: CGFloat = 9

    /// 前缀与数值之间的间距。
    static let symbolSpacing: CGFloat = 1

    /// 格间最小间距:全部指标同时打满最宽值时总宽不再有富余,间距收缩到此下限。
    /// 横排常态下实际间距 = 该下限 + 均摊富余,观感是刻意留白的分隔,不是挤压。
    static let minInterPairGap: CGFloat = 2

    /// 横排文本测量字体:与渲染用的 labelFont 同字号/字重/rounded/等宽数字。
    private static let measuringFont: NSFont =
        roundedMeasuringFont(size: horizontalValueFontSize, weight: .medium, monospacedDigit: true)

    // MARK: - 横排布局

    /// 横排布局结果:总宽(恒定,只随指标集合/布局样式变化)+ 格间间距(随实时数值微调)。
    struct HorizontalLayout {
        let totalWidth: CGFloat
        let gap: CGFloat
    }

    /// 横排总布局:总宽 = Σ 最大预留格宽 + (格数-1)·最小间距,与实时数值无关;
    /// 间距 = (总宽 - 实际内容宽)/(格数-1),富余均摊、向下钳到最小间距,
    /// 保证内容宽度恒等于总宽(两端都贴边)。单指标无间距概念,富余留在右缘内。
    static func horizontalLayout(for items: [MenuBarMetricItem], layout: MenuBarMetricLayoutStyle) -> HorizontalLayout {
        let gapCount = max(items.count - 1, 0)
        let total = items.reduce(CGFloat(0)) { $0 + maxPairWidth(for: $1.kind, layout: layout) }
            + CGFloat(gapCount) * minInterPairGap
        guard gapCount > 0 else {
            return HorizontalLayout(totalWidth: total, gap: minInterPairGap)
        }
        let natural = items.reduce(CGFloat(0)) { $0 + naturalPairWidth(for: $1, layout: layout) }
        let slack = max(total - natural, 0)
        return HorizontalLayout(totalWidth: total, gap: max(slack / CGFloat(gapCount), minInterPairGap))
    }

    /// 单指标最大预留格宽:前缀 + 最宽可能值。
    static func maxPairWidth(for kind: MenuBarMetricKind, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        prefixWidth(for: kind, layout: layout) + symbolSpacing + maxValueWidth(for: kind)
    }

    /// 单指标实际内容宽:前缀 + 当前值(未取整的实测宽)。
    static func naturalPairWidth(for item: MenuBarMetricItem, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        prefixWidth(for: item.kind, layout: layout) + symbolSpacing + measuredTextWidth(of: displayValue(for: item))
    }

    /// 各指标横排预留的「最宽可能值」:等宽数字下同位数任意值与样本等宽。
    /// 格内实际值与预留值的差 = 该格富余,由布局均摊为间距,不再常驻挂在边缘。
    private static let reservedValues: [MenuBarMetricKind: String] = [
        .cpuUsage: "100%",
        .gpuUsage: "100%",
        .memoryUsage: "100%",
        .memoryPressure: "100%",
        .batteryLevel: "100%",
        .networkDownload: "888M",
        .networkUpload: "888M",
        .cpuTemperature: "888°",
        .storageFree: "888G",
        .systemPower: "888W",
        .fanSpeed: "9999",
    ]

    /// 预留值实测宽度。ceil 对齐渲染取整;+0.5 使全打满时格间距仍略高于下限。
    private static let reservedValueWidths: [MenuBarMetricKind: CGFloat] =
        reservedValues.mapValues { ceil(measuredTextWidth(of: $0)) + 0.5 }

    private static func maxValueWidth(for kind: MenuBarMetricKind) -> CGFloat {
        reservedValueWidths[kind] ?? ceil(measuredTextWidth(of: reservedFallback)) + 0.5
    }

    /// 兜底预留值:新增指标忘记配 reservedValues 时使用,宽度偏宽、无截断风险。
    private static let reservedFallback = "88888"

    // MARK: - 前缀与数值

    /// 前缀文字:带 `menuBarPrefix` 的直接用,网络无前缀则用方向箭头。
    /// 横排(文字模式)与紧凑模式的标签同源;输入与实例状态无关,故为 static。
    static func textPrefix(for kind: MenuBarMetricKind) -> String {
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
    /// (箭头由前缀部分统一呈现),宽度交给布局引擎控制。
    static func displayValue(for item: MenuBarMetricItem) -> String {
        var value = Substring(item.value)
        if let first = value.first, first == "↑" || first == "↓" {
            value = value.dropFirst()
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// 前缀宽度:文字模式实测文本;icon 模式用同配置 NSImage 的固有宽度。
    /// ceil 对齐渲染取整;icon 额外 +1 兜底 NSImage 与 SwiftUI 渲染的亚像素差异。
    private static func prefixWidth(for kind: MenuBarMetricKind, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        switch layout {
        case .icon:
            iconWidths[kind] ?? fallbackIconWidth
        case .text, .compact:
            ceil(measuredTextWidth(of: textPrefix(for: kind)))
        }
    }

    /// 各 SF Symbol 前缀在 9pt medium 配置下的固有宽度,一次性测得并复用。
    private static let iconWidths: [MenuBarMetricKind: CGFloat] = {
        var cache: [MenuBarMetricKind: CGFloat] = [:]
        // Swift 侧仅 pointSize:weight: 配置可用(font:/textAttributes: 初始化器不可直调);
        // 系统字体 9pt medium 与 leading(for:) 的 SwiftUI 渲染口径一致,亚像素差由 +1 兜底。
        let configuration = NSImage.SymbolConfiguration(pointSize: iconFontSize, weight: .medium)
        for kind in MenuBarMetricKind.allCases {
            guard let base = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil),
                  let configured = base.withSymbolConfiguration(configuration) else {
                continue
            }
            cache[kind] = ceil(configured.size.width) + 1
        }
        return cache
    }()

    /// Symbol 测量失败时的兜底宽度(略宽于 9pt 常规 symbol,无截断风险)。
    private static let fallbackIconWidth: CGFloat = 13

    // MARK: - 测量基础设施

    /// 文本实测宽度缓存:各指标的可能显示值集合有限,NSCache 命中后
    /// 每秒 tick 只是字典查询,不再重复走 NSString 测量。
    private static let measuredWidthCache = NSCache<NSString, NSNumber>()

    static func measuredTextWidth(of string: String) -> CGFloat {
        if let cached = measuredWidthCache.object(forKey: string as NSString) {
            return cached.doubleValue
        }
        let width = (string as NSString).size(withAttributes: [.font: measuringFont]).width
        measuredWidthCache.setObject(NSNumber(value: width), forKey: string as NSString)
        return width
    }

    /// 与显示字体同为 rounded 设计的测量字体:rounded 的数字字形略宽,若用非 rounded
    /// 字体测量会系统性偏小,定宽框在取整边界上放不下实际渲染结果,数值偶发被截断
    /// 成「9…」(温度尤其明显)。横排与紧凑模式的测量共用此实现。
    static func roundedMeasuringFont(size: CGFloat, weight: NSFont.Weight, monospacedDigit: Bool) -> NSFont {
        let base = monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }
}
