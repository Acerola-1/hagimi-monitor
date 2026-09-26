import SwiftUI

/// 传给浮窗的内容包装。
nonisolated struct GameHUDContent {
    let view: AnyView

    var rootView: AnyView { view }
}
