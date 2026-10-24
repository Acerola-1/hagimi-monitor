import AppKit
import CoreGraphics
import Foundation

nonisolated struct GameHUDWindowIdentity: Equatable, Sendable {
    let processIdentifier: pid_t
    let windowID: CGWindowID
}

/// 不可确认时不提供回退位置，调用方应隐藏 HUD。
nonisolated enum GameHUDWindowTarget: Equatable {
    case unavailable
    case target(windowID: CGWindowID, rect: CGRect, screen: NSScreen, sourceFrame: CGRect? = nil)
}

/// 低频发现窗口，独立检测仅查询已确认的 ID；两条路径共用边界校验。
/// 只读公开窗口信息，不需要录屏、辅助功能或输入监控授权。
@MainActor
final class GameHUDWindowLocator {
    private let windowInfo: (CGWindowListOption, CGWindowID) -> [[String: Any]]?

    init(windowInfo: @escaping (CGWindowListOption, CGWindowID) -> [[String: Any]]? = {
        CGWindowListCopyWindowInfo($0, $1) as? [[String: Any]]
    }) {
        self.windowInfo = windowInfo
    }

    struct WindowCandidate: Equatable {
        let windowID: CGWindowID
        let frame: CGRect
    }

    func resolveTargetWindow(processIdentifier: pid_t, minimumSize: CGSize) -> GameHUDWindowTarget {
        guard let list = windowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ),
              let chosen = list.compactMap({ Self.candidate(from: $0, ownedBy: processIdentifier) })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return .unavailable
        }
        return target(for: chosen, minimumSize: minimumSize)
    }

    func resolveTrackedWindow(_ identity: GameHUDWindowIdentity, minimumSize: CGSize) -> GameHUDWindowTarget {
        guard let list = windowInfo(.optionIncludingWindow, identity.windowID),
              let info = list.first,
              let candidate = Self.candidate(from: info, ownedBy: identity.processIdentifier),
              candidate.windowID == identity.windowID else { return .unavailable }
        return target(for: candidate, minimumSize: minimumSize)
    }

    static func candidate(from info: [String: Any], ownedBy pid: pid_t) -> WindowCandidate? {
        guard let owner = info[kCGWindowOwnerPID as String] as? Int, owner == Int(pid),
              let number = info[kCGWindowNumber as String] as? Int,
              number > 0, number <= Int(UInt32.max),
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha.isFinite, alpha > 0,
              let onScreen = info[kCGWindowIsOnscreen as String] as? Bool, onScreen,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"],
              [x, y, width, height].allSatisfy(\.isFinite), width >= 1, height >= 1 else { return nil }
        return WindowCandidate(windowID: CGWindowID(number), frame: CGRect(x: x, y: y, width: width, height: height))
    }

    /// CG 以主屏左上为原点，AppKit 以主屏左下为原点；外屏允许负坐标。
    /// 跨屏时选择可见交集最大的显示器，避免刚碰到外屏便跳到其边缘。
    static func visibleRegion(cgFrame: CGRect, primaryMaxY: CGFloat,
                              screens: [CGRect], minimumSize: CGSize) -> (screenIndex: Int, rect: CGRect)? {
        guard [cgFrame.minX, cgFrame.minY, cgFrame.width, cgFrame.height, primaryMaxY].allSatisfy(\.isFinite),
              cgFrame.width > 0, cgFrame.height > 0 else { return nil }
        let flipped = CGRect(x: cgFrame.minX, y: primaryMaxY - cgFrame.maxY,
                             width: cgFrame.width, height: cgFrame.height)
        let regions = screens.enumerated().compactMap { index, screen -> (Int, CGRect)? in
            let intersection = flipped.intersection(screen)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            return (index, intersection)
        }
        guard let chosen = regions.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }),
              chosen.1.width >= minimumSize.width, chosen.1.height >= minimumSize.height else { return nil }
        return (chosen.0, chosen.1)
    }

    private func target(for candidate: WindowCandidate, minimumSize: CGSize) -> GameHUDWindowTarget {
        let screens = NSScreen.screens
        guard let main = screens.first,
              let region = Self.visibleRegion(cgFrame: candidate.frame, primaryMaxY: main.frame.maxY,
                                              screens: screens.map(\.frame), minimumSize: minimumSize) else {
            return .unavailable
        }
        return .target(windowID: candidate.windowID, rect: region.rect, screen: screens[region.screenIndex],
                       sourceFrame: candidate.frame)
    }
}
