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
        isDark ? Color.white.opacity(0.68) : Color(hex: 0x5A6475)
    }

    var trackFill: Color {
        isDark ? Color.white.opacity(0.08) : Color(hex: 0x3C485A).opacity(0.08)
    }

    var liveDot: Color {
        Color(hex: 0x3DDC97)
    }

    var displayTint: Color {
        switch preference {
        case .balanced:
            Color(hex: 0x4E7FD9)
        case .vibrant:
            Color(hex: 0xFF7EB6)
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

    func rowGlassTint(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            neutralGlassTint
        case .vibrant:
            moduleTint(for: kind).opacity(isDark ? 0.16 : 0.08)
        }
    }

    func rowSeparator(for kind: MonitorKind) -> Color {
        switch preference {
        case .balanced:
            neutralSeparator
        case .vibrant:
            moduleTint(for: kind).opacity(isDark ? 0.28 : 0.18)
        }
    }

    var displayGlassTint: Color {
        switch preference {
        case .balanced:
            neutralGlassTint
        case .vibrant:
            displayTint.opacity(isDark ? 0.16 : 0.08)
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
            Color(hex: 0x65AF52)
        }
    }

    private func vibrantModuleTint(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu:
            Color(hex: 0xFA4D56)
        case .gpu:
            Color(hex: 0xA855F7)
        case .memory:
            Color(hex: 0x1192E8)
        case .storage:
            Color(hex: 0xB28600)
        case .network:
            Color(hex: 0x009D9A)
        case .battery:
            Color(hex: 0x198038)
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
