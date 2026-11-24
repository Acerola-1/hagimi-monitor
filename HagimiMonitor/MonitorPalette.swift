import SwiftUI

struct MonitorPalette {
    /// 模块实色上的控件前景，明暗外观共用以稳定对比。
    static let selectedControlForeground = Color(hex: 0x171D2A)

    let preference: MonitorColorSchemePreference
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.96) : Color(hex: 0x171D2A)
    }

    /// 浅色数字、次要文字和标签逐级压深，避免在亮玻璃上发飘。标题仍是 #171D2A。
    var valueText: Color {
        isDark ? Color.white.opacity(0.90) : Color(hex: 0x222938)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.82) : Color(hex: 0x343C4A)
    }

    var captionText: Color {
        isDark ? Color.white.opacity(0.78) : Color(hex: 0x4A5362)
    }

    /// 指标格、进度槽和展开区内衬共用。
    /// 调试构建可用 `-HagimiTrackFill` 覆盖当前外观下的浓度。
    var trackFill: Color {
        if let override = TemporaryInstanceOverrides.trackFillOpacity {
            return isDark ? Color.white.opacity(override) : Color(hex: 0x3C485A).opacity(override)
        }
        return isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.042)
    }

    /// 主行成对读数的浅底。
    var rowGrooveFill: Color {
        isDark ? trackFill : Color.black.opacity(0.058)
    }

    /// 卡片 0.5pt 细描边：浅色提供清晰物理边界，深色保持无边框。
    var cardBorderColor: Color {
        isDark ? .clear : Color.black.opacity(0.07)
    }

    /// 毛玻璃按钮描边。明暗和两种配色共用 10% 白。
    var materialButtonStroke: Color {
        Color.white.opacity(0.10)
    }

    func liveDot(for loadLevel: MenuBarComputeLoadLevel) -> Color {
        Color(nsColor: loadLevel.coreColor(darkMode: isDark))
    }

    var displayTint: Color {
        switch preference {
        case .balanced:
            return Color(hex: isDark ? 0x7D92B5 : 0x526787)
        case .vibrant:
            // 中性蓝灰作为附属信息行色相，浅色下压深以保证对比度。
            return Color(hex: isDark ? 0x64748B : 0x52637A)
        }
    }

    func moduleTint(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            balancedModuleTint(for: kind)
        case .vibrant:
            vibrantModuleTint(for: kind)
        }
    }

    /// 严重档红:SwiftUI 侧经 `severityTint` 取色,AppKit 绘制路径(菜单栏红点)
    /// 数值同源,避免两套绘制各写一个红。
    static let criticalTintHex: UInt32 = 0xD94848

    func severityTint(for severity: MonitorSeverity) -> Color {
        if isDark {
            switch preference {
            case .balanced:
                // 平衡深色使用高辨识度状态强调色，区分三档严重度。
                switch severity {
                case .calm: return Color(hex: 0x36B370)
                case .warning: return Color(hex: 0xD4982A)
                case .critical: return Color(hex: 0xE85454)
                }
            case .vibrant:
                // 活力深色使用克制饱和度状态色，与高饱和模块底色保持平衡。
                switch severity {
                case .calm: return Color(hex: 0x2F9E64)
                case .warning: return Color(hex: 0xB8872E)
                case .critical: return Color(hex: Self.criticalTintHex)
                }
            }
        }
        switch severity {
        case .calm: return Color(hex: 0x1D854D)
        case .warning: return Color(hex: 0x9B6915)
        case .critical: return Color(hex: 0xC93838)
        }
    }

    /// 快捷功能统一强调色 Hex:全部工具共用一紫,激活状态一眼可辨,
    /// 供 SwiftUI 与 AppKit (如 MenuBarHUDBadge) 统一定义单源真理。
    static let quickToolTintHex: UInt32 = 0xA855F7

    /// 快捷功能统一强调色:全部工具共用一紫,激活状态一眼可辨,
    /// 不随主题切换漂移。
    var quickToolTint: Color {
        Color(hex: Self.quickToolTintHex)
    }

    /// 快捷功能磁贴点亮态底色:强调色低透明铺底,深色模式下稍亮
    /// 以维持可辨识度。
    var quickToolActiveFill: Color {
        quickToolTint.opacity(isDark ? 0.16 : 0.10)
    }

    /// 活力模式里性能核用琥珀：比模块橙更黄，和青绿能效核拉开冷暖。
    /// 深色用亮金。浅色保持同一色相的明亮金；黄压得过深会变成棕橄榄。
    /// 平衡模式保持橙 / 蓝 / 绿的分工。
    var performanceCoreTint: Color {
        switch preference {
        case .balanced:
            Color(hex: isDark ? 0xFF8F45 : 0xD25E28)
        case .vibrant:
            Color(hex: isDark ? 0xFFC44D : 0xE09600)
        }
    }

    /// 三组核心同时出现时，平衡配色的性能核改用冷蓝，避免和超核的橙色叠在一起。
    var secondaryPerformanceCoreTint: Color {
        switch preference {
        case .balanced:
            Color(hex: isDark ? 0x5C96FF : 0x2E64D4)
        case .vibrant:
            performanceCoreTint
        }
    }

    var superCoreTint: Color {
        switch preference {
        case .balanced:
            Color(hex: isDark ? 0xFF8F45 : 0xD25E28)
        case .vibrant:
            Color(hex: isDark ? 0xB07CFF : 0x6E3CC8)
        }
    }

    var efficiencyCoreTint: Color {
        switch preference {
        case .balanced:
            Color(hex: isDark ? 0x3DCC70 : 0x1A8A48)
        case .vibrant:
            Color(hex: isDark ? 0x22D6C4 : 0x0C948C)
        }
    }

    /// 空闲轨道只交代圆环轮廓，不携带模块色；与行背景渐变和分隔线的着色独立。
    var cpuCoreTrack: Color {
        switch preference {
        case .balanced:
            return neutralSeparator
        case .vibrant:
            return isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
        }
    }

    /// 行卡片表面渐变与填充规格：平衡为均布中性玻璃；活力深色采用高浓度渐变，浅色采用低浓度行头微晕并衰减归零。
    struct RowGlassSpec {
        let color: Color
        let fullOpacity: Double
        let faintOpacity: Double
        let fadeEnd: Double
        let isUniform: Bool
    }

    func rowGlassSpec(for kind: MonitorKind?) -> RowGlassSpec {
        if preference == .balanced {
            return RowGlassSpec(color: neutralGlassTint, fullOpacity: 1, faintOpacity: 1,
                                fadeEnd: MonitorConstants.rowTintFadeEnd, isUniform: true)
        }
        if isDark {
            let tint = kind.map { moduleTint(for: $0) } ?? displayTint
            return RowGlassSpec(color: tint, fullOpacity: vibrantGlassOpacity,
                                faintOpacity: MonitorConstants.rowTintFaintOpacity,
                                fadeEnd: MonitorConstants.rowTintFadeEnd, isUniform: false)
        }
        // 浅色活力：行头仅附轻度微晕（暖色使用解耦底色），在 108pt 处完全衰减至透明，保持展开区中性可读。
        let surface = kind.map { vibrantLightSurfaceTint(for: $0) } ?? displayTint
        let isWarm = kind == .cpu || kind == .storage
        return RowGlassSpec(color: surface, fullOpacity: isWarm ? 0.024 : 0.032,
                            faintOpacity: 0.0, fadeEnd: 108.0, isUniform: false)
    }

    /// 行玻璃填充:平衡为均布中性玻璃;活力按明暗分层衰减。
    @ViewBuilder
    func rowGlassFill(for kind: MonitorKind) -> some View {
        let spec = rowGlassSpec(for: kind)
        if spec.isUniform {
            spec.color
        } else {
            RowGlassFadeFill(
                tint: spec.color,
                fullOpacity: spec.fullOpacity,
                faintOpacity: spec.faintOpacity,
                fadeEnd: spec.fadeEnd
            )
        }
    }

    @ViewBuilder
    var displayGlassFill: some View {
        let spec = rowGlassSpec(for: nil)
        if spec.isUniform {
            spec.color
        } else {
            RowGlassFadeFill(
                tint: spec.color,
                fullOpacity: spec.fullOpacity,
                faintOpacity: spec.faintOpacity,
                fadeEnd: spec.fadeEnd
            )
        }
    }

    /// 活力行玻璃满浓度不透明度：深色 16% 呈现发光层次，浅色 3.2% 控制染色轻盈。
    var vibrantGlassOpacity: Double {
        isDark ? 0.16 : 0.032
    }

    /// 行卡白罩，内容和原生底座共用，保持材质层次一致。
    /// 调试构建可用 `-HagimiCardBrighten` 覆盖浅色这一层。
    var cardBrightenOpacity: Double {
        if isDark { return 0.01 }
        if let override = TemporaryInstanceOverrides.lightCardBrightenOpacity {
            return override
        }
        switch preference {
        case .balanced:
            return 0.08
        case .vibrant:
            return 0.10
        }
    }

    func rowSeparator(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            return neutralSeparator
        case .vibrant:
            return moduleTint(for: kind).opacity(isDark ? 0.28 : 0.11)
        }
    }

    var displaySeparator: Color {
        switch preference {
        case .balanced:
            return neutralSeparator
        case .vibrant:
            return isDark ? displayTint.opacity(0.28) : Color.black.opacity(0.08)
        }
    }

    var displayBadgeFill: Color {
        switch preference {
        case .balanced:
            if isDark {
                return Color(hex: 0x7A91B4).opacity(0.16)
            }
            return displayTint.opacity(0.11)
        case .vibrant:
            return displayTint.opacity(isDark ? 0.18 : 0.11)
        }
    }

    func badgeFill(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            moduleTint(for: kind).opacity(isDark ? 0.18 : 0.10)
        case .vibrant:
            moduleTint(for: kind).opacity(isDark ? 0.20 : 0.12)
        }
    }

    /// 平衡行的中性玻璃。
    var neutralGlassTint: Color {
        if isDark { return Color.black.opacity(0.22) }
        return Color.white.opacity(0.18)
    }

    private var neutralSeparator: Color {
        if isDark {
            return Color(hex: 0x7A91B4).opacity(0.22)
        }
        return Color.black.opacity(0.08)
    }

    private func balancedModuleTint(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu:
            return Color(hex: isDark ? 0xE08355 : 0xC25E2E)
        case .gpu:
            return Color(hex: isDark ? 0x7E82F2 : 0x5B5FD1)
        case .memory:
            return Color(hex: isDark ? 0x45B2A5 : 0x22877C)
        case .storage:
            return Color(hex: isDark ? 0xB89D6E : 0x8A6F44)
        case .network:
            return Color(hex: isDark ? 0x47A8D4 : 0x1E7CA6)
        case .battery:
            return Color(hex: isDark ? 0x4CC275 : 0x2FA85F)
        case .fan:
            return Color(hex: isDark ? 0x64B5CC : 0x368199)
        case .bluetooth:
            return Color(hex: isDark ? 0x5594E8 : 0x2F6BC0)
        }
    }

    private func vibrantModuleTint(for kind: MonitorKind) -> Color {
        if isDark {
            // 深色活力使用高饱和前景，适配暗底发光层次。
            switch kind {
            case .cpu: return Color(hex: 0xF97316)
            case .gpu: return Color(hex: 0xA855F7)
            case .memory: return Color(hex: 0x1192E8)
            case .storage: return Color(hex: 0xB28600)
            case .network: return Color(hex: 0x009D9A)
            case .battery: return Color(hex: 0x2AB55E)
            case .fan: return Color(hex: 0x6366F1)
            case .bluetooth: return Color(hex: 0x0082FC)
            }
        }
        // 浅色活力使用压深提纯前景，确保浅底下的图形与文字对比度。
        switch kind {
        case .cpu: return Color(hex: 0xD95B08)
        case .gpu: return Color(hex: 0x8B3DFF)
        case .memory: return Color(hex: 0x0B7AD1)
        case .storage: return Color(hex: 0x9C6B00)
        case .network: return Color(hex: 0x008280)
        case .battery: return Color(hex: 0x26AD59)
        case .fan: return Color(hex: 0x5254E8)
        case .bluetooth: return Color(hex: 0x0072E3)
        }
    }

    /// 浅色活力底色解耦：暖色向清透蜜柑/琥珀偏移，避开肉粉与泥黄。
    private func vibrantLightSurfaceTint(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu: Color(hex: 0xF58220)
        case .storage: Color(hex: 0xC88A14)
        default: vibrantModuleTint(for: kind)
        }
    }
}

