import SwiftUI

/// 同一份快照的卡片与顶部横条视图，由设置与可用宽度选择其一。
nonisolated struct GameHUDContent {
    let cardView: AnyView
    let topStripView: AnyView

    func rootView(for style: GameHUDPresentationStyle) -> AnyView {
        style == .topStrip ? topStripView : cardView
    }
}
