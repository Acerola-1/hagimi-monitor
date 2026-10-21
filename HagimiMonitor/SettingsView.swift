import Foundation

enum SettingsTab: String {
    case general
    case statistics
    case storage
    case about
    #if DIRECT_DISTRIBUTION
    /// Game HUD 设置页深链(仅官网版;用于原生验收夹具与内部路由)。
    case gameHUD
    #endif
}
