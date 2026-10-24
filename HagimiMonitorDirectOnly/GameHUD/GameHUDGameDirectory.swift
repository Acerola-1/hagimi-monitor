import AppKit
import Foundation

/// Game HUD 的显示资格与设置名单同源。
///
/// 资格完全由 `MonitorSettings.gameHUDRegistry` 决定:
/// 「存在有效自动来源或手动添加意图,且不在黑名单」。
/// 内置候选不单独维护:游戏通过扫描来源(Steam/Epic/类别)自动进入登记;
/// 任何能触发 HUD 的身份都必须在登记里有可管理行。
@MainActor
enum GameHUDGameDirectory {
    /// 判定前台 bundle ID 是否命中启用名单。
    static func matches(bundleID: String?, settings: MonitorSettings) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return settings.gameHUDRegistry.isEligible(bundleID)
    }
}

/// 前台应用的游戏身份与进程信息。受控启动(官网版)会额外携带会话身份,
/// 普通启动的进程靠这里识别。
nonisolated struct GameHUDForegroundGame: Equatable, Sendable {
    let bundleID: String
    let processIdentifier: pid_t
    let localizedName: String
}
