import AppKit
import CoreGraphics
import Foundation

/// 目标游戏窗口确认结果。`unavailable` 是明确的「不可显示」结论,
/// 不携带任何回退位置——HUD 隐藏,不退回整屏角落(spec:没有可靠目标窗口)。
nonisolated enum GameHUDWindowTarget: Equatable {
    case unavailable
    case target(rect: CGRect, screen: NSScreen)
}

/// 前台游戏的窗口定位器:从系统窗口列表中确认该游戏的唯一目标窗口、
/// 可见屏幕矩形与所属显示器。
///
/// 数据源为公开 API(CGWindowListCopyWindowInfo 的窗口层级/边界 +
/// NSScreen 坐标系),不要求录屏、辅助功能或输入监控授权。
/// 任何无法确认的情形(窗口不可见、候选歧义、边界不合法)一律返回
/// `unavailable`,由调用方隐藏 HUD;从不猜一个近似矩形。
@MainActor
final class GameHUDWindowLocator {

    struct WindowCandidate: Equatable {
        let windowID: CGWindowID
        let frame: CGRect
        /// 窗口层级(0=常规窗口,越高越靠前)。透明辅助层不参与选窗。
        let layer: Int
    }

    /// 确认目标窗口。
    /// - Parameters:
    ///   - processIdentifier: 游戏进程 PID。窗口必须属于该进程,启动器
    ///     存活不会让 HUD 留守(spec:游戏失焦、窗口关闭或退出)。
    ///   - minimumSize: 目标窗口短边下限;放不下 HUD 的窗口按不可显示处理。
    func resolveTargetWindow(processIdentifier: pid_t, minimumSize: CGSize) -> GameHUDWindowTarget {
        let candidates = visibleWindows(ownedBy: processIdentifier)
        guard let chosen = chooseTarget(from: candidates) else {
            return .unavailable
        }
        // 屏幕坐标:CGWindowList 边界以全局左上角为原点(y 向下),而
        // NSScreen.frame 以主屏左下角为原点(y 向上),必须先翻转再用,
        // 否则求交矩形整体上下镜像。翻转公式:全局高度 = 主屏 frame 高度
        // (菜单栏所在屏),y' = globalHeight − y − height。
        guard let mainScreen = NSScreen.screens.first else {
            return .unavailable
        }
        let globalHeight = mainScreen.frame.maxY
        let flipped = CGRect(
            x: chosen.frame.minX,
            y: globalHeight - chosen.frame.maxY,
            width: chosen.frame.width,
            height: chosen.frame.height
        )
        // 命中不到任何屏幕(罕见:刚拔线、虚拟显示器)按不可显示处理。
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(flipped) }) else {
            return .unavailable
        }
        // 与屏幕求交:窗口部分停在屏幕外(拖到一半)时,HUD 锚定在可见部分。
        let visibleRect = flipped.intersection(screen.frame)
        guard visibleRect.width >= minimumSize.width, visibleRect.height >= minimumSize.height else {
            return .unavailable
        }
        return .target(rect: visibleRect, screen: screen)
    }

    /// 该进程的全部「常规窗口层」可见候选。最小化(CGSWindowOnScreen 缺失)、
    /// alpha 0、辅助层(菜单、Dock、状态条)都不进候选。
    private func visibleWindows(ownedBy processIdentifier: pid_t) -> [WindowCandidate] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        var result: [WindowCandidate] = []
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == Int(processIdentifier) else {
                continue
            }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            guard let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha > 0 else {
                continue
            }
            let frame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            // 空窗口与钉在角落的 helper 窗口(如 1×1)不参与。
            guard frame.width >= 1, frame.height >= 1 else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? Int else { continue }
            result.append(WindowCandidate(windowID: CGWindowID(windowID), frame: frame, layer: layer))
        }
        return result
    }

    /// 候选消歧:取面积最大的候选。游戏进程通常只有一个常规窗口;出现
    /// 多个时(调试面板等),最大的那块是游戏画面——比「随机选一个」可靠,
    /// 比强行显示更安全。候选为空即不可显示。
    private func chooseTarget(from candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
