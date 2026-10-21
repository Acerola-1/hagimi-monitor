import SwiftUI

/// HUD 背景外观的唯一所有者。
///
/// 两种样式的现有背景不透明度集中登记在这里;透明度是 0...1 的“透出程度”,
/// 背景 alpha 恒为 `1 - transparency`,所以默认值恰好还原各自现有外观:
/// 卡片 1 - 0.68 = 32%,顶部横条 1 - 0.72 = 28%。
/// 只改变背景填充,不修改窗口 alpha、整棵 HUD 的 opacity 或文字颜色。
nonisolated enum GameHUDBackgroundAppearance {
    static let cardBaseOpacity: Double = 0.68
    static let topStripBaseOpacity: Double = 0.72
    static let step: Double = 0.01

    static func baseOpacity(for style: GameHUDPresentationStyle) -> Double {
        switch style {
        case .card: cardBaseOpacity
        case .topStrip: topStripBaseOpacity
        }
    }

    static func defaultTransparency(for style: GameHUDPresentationStyle) -> Double {
        1 - baseOpacity(for: style)
    }

    /// 非法存储(NaN/无穷/越界)安全夹取或回退到该样式默认值。
    static func normalized(_ value: Double, for style: GameHUDPresentationStyle) -> Double {
        guard value.isFinite else { return defaultTransparency(for: style) }
        return min(max(value, 0), 1)
    }

    static func storedTransparency(_ stored: Double?, for style: GameHUDPresentationStyle) -> Double {
        guard let stored else { return defaultTransparency(for: style) }
        return normalized(stored, for: style)
    }

    static func backgroundAlpha(for style: GameHUDPresentationStyle, transparency: Double) -> Double {
        1 - normalized(transparency, for: style)
    }

    static func backgroundColor(for style: GameHUDPresentationStyle, transparency: Double) -> Color {
        Color.black.opacity(backgroundAlpha(for: style, transparency: transparency))
    }

    static func percent(_ transparency: Double, for style: GameHUDPresentationStyle) -> Int {
        Int((normalized(transparency, for: style) * 100).rounded())
    }
}

/// 透明度示例预览的几何合同。预览是局部样本,不是正式 HUD 的缩略图:
/// 高度上限只有一个来源,超出时减少静态示例而不是缩小文字。
nonisolated enum GameHUDPreviewContract {
    static let maxHeight: CGFloat = 140
    static let cardContainerHeight: CGFloat = 140
    static let topStripContainerHeight: CGFloat = 72

    static func containerHeight(for style: GameHUDPresentationStyle) -> CGFloat {
        min(maxHeight, style == .card ? cardContainerHeight : topStripContainerHeight)
    }
}

/// 预览背景模式:静态明亮/深色/复杂底纹,不画大型游戏场景,不启动动画。
nonisolated enum GameHUDPreviewBackground: String, CaseIterable, Identifiable, Sendable {
    case bright
    case dark
    case complex

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .bright: "gamehud.appearance.preview.background.bright"
        case .dark: "gamehud.appearance.preview.background.dark"
        case .complex: "gamehud.appearance.preview.background.complex"
        }
    }
}

/// 预览固定样本:少量完整指标,正常字号,和正式监控、历史、测帧完全隔离。
nonisolated enum GameHUDPreviewSample {
    static let enabledIDs: Set<GameHUDMetricID> = [.fps, .cpuUsage]

    static let snapshot = GameHUDSnapshot(
        readings: [
            GameHUDReading(metricID: GameHUDMetricID.cpuUsage.rawValue, kind: .cpu, value: "12%", percent: 12),
        ],
        date: Date(timeIntervalSince1970: 0)
    )

    static let fpsStats = GameHUDFPSStats(
        currentFPS: 60,
        averageFPS: 60,
        onePercentLow: nil,
        frameTimeMs: nil
    )
}

/// 静态背景底纹。只用于观察背景透出与文字对比,不承载产品表面语义。
struct GameHUDPreviewBackdrop: View {
    let background: GameHUDPreviewBackground

    var body: some View {
        switch background {
        case .bright:
            LinearGradient(
                colors: [Color.white, Color(white: 0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .complex:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.18, blue: 0.30), Color(red: 0.32, green: 0.10, blue: 0.30)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                GeometryReader { proxy in
                    Circle()
                        .fill(Color.orange.opacity(0.42))
                        .frame(width: proxy.size.width * 0.42, height: proxy.size.width * 0.42)
                        .offset(x: proxy.size.width * 0.62, y: -proxy.size.height * 0.18)
                    Circle()
                        .fill(Color.teal.opacity(0.38))
                        .frame(width: proxy.size.width * 0.35, height: proxy.size.width * 0.35)
                        .offset(x: -proxy.size.width * 0.08, y: proxy.size.height * 0.42)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: proxy.size.width * 0.7, height: 2)
                        .rotationEffect(.degrees(-18))
                        .offset(x: proxy.size.width * 0.2, y: proxy.size.height * 0.25)
                }
            }
        }
    }
}
