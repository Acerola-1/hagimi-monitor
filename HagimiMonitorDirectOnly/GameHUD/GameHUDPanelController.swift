import AppKit
import SwiftUI

/// 全屏贴屏幕安全区顶边，窗口化贴目标游戏窗口顶边。
enum GameHUDTopStripPlacement {
    static func frame(windowRect: CGRect, screenRect: CGRect, topSafeInset: CGFloat,
                      contentSize: CGSize, margin: CGFloat) -> CGRect? {
        let safeTop = max(0, topSafeInset)
        let visibleWindow = windowRect.intersection(screenRect)
        guard !visibleWindow.isNull,
              contentSize.height > 0 else { return nil }

        let safeTopY = screenRect.maxY - safeTop
        let fillsScreen = visibleWindow.width >= screenRect.width * 0.9
            && visibleWindow.height >= screenRect.height * 0.9
            && visibleWindow.maxY >= safeTopY - (safeTop > 0 ? safeTop + 2 : 2)
        let anchor = fillsScreen ? screenRect : visibleWindow
        guard contentSize.width + margin * 2 <= anchor.width else { return nil }

        let frame = CGRect(
            x: anchor.midX - contentSize.width / 2,
            y: (fillsScreen ? safeTopY : min(visibleWindow.maxY, safeTopY)) - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
        return frame
    }
}

/// Game HUD 硬件浮窗宿主:独立 NSPanel,配置沿探针实测结论(见
/// prototypes/game-hud-probe 的 OverlayProbe):
/// - borderless + nonactivatingPanel,`canBecomeKey/Main` 均为 false;
/// - level `.floating` 足以覆盖另一进程的原生全屏(无需 .statusBar);
/// - 点击穿透 `ignoresMouseEvents`(CGEvent 实测游戏仍收键且保持 key);
/// - 全 Space/全应用 + 全屏辅助行为,切 Space/进游戏全屏不掉层。
///
/// 面板生命周期与会话状态绑定:显示时按目标窗口矩形落位,目标变化
/// (移动/缩放/换屏)由会话控制器轮询驱动重算;隐藏时不重绘。
@MainActor
final class GameHUDPanelController {

    private var panel: GameHUDPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var activeStyle: GameHUDPresentationStyle = .card
    private let settings: MonitorSettings

    /// HUD 卡片与目标窗口边缘的安全边距(pt)。
    static let windowMargin: CGFloat = 16
    /// 受控会话下给官方 HUD 预留的顶部高度(pt)。官方实际高度不可查询,
    /// 这是保守值:预留不足可能重叠(MetalFX 瞬态),预留过度则小窗口
    /// 放不下 → 隐藏(宁可不见,不可裁切/盖错)。
    static let officialHUDReservedHeight: CGFloat = 190

    init(settings: MonitorSettings) {
        self.settings = settings
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 选择顶部横条时锚定屏幕或窗口顶边；单行放不下时显示卡片。
    /// - Parameters:
    ///   - windowRect: 目标游戏窗口的可见屏幕矩形。
    ///   - screen: 目标窗口所在屏幕，用于横条安全区落位。
    ///   - reserveTop: 是否给官方 HUD 预留顶部空间(仅官网受控会话)。
    ///   - fpsStats: 帧率统计快照(用于确定 FPS 与 1% Low 行所占高度)。
    ///   - content: HUD 内容视图。
    func show(in windowRect: CGRect, screen: NSScreen?, reserveTop: Bool,
              fpsStats: GameHUDFPSStats? = nil, content: GameHUDContent) {
        let stripFrame: CGRect?
        if settings.gameHUDPresentationStyle == .topStrip, let screen {
            let strip = NSHostingView(rootView: content.rootView(for: .topStrip))
            strip.safeAreaRegions = []
            stripFrame = GameHUDTopStripPlacement.frame(
                windowRect: windowRect, screenRect: screen.frame,
                topSafeInset: screen.safeAreaInsets.top,
                contentSize: strip.fittingSize, margin: Self.windowMargin
            )
        } else {
            stripFrame = nil
        }
        let style: GameHUDPresentationStyle = stripFrame == nil ? .card : .topStrip
        activeStyle = style
        if hostingView == nil {
            let hosting = NSHostingView(rootView: content.rootView(for: style))
            hosting.safeAreaRegions = style == .topStrip ? [] : .all
            self.hostingView = hosting
        } else {
            hostingView?.rootView = content.rootView(for: style)
            hostingView?.safeAreaRegions = style == .topStrip ? [] : .all
        }
        let measuredHeight = hostingView?.fittingSize.height
        let effectiveHeight = (measuredHeight ?? 0) > 40 ? measuredHeight : nil
        guard let frame = stripFrame ?? hudFrame(in: windowRect, reserveTop: reserveTop,
                                                 fpsStats: fpsStats, customHeight: effectiveHeight) else {
            hide()
            return
        }
        let panel = ensurePanel(frame: frame)
        if panel.contentView !== hostingView {
            panel.contentView = hostingView
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible || !panel.isOnActiveSpace {
            panel.orderFrontRegardless()
        }
    }

    /// 重算落位:目标窗口移动/缩放/换屏时调用。frame 计算失败即隐藏,
    /// 不留在旧位置。
    func updateFrame(in windowRect: CGRect, reserveTop: Bool, fpsStats: GameHUDFPSStats? = nil) {
        guard let panel, panel.isVisible else { return }
        guard activeStyle == .card else { return }
        let measuredHeight = hostingView?.fittingSize.height
        let effectiveHeight = (measuredHeight ?? 0) > 40 ? measuredHeight : nil
        guard let frame = hudFrame(in: windowRect, reserveTop: reserveTop, fpsStats: fpsStats, customHeight: effectiveHeight) else {
            hide()
            return
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        hostingView = nil
        activeStyle = .card
    }

    /// HUD 在目标窗口内的候选矩形:所选侧下角 + 安全边距。受控会话时
    /// 顶部预留官方 HUD 空间。放不下返回 nil(隐藏,不裁切)。
    private func hudFrame(in windowRect: CGRect, reserveTop: Bool, fpsStats: GameHUDFPSStats? = nil, customHeight: CGFloat? = nil) -> CGRect? {
        let baseSize = GameHUDViewContract.size(for: settings.gameHUDEnabledMetricIDs, fpsStats: fpsStats)
        let contentSize = CGSize(width: baseSize.width, height: customHeight ?? baseSize.height)
        let margin = Self.windowMargin
        let availableHeight = windowRect.height - margin * 2 - (reserveTop ? Self.officialHUDReservedHeight : 0)
        guard contentSize.width + margin * 2 <= windowRect.width,
              contentSize.height <= availableHeight else {
            return nil
        }
        let x: CGFloat
        let y: CGFloat
        switch settings.gameHUDSidePreference {
        case .topLeft:
            x = windowRect.minX + margin
            y = windowRect.maxY - margin - contentSize.height
        case .topRight:
            x = windowRect.maxX - margin - contentSize.width
            y = windowRect.maxY - margin - contentSize.height
        case .bottomLeft:
            x = windowRect.minX + margin
            y = windowRect.minY + margin
        case .bottomRight:
            x = windowRect.maxX - margin - contentSize.width
            y = windowRect.minY + margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: contentSize)
    }

    private func ensurePanel(frame: NSRect) -> GameHUDPanel {
        if let panel { return panel }
        let panel = GameHUDPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }
}

/// 见 GameHUDPanelController 文档:探针验证过的浮窗档位。
@MainActor
private final class GameHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 透明浮窗允许贴到物理屏幕边缘；默认约束会让外屏退到菜单栏可视区。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
