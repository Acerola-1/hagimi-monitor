import AppKit

/// 横排(icon/text)布局的「总宽预订」布局引擎。
///
/// 核心思路:菜单栏图标的左右边缘绝对不动,宽度问题全部在内部消化:
/// 1. **总宽一次性算死**:每个指标按「最宽可能值」预留一格,总宽 = Σ(前缀 + 最宽值) + 格间间距,
///    只随勾选的指标集合与布局样式变化,与任何实时数值无关;
/// 2. **常用值锚点 + 均摊间距**:每格区域按「常用宽度」划定,格间间距由剩余富余均摊。
///    数值在常用范围内的位数变化(8% -> 18%)被自己区域内的尾部空白完全吸收,
///    所有位置纹丝不动;只有冲出常用宽度(CPU 冲上 100%)才轻微收缩格间距,
///    左右边缘与总宽在任何情况下都恒定。
///
/// 字体与菜单栏其余文字同族(SF Rounded,与系统观感一致),等宽数字保证同位数串宽度
/// 恒定;尾部单位字形(%、W、M…)拆出用小一号字号渲染,既省宽又形成「数字为主、
/// 单位为辅」的层次。
///
/// 宽度全部由本引擎静态测量(NSString/NSImage 实测 + 缓存),不依赖 GeometryReader,
/// 与 ImageRenderer 快照管线兼容:快照宽度恒等于 totalWidth,状态项 length 恒定。
enum MenuBarMetricWidthEngine {

    // MARK: - 常量(与 `MenuBarMetricLabel` 渲染口径同源)

    /// 横排数值字号:与 `MenuBarMetricLabel` 横排字体一致,测量与渲染必须同源。
    static let horizontalValueFontSize: CGFloat = 11

    /// 尾部单位字形字号:比数字小一档,弱化单位、突出数字(iStat 式层次)。
    static let unitFontSize: CGFloat = 9

    /// icon 字号:比数值小 2pt,让数字视觉上比 icon 略大一圈(贴近 iStat Menus
    /// 「数字突出、icon 作标识」的视觉权重)。icon 与文本前缀共用此测量口径。
    static let iconFontSize: CGFloat = 9

    /// 前缀与数值之间的间距。
    static let symbolSpacing: CGFloat = 1

    /// 格间最小间距:全部指标同时打满最宽值时总宽不再有富余,间距收缩到此下限。
    /// 横排常态下实际间距 = 该下限 + 均摊富余,观感是刻意留白的分隔,不是挤压。
    static let minInterPairGap: CGFloat = 2

    /// 横排字体(rounded + medium + 等宽数字):渲染由视图经 `Font(nsFont)` 桥接,
    /// 与本引擎的测量共用同一 NSFont 实例,测量/渲染天然同源。
    static let horizontalValueFont: NSFont =
        roundedMeasuringFont(size: horizontalValueFontSize, weight: .medium, monospacedDigit: true)

    /// 尾部单位字形字体:与数值同族同字重、小一号。
    static let unitFont: NSFont =
        roundedMeasuringFont(size: unitFontSize, weight: .medium, monospacedDigit: true)

    // MARK: - 横排布局

    /// 横排布局结果:总宽(恒定,只随指标集合/布局样式变化)+ 格间间距(仅当某指标
    /// 冲出常用宽度时轻微收缩,稳态下恒定)。
    struct HorizontalLayout {
        let totalWidth: CGFloat
        let gap: CGFloat
    }

    /// 横排总布局:总宽 = Σ 最大预留格宽 + (格数-1)·最小间距,与实时数值无关。
    /// 每格的实际占位 = max(当前内容宽, 常用宽度),格间间距 = (总宽 - Σ占位)/(格数-1):
    /// 数值在常用范围内时占位恒等于常用宽度,间距与所有位置纹丝不动;
    /// 冲出常用宽度(如 CPU 100%)时该格占位变大、间距轻微收缩,内容总宽仍恒等于
    /// 总宽(两端贴边),边缘永不推移。单指标无间距概念,富余留在右缘内。
    static func horizontalLayout(for items: [MenuBarMetricItem], layout: MenuBarMetricLayoutStyle) -> HorizontalLayout {
        let gapCount = max(items.count - 1, 0)
        let total = items.reduce(CGFloat(0)) { $0 + maxPairWidth(for: $1.kind, layout: layout) }
            + CGFloat(gapCount) * minInterPairGap
        guard gapCount > 0 else {
            return HorizontalLayout(totalWidth: total, gap: minInterPairGap)
        }
        let placed = items.reduce(CGFloat(0)) {
            $0 + max(naturalPairWidth(for: $1, layout: layout), commonPairWidth(for: $1.kind, layout: layout))
        }
        return HorizontalLayout(totalWidth: total, gap: max((total - placed) / CGFloat(gapCount), minInterPairGap))
    }

