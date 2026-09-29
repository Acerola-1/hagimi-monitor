import Foundation

/// Game HUD 布局位置:硬件 HUD 放在目标游戏窗口的四象限(左上、右上、左下、右下, 默认右下)。
nonisolated enum GameHUDSide: String, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    init(fromStored string: String) {
        switch string {
        case "topLeft": self = .topLeft
        case "topRight": self = .topRight
        case "bottomLeft", "left": self = .bottomLeft
        case "bottomRight", "right": self = .bottomRight
        default: self = .bottomRight
        }
    }
}

/// HUD 呈现样式。顶部横条在目标窗口内能放入一行时使用。
nonisolated enum GameHUDPresentationStyle: String, CaseIterable, Sendable {
    case card
    case topStrip

    init(fromStored string: String) {
        self = GameHUDPresentationStyle(rawValue: string) ?? .topStrip
    }
}
