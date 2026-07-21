import AppKit
import Combine
import SwiftUI

/// 钉住面板控制器:管理一个可拖动、始终最前、失焦不关闭的常驻监控面板。
///
/// 与 `FluidPanelController`（菜单栏弹出面板）的关键区别:
/// - 可拖动（`isMovableByWindowBackground = true`）
/// - 始终最前（`level = .floating`）
/// - 失焦不关闭（`windowDidResignKey` 不做关闭）
/// - 不安装「点击外部关闭」的全局监听
/// - 位置持久化,重启后恢复
/// - 仅当前桌面显示（不含 `.canJoinAllSpaces`）
@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    private let openSettingsAction: () -> Void

    private let panel: NSPanel
    private var hostingView: NSHostingView<AnyView>?

    /// 面板圆角半径,与 FluidPanelController 一致。
    private static let panelCornerRadius: CGFloat = 12

    init(store: MonitorStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettingsAction = openSettings

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: MonitorConstants.panelIdealWidth, height: 200),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
    }

    deinit {
        // 若面板仍可见,通知 store 移除引用。
        if panel.isVisible {
            store.panelDidDisappear(.pinned)
        }
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isMovable = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        // 仅当前桌面显示,不跟随 Spaces 切换。
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        // 隐藏标题栏,做出无边框外观。
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // 毛玻璃背景,与 FluidPanelController 一致。
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.panelCornerRadius
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        // 面板内容:MonitorPanelView,注入 panelRole = .pinned 与关闭闭包。
        let root = MonitorPanelView(store: store)
            .environment(\.fluidOpenSettings, OpenSettingsActionKey.Action(openSettingsAction))
            .environment(\.panelRole, .pinned)
            .environment(\.dismissPinnedPanel, DismissPinnedPanelAction { [weak self] in
                self?.hide()
            })
            .modifier(PinnedPanelSizeReader { [weak self] size in
                self?.contentSizeDidChange(to: size)
            })

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.panelCornerRadius
        hosting.layer?.masksToBounds = true
        visualEffect.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        hostingView = hosting

        // 用内容固有尺寸初始化窗口大小。
        hosting.layoutSubtreeIfNeeded()
        let intrinsic = hosting.intrinsicContentSize
        if intrinsic.width > 1, intrinsic.height > 1 {
            panel.setContentSize(intrinsic)
        }
    }

    // MARK: - Show / Hide / Toggle

    /// 显示钉住面板:读取记忆位置,做越界回收,非激活方式呈现。
    func show() {
        guard !panel.isVisible else { return }

        hostingView?.layoutSubtreeIfNeeded()
        let intrinsic = hostingView?.intrinsicContentSize ?? .zero
        let size = (intrinsic.width > 1 && intrinsic.height > 1) ? intrinsic : panel.frame.size

        // 读取记忆位置,无历史值则用默认位置（主屏右上角）。
        if let savedOrigin = store.settings.pinnedPanelOrigin {
            panel.setFrame(CGRect(origin: savedOrigin, size: size), display: false)
        } else {
            panel.setContentSize(size)
            // 默认位置:主屏右上角,留出边距。
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let origin = CGPoint(
                    x: screenFrame.maxX - size.width - 20,
                    y: screenFrame.maxY - size.height - 20
                )
                panel.setFrameOrigin(origin)
            }
        }

        // 越界回收:若面板不与任何屏幕可见区域相交,回收到主屏。
        ensureOnScreen()

        // 非激活方式呈现,保持当前 App 前台。
        panel.orderFrontRegardless()

        store.panelDidAppear(.pinned)
    }

    /// 隐藏钉住面板。
    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        store.panelDidDisappear(.pinned)
    }

    /// 切换钉住面板显隐。
    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// 面板是否可见。
    var isVisible: Bool {
        panel.isVisible
    }

    // MARK: - Sizing / Positioning

    private func contentSizeDidChange(to size: CGSize) {
        guard panel.frame.size != size else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.frame.size != size else { return }
            // 保持当前位置,只更新尺寸。
            var frame = self.panel.frame
            frame.size = size
            self.panel.setFrame(frame, display: true)
        }
    }

    /// 确保面板在可见屏幕范围内。若不与任何屏幕相交,回收到主屏。
    private func ensureOnScreen() {
        let panelFrame = panel.frame
        var isOnScreen = false
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(panelFrame) {
                isOnScreen = true
                break
            }
        }
        guard !isOnScreen else { return }

        // 回收到主屏可见区域内。
        guard let mainScreen = NSScreen.main else { return }
        let visibleFrame = mainScreen.visibleFrame
        var newFrame = panelFrame

        // 夹取到可见区域内。
        if newFrame.maxX > visibleFrame.maxX {
            newFrame.origin.x = visibleFrame.maxX - newFrame.width
        }
        if newFrame.minX < visibleFrame.minX {
            newFrame.origin.x = visibleFrame.minX
        }
        if newFrame.maxY > visibleFrame.maxY {
            newFrame.origin.y = visibleFrame.maxY - newFrame.height
        }
        if newFrame.minY < visibleFrame.minY {
            newFrame.origin.y = visibleFrame.minY
        }

        panel.setFrame(newFrame, display: true)
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidMove(_ notification: Notification) {
        MainActor.assumeIsolated {
            // 拖动结束后将 origin 写入 MonitorSettings。
            store.settings.savePinnedPanelOrigin(panel.frame.origin)
        }
    }

    // 失焦不关闭,与 FluidPanelController 相反。
    nonisolated func windowDidResignKey(_ notification: Notification) {
        // 不做任何操作。
    }
}

// MARK: - Size Reader

/// 与 FluidPanelSizeReader 相同的尺寸读取器,用于钉住面板。
private struct PinnedPanelSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            .edgesIgnoringSafeArea(.all)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { onChange(geometry.size) }
                        .onChange(of: geometry.size) { _, newValue in
                            onChange(newValue)
                        }
                }
            )
            .fixedSize()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}