/// 调试构建用来区分并排打开的临时实例。
/// `-HagimiInstanceLabel` 显示在面板标题旁；`-HagimiTrackFill` 覆盖当前外观下指标格和凹槽的浓度；
/// `-HagimiSurfaceVeil` 覆盖浅色窗口白罩；`-HagimiCardBrighten` 覆盖浅色行卡白罩。正式包不读这些参数。
enum TemporaryInstanceOverrides {
    static var label: String? {
        #if DEBUG
        let value = UserDefaults.standard.string(forKey: "HagimiInstanceLabel") ?? ""
        return value.isEmpty ? nil : value
        #else
        return nil
        #endif
    }

    static var trackFillOpacity: Double? {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: "HagimiTrackFill") != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: "HagimiTrackFill")
        guard value >= 0, value <= 1 else { return nil }
        return value
        #else
        return nil
        #endif
    }

    static var lightCardBrightenOpacity: Double? {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: "HagimiCardBrighten") != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: "HagimiCardBrighten")
        guard value >= 0, value <= 1 else { return nil }
        return value
        #else
        return nil
        #endif
    }

    static var lightSurfaceVeilOpacity: Double? {
        #if DEBUG
        guard UserDefaults.standard.object(forKey: "HagimiSurfaceVeil") != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: "HagimiSurfaceVeil")
        guard value >= 0, value <= 1 else { return nil }
        return value
        #else
        return nil
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

}

/// 活力行玻璃的垂直衰减填充:停靠点按实际行高换算,收起的行整卡落在
/// plateau 满浓度段;展开时底部衰减到近中性。GeometryReader 随行高补间
/// 逐帧重算,展开动画期间渐变同步滑动,不产生跳变。
private struct RowGlassFadeFill: View {
    var tint: Color
    var fullOpacity: Double
    var faintOpacity: Double = MonitorConstants.rowTintFaintOpacity
    var fadeEnd: Double = MonitorConstants.rowTintFadeEnd

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(fullOpacity), location: 0),
                    .init(color: tint.opacity(fullOpacity),
                          location: min(MonitorConstants.rowTintPlateau / height, 1)),
                    .init(color: tint.opacity(faintOpacity),
                          location: min(fadeEnd / height, 1))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
