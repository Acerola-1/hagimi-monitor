import AppKit
import Foundation

/// Game HUD 的游戏名单:内置保守候选 + 用户添加 + 用户排除(优先级最高)。
///
/// 内置候选的原则(spec:游戏识别与显示门槛):仅因「用了 Metal/OpenGL」
/// 不足以判为游戏;首批名单逐项人工登记 bundle ID,宁可漏判不可误判。
/// 名单为空时功能仍可用——用户手动添加始终有效。
@MainActor
enum GameHUDGameDirectory {

    /// 内置保守候选。当前为空是刻意的:首批 bundle ID 需在真实游戏上逐项
    /// 验证窗口身份(见 tasks 1.5/3.1)后再登记;登记前依赖用户手动添加。
    /// 新增条目时同步在注释记录来源与验证日期。
    static let builtinCandidates: Set<String> = []

    /// 判定前台 bundle ID 是否命中名单。
    ///
    /// 2026-09-26 定案:扫描结果自动采纳,名单 = 「扫描能发现的一切游戏 −
    /// 用户排除」。内置候选保留(真实游戏验证后登记,不看扫描也能命中),
    /// customGames 继续承载手动添加(浏览兜底)与自动采纳的持久化记录。
    static func matches(bundleID: String?, settings: MonitorSettings) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        if settings.gameHUDExcludedGames.contains(bundleID) {
            return false
        }
        return builtinCandidates.contains(bundleID)
            || settings.gameHUDCustomGames.contains(bundleID)
            || GameHUDGameScanner.shared.knownGameBundleIDs.contains(bundleID)
    }

    /// 名单页展示:内置候选 + 用户添加,排除项单独分组由设置页渲染。
    static func catalogEntries(settings: MonitorSettings) -> (candidates: [String], custom: [String], excluded: [String]) {
        let excluded = settings.gameHUDExcludedGames.sorted()
        let candidates = (builtinCandidates.subtracting(settings.gameHUDExcludedGames)).sorted()
        let custom = (settings.gameHUDCustomGames.subtracting(settings.gameHUDExcludedGames)).sorted()
        return (candidates, custom, excluded)
    }
}

/// 前台应用的游戏身份与进程信息。受控启动(官网版)会额外携带会话身份,
/// 普通启动的进程靠这里识别。
nonisolated struct GameHUDForegroundGame: Equatable, Sendable {
    let bundleID: String
    let processIdentifier: pid_t
    let localizedName: String
}
