import AppKit
import SwiftUI

struct MonitorPalette {
    let preference: MonitorColorSchemePreference
    let colorScheme: ColorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    var primaryText: Color {
        Color(nsColor: .labelColor)
    }

    var valueText: Color {
        Color(nsColor: .labelColor)
    }

    var secondaryText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    var captionText: Color {
        Color(nsColor: .secondaryLabelColor)
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

    /// 快捷功能统一强调色:全部工具共用一紫,激活状态一眼可辨,
    /// 不随主题切换漂移。
    var quickToolTint: Color {
        Color(hex: 0xA855F7)
    }

    /// 快捷功能磁贴点亮态底色:强调色低透明铺底,深色模式下稍亮
    /// 以维持可辨识度。
    var quickToolActiveFill: Color {
        quickToolTint.opacity(isDark ? 0.16 : 0.10)
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

    /// macOS 15 行玻璃回退填充。两套配色都保留模块色，并向展开区逐渐
    /// 衰减，避免大面积色块干扰明细文字。
    @ViewBuilder
    func rowGlassFill(for kind: MonitorKind) -> some View {
        switch preference {
        case .balanced:
            RowGlassFadeFill(tint: moduleTint(for: kind), fullOpacity: fallbackBalancedGlassOpacity)
        case .vibrant:
            RowGlassFadeFill(tint: moduleTint(for: kind), fullOpacity: fallbackVibrantGlassOpacity)
        }
    }

    /// macOS 26 原生 Liquid Glass 的模块 tint。颜色只进入系统玻璃管线，
    /// 折射、高光和前景对比度仍由系统负责。
    func rowGlassTint(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            moduleTint(for: kind).opacity(liquidBalancedGlassOpacity)
        case .vibrant:
            moduleTint(for: kind).opacity(liquidVibrantGlassOpacity)
        }
    }

    @ViewBuilder
    var displayGlassFill: some View {
        switch preference {
        case .balanced:
            RowGlassFadeFill(tint: displayTint, fullOpacity: fallbackBalancedGlassOpacity)
        case .vibrant:
            RowGlassFadeFill(tint: displayTint, fullOpacity: fallbackVibrantGlassOpacity)
        }
    }

    /// 显示器行的 macOS 26 Liquid Glass tint。
    var displayGlassTint: Color {
        switch preference {
        case .balanced:
            displayTint.opacity(liquidBalancedGlassOpacity)
        case .vibrant:
            displayTint.opacity(liquidVibrantGlassOpacity)
        }
    }

    private var fallbackBalancedGlassOpacity: Double {
        isDark ? 0.12 : 0.06
    }

    /// 旧系统回退靠自绘颜色表现模块归属，活力主题适当提高色彩层次。
    private var fallbackVibrantGlassOpacity: Double {
        isDark ? 0.18 : 0.10
    }

    private var liquidBalancedGlassOpacity: Double {
        isDark ? 0.11 : 0.07
    }

    /// 原生 clear glass 只接受单色 tint；这里保持足够辨识度，同时让底层
    /// regular glass 和边缘高光清晰透出。
    private var liquidVibrantGlassOpacity: Double {
        isDark ? 0.15 : 0.09
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
