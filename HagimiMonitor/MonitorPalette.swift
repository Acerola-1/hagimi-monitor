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
        isDark ? Color.white.opacity(0.78) : Color(hex: 0x3E4756)
    }

    /// 指标格、进度槽和展开区内衬共用。深色用 3% 白，浅色用同一块深石板的 5%。
    /// 调试构建可用 `-HagimiTrackFill` 覆盖当前外观下的浓度。
    var trackFill: Color {
        if isDark {
            let opacity = TemporaryInstanceOverrides.trackFillOpacity ?? 0.03
            return Color.white.opacity(opacity)
        }
        let opacity = TemporaryInstanceOverrides.trackFillOpacity ?? 0.05
        return Color(hex: 0x3C485A).opacity(opacity)
    }

    /// 主行成对读数的浅底。浅色这块比指标格更需要轮廓，用 8% 深石板；深色仍跟指标格走。
    var rowGrooveFill: Color {
        guard !isDark else { return trackFill }
        return Color(hex: 0x3C485A).opacity(0.08)
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
            Color(hex: 0x4E7FD9)
        case .vibrant:
            // 中性蓝灰:紫族只留给 GPU,显示器是附属信息行,低饱和退场不抢色。
            Color(hex: 0x64748B)
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
        switch severity {
        case .calm:
            Color(hex: 0x2F9E64)
        case .warning:
            Color(hex: 0xB8872E)
        case .critical:
            Color(hex: Self.criticalTintHex)
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
            neutralSeparator
        case .vibrant:
            isDark ? Color.white.opacity(0.22) : Color(hex: 0x3C485A).opacity(0.18)
        }
    }

    /// 行玻璃填充:平衡为均布中性玻璃;活力为垂直衰减渐变——行头保持满浓度,
    /// 向下衰减至近中性,展开区小字不受模块色相干扰(参数见 MonitorConstants)。
    @ViewBuilder
    func rowGlassFill(for kind: MonitorKind) -> some View {
        switch preference {
        case .balanced:
            neutralGlassTint
        case .vibrant:
            RowGlassFadeFill(tint: moduleTint(for: kind), fullOpacity: vibrantGlassOpacity)
        }
    }

    @ViewBuilder
    var displayGlassFill: some View {
        switch preference {
        case .balanced:
            neutralGlassTint
        case .vibrant:
            RowGlassFadeFill(tint: displayTint, fullOpacity: vibrantGlassOpacity)
        }
    }

    /// 活力行玻璃满浓度不透明度:暗底需要更高浓度才能显出模块色相。
    var vibrantGlassOpacity: Double {
        isDark ? 0.16 : 0.08
    }

    /// 行卡白罩，内容和原生底座共用，保持材质层次一致。
    /// 深色统一 1%，展开区少被抬白。浅色 5%，把薄玻璃收成磨砂卡片，又不过度抬白。
    /// 调试构建可用 `-HagimiCardBrighten` 覆盖浅色这一层。
    var cardBrightenOpacity: Double {
        if isDark { return 0.01 }
        return TemporaryInstanceOverrides.lightCardBrightenOpacity ?? 0.05
    }

    func rowSeparator(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            neutralSeparator
        case .vibrant:
            moduleTint(for: kind).opacity(isDark ? 0.28 : 0.18)
        }
    }

    var displaySeparator: Color {
        switch preference {
        case .balanced:
            neutralSeparator
        case .vibrant:
            displayTint.opacity(isDark ? 0.28 : 0.18)
        }
    }

    var displayBadgeFill: Color {
        switch preference {
        case .balanced:
            Color(hex: 0x7A91B4).opacity(isDark ? 0.16 : 0.10)
        case .vibrant:
            displayTint.opacity(isDark ? 0.18 : 0.10)
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

    /// 平衡行的中性玻璃。深色用较重的黑罩把毛玻璃压暗，展开区小字落在深底上；
    /// 浅色用低浓度石板色，只和窗口分开一层。
    var neutralGlassTint: Color {
        if isDark { return Color.black.opacity(0.22) }
        return Color(hex: 0x7A91B4).opacity(0.06)
    }

    private var neutralSeparator: Color {
        Color(hex: 0x7A91B4).opacity(isDark ? 0.22 : 0.14)
    }

    private func balancedModuleTint(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu:
            Color(hex: 0xD27A4A)
        case .gpu:
            Color(hex: 0x5D8CF0)
        case .memory:
            Color(hex: 0x42A39A)
        case .storage:
            Color(hex: 0x9A865E)
        case .network:
            Color(hex: 0x43A6A0)
        case .battery:
            Color(hex: 0x55BC6F)
        case .fan:
            // 风扇色与系统色温呼应:蓝青系,弱化视觉权重,避免与 CPU/内存(暖色)抢眼。
            Color(hex: 0x5BB0C2)
        case .bluetooth:
            // 蓝牙标志色:平衡主题降低饱和,与调色板其余模块的柔和度对齐。
            Color(hex: 0x4A90D9)
        }
    }

    private func vibrantModuleTint(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu:
            Color(hex: 0xF97316)
        case .gpu:
            Color(hex: 0xA855F7)
        case .memory:
            Color(hex: 0x1192E8)
        case .storage:
            Color(hex: 0xB28600)
        case .network:
            Color(hex: 0x009D9A)
        case .battery:
            Color(hex: 0x2AB55E)
        case .fan:
            // 靛蓝紫:与相邻内存行(#1192E8 蓝)、GPU 紫(#A855F7)同为蓝紫族,
            // 色相相邻、保持可辨。
            Color(hex: 0x6366F1)
        case .bluetooth:
            // Bluetooth SIG 官方蓝。
            Color(hex: 0x0082FC)
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

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(fullOpacity), location: 0),
                    .init(color: tint.opacity(fullOpacity),
                          location: min(MonitorConstants.rowTintPlateau / height, 1)),
                    .init(color: tint.opacity(MonitorConstants.rowTintFaintOpacity),
                          location: min(MonitorConstants.rowTintFadeEnd / height, 1))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
