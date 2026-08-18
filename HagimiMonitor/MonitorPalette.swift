import SwiftUI

struct MonitorPalette {
    let preference: MonitorColorSchemePreference
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.96) : Color(hex: 0x171D2A)
    }

    var valueText: Color {
        isDark ? Color.white.opacity(0.90) : Color(hex: 0x2F3747)
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.82) : Color(hex: 0x465164)
    }

    var captionText: Color {
        isDark ? Color.white.opacity(0.78) : Color(hex: 0x4E5868)
    }

    var trackFill: Color {
        isDark ? Color.white.opacity(0.08) : Color(hex: 0x3C485A).opacity(0.08)
    }

    func liveDot(for loadLevel: MenuBarComputeLoadLevel) -> Color {
        Color(nsColor: loadLevel.coreColor(darkMode: isDark))
    }

    var displayTint: Color {
        switch preference {
        case .balanced:
            Color(hex: 0x4E7FD9)
        case .vibrant:
            Color(hex: 0xC268B8)
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

    func severityTint(for severity: MonitorSeverity) -> Color {
        switch severity {
        case .calm:
            Color(hex: 0x2F9E64)
        case .warning:
            Color(hex: 0xB8872E)
        case .critical:
            Color(hex: 0xD94848)
        }
    }

    /// P 核主色:独立于 CPU 模块主色。活力模式下 CPU 为橙,性能核用高醒目
    /// 绯红与行 tint 形成强对比,保证逐核圆环在彩色底上的辨识度;
    /// 平衡模式下与 CPU 主色一致。
    var performanceCoreTint: Color {
        switch preference {
        case .balanced:
            moduleTint(for: .cpu)
        case .vibrant:
            Color(hex: 0xFA4D56)
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
    private var vibrantGlassOpacity: Double {
        isDark ? 0.16 : 0.08
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

    private var neutralGlassTint: Color {
        Color(hex: 0x7A91B4).opacity(isDark ? 0.12 : 0.06)
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
            Color(hex: 0x6366F1)
        case .bluetooth:
            // Bluetooth SIG 官方蓝。
            Color(hex: 0x0082FC)
        }
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