    /// 单指标最大预留格宽:前缀 + 最宽可能值。
    static func maxPairWidth(for kind: MenuBarMetricKind, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        prefixWidth(for: kind, layout: layout) + symbolSpacing + maxValueWidth(for: kind)
    }

    /// 单指标常用格宽:前缀 + 常用值。区域按此划定,数值在常用范围内的变化不影响布局。
    static func commonPairWidth(for kind: MenuBarMetricKind, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        prefixWidth(for: kind, layout: layout) + symbolSpacing + (commonValueWidths[kind] ?? maxValueWidth(for: kind))
    }

    /// 单指标实际内容宽:前缀 + 当前值(未取整的实测宽)。
    static func naturalPairWidth(for item: MenuBarMetricItem, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        prefixWidth(for: item.kind, layout: layout) + symbolSpacing + measuredValueWidth(of: displayValue(for: item))
    }

    /// 各指标的「常用值」锚点,按统计特性分两类:
    /// - 平稳指标(CPU/温度/功耗/百分比类):典型稳态为两位数,锚定 `99` 档--
    ///   9↔10 的边界横跳被区域吸收,只有 3 位极值(100%/100°/100W+)才轻微收缩间距;
    /// - 跳变指标(网速/存储/风扇):显示宽度天生横跨多个量级,锚小了反而频繁越界
    ///   造成间距抖动,直接锚定最大值,区域恒定。
    private static let commonValues: [MenuBarMetricKind: String] = [
        .cpuUsage: "99%",
        .gpuUsage: "99%",
        .memoryUsage: "99%",
        .memoryPressure: "99%",
        .batteryLevel: "99%",
        .cpuTemperature: "99°",
        .systemPower: "99W",
        .networkDownload: "888M",
        .networkUpload: "888M",
        .storageFree: "888G",
        .fanSpeed: "9999",
    ]

    /// 常用值实测宽度,口径同 reservedValueWidths。
    private static let commonValueWidths: [MenuBarMetricKind: CGFloat] =
        commonValues.mapValues { ceil(measuredValueWidth(of: $0)) + 0.5 }

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
    /// 旧「定宽框 + 截断」方案需要的 +2 大兜底已无意义:数值是内容自适应排布,
    /// 布局上不存在截断,预留只参与总宽与间距的算术。
    private static let reservedValueWidths: [MenuBarMetricKind: CGFloat] =
        reservedValues.mapValues { ceil(measuredValueWidth(of: $0)) + 0.5 }

    private static func maxValueWidth(for kind: MenuBarMetricKind) -> CGFloat {
        reservedValueWidths[kind] ?? ceil(measuredValueWidth(of: reservedFallback)) + 0.5
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

    /// 会以小一号字号渲染的尾部单位字形集合。其余(纯数字、小数点)走主字号。
    private static let unitSuffixes: Set<Character> = ["%", "W", "K", "M", "G", "T", "B", "°"]

    /// 数值拆分:尾部单位字形独立出来,渲染用小一号字号弱化,测量分别按各自字号计宽。
    static func splitValueUnit(_ value: String) -> (digits: String, unit: String) {
        if let last = value.last, unitSuffixes.contains(last) {
            return (String(value.dropLast()), String(last))
        }
        return (value, "")
    }

    /// 前缀宽度:文字模式实测文本;icon 模式用同配置 NSImage 的固有宽度。
    /// ceil 对齐渲染取整;icon 额外 +1 兜底 NSImage 与 SwiftUI 渲染的亚像素差异。
    private static func prefixWidth(for kind: MenuBarMetricKind, layout: MenuBarMetricLayoutStyle) -> CGFloat {
        switch layout {
        case .icon:
            iconWidths[kind] ?? fallbackIconWidth
        case .text, .compact:
            ceil(measuredTextWidth(of: textPrefix(for: kind), font: horizontalValueFont))
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

    /// 数值实测宽:数字部分按主字号、尾部单位按小一号字号分别测量后求和,
    /// 与 `MenuBarMetricLabel` 的拆分渲染一一对应。
    static func measuredValueWidth(of value: String) -> CGFloat {
        let parts = splitValueUnit(value)
        let unitWidth = parts.unit.isEmpty
            ? 0
            : measuredTextWidth(of: parts.unit, font: unitFont)
        return measuredTextWidth(of: parts.digits, font: horizontalValueFont) + unitWidth
    }

    /// 文本实测宽度缓存:键含字体名与字号(横排/单位/紧凑各自缓存),
    /// NSCache 命中后每秒 tick 只是字典查询,不再重复走 NSString 测量。
    private static let measuredWidthCache = NSCache<NSString, NSNumber>()

    static func measuredTextWidth(of string: String, font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(string)" as NSString
        if let cached = measuredWidthCache.object(forKey: key) {
            return cached.doubleValue
        }
        let width = (string as NSString).size(withAttributes: [.font: font]).width
        measuredWidthCache.setObject(NSNumber(value: width), forKey: key)
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
