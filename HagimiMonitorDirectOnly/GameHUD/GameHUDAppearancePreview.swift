import SwiftUI

/// 透明度局部样本:复用正式 HUD 的字体、背景与指标片段,只传固定的小样本。
///
/// 它不是正式 HUD 的缩略图:不读取用户勾选集合,不启动测帧/采样,
/// 不画游戏场景;高度由 `GameHUDPreviewContract` 统一封顶,超限时减少样本
/// 而不是缩小文字。
struct GameHUDAppearancePreview: View {
    let style: GameHUDPresentationStyle
    let transparency: Double
    let background: GameHUDPreviewBackground

    var body: some View {
        ZStack {
            GameHUDPreviewBackdrop(background: background)
            content
                .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: GameHUDPreviewContract.containerHeight(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(localized: "gamehud.appearance.preview.accessibility")))
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .card:
            GameHUDView(
                snapshot: GameHUDPreviewSample.snapshot,
                fpsStats: GameHUDPreviewSample.fpsStats,
                enabledMetricIDs: GameHUDPreviewSample.enabledIDs,
                backgroundTransparency: transparency
            )
        case .topStrip:
            GameHUDTopStripView(
                snapshot: GameHUDPreviewSample.snapshot,
                fpsStats: GameHUDPreviewSample.fpsStats,
                enabledMetricIDs: GameHUDPreviewSample.enabledIDs,
                backgroundTransparency: transparency
            )
        }
    }
}
