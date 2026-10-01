import AppKit
import Combine
import SwiftUI

/// 自动管理 PinnedPanelController 外部资源生命周期的包装器。
/// 安全不变式：在 deinit 时自动在主线程注销 NSEvent 监视器并在面板仍可见时通知 store。
nonisolated private final class PinnedPanelCleanupBox: @unchecked Sendable {
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private weak var panel: NSPanel?
    private weak var store: MonitorStore?

    func setMonitors(local: Any?, global: Any?) {
        localEventMonitor = local
        globalEventMonitor = global
    }

    func setContext(panel: NSPanel, store: MonitorStore) {
        self.panel = panel
        self.store = store
    }

    deinit {
        let local = localEventMonitor
        let global = globalEventMonitor
        let p = panel
        let s = store

        let cleanup = { @MainActor in
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
            if let p, p.isVisible, let s {
                s.panelDidDisappear(.pinned)
            }
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                cleanup()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    cleanup()
                }
            }
        }
    }
}

/// 快捷键面板控制器。默认是失焦即收的临时面板，钉住后才变为常驻窗口。
@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    private weak var panelMotion: SingleHostMotionCoordinator?
    private var awaitingGeometry = false
    private let store: MonitorStore
    private let openSettingsAction: () -> Void

    private let panel: NSPanel
    private let presentation = QuickPanelPresentation()
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private let cleanupBox = PinnedPanelCleanupBox()

    /// 面板树观察侧门控:隐藏期冻结失效,呼出开闸补发一次(见 PanelRefreshGate)。
    private let panelRefreshGate: PanelRefreshGate


    /// 面板外框圆角:与 FluidPanelController 一致(panelCornerRadius)。
    private static let panelCornerRadius = CGFloat(MonitorConstants.panelCornerRadius)

    init(store: MonitorStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettingsAction = openSettings
        panelRefreshGate = PanelRefreshGate(store: store)

        panel = NativePanelWindow(
            contentRect: CGRect(x: 0, y: 0, width: MonitorConstants.panelIdealWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        cleanupBox.setContext(panel: panel, store: store)
        presentation.configure(
            togglePin: { [weak self] in self?.togglePin() },
            close: { [weak self] in self?.hide(resetPin: true) }
        )
        installEventMonitor()

    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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

        // 窗口底座宿主：由 CompatiblePanelGlassHost 提供跨版本兼容背景（Liquid Glass / popover 毛玻璃），
        // 内部行卡片严格保持 withinWindow 材质。
        let glassHost = CompatiblePanelGlassHost(cornerRadius: Self.panelCornerRadius)
        panel.contentView = glassHost

        let root = MonitorPanelView(store: store, refreshGate: panelRefreshGate, quickPanelPresentation: presentation)
            .environment(\.fluidOpenSettings, OpenSettingsActionKey.Action { [weak self] in
                self?.hide(resetPin: true)
                self?.openSettingsAction()
            })
            .environment(\.panelMotionAdapter, self)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.panelCornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = false
        glassHost.setHostingView(hosting)

        hostingView = hosting

        // 用内容固有尺寸初始化窗口大小。
        hosting.layoutSubtreeIfNeeded()
        let intrinsic = hosting.intrinsicContentSize
        if intrinsic.width > 1, intrinsic.height > 1 {
            panel.setContentSize(intrinsic)
        }

        updatePresentationMode()
    }

    private func installEventMonitor() {
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel else { return event }
            self.dismissIfTransient()
            return event
        }

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissIfTransient()
            }
        }
        cleanupBox.setMonitors(local: local, global: global)
    }

    private func updatePresentationMode() {
        let isPinned = presentation.isPinned
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = isPinned
        panel.level = isPinned ? .floating : .normal
    }

    private func togglePin() {
        presentation.togglePinState()
        // 先提交图钉的视觉状态，再在下一轮 RunLoop 切换窗口层级，避免 AppKit
        // 的层级调整拖慢按钮反馈。
        DispatchQueue.main.async { [weak self] in
            self?.updatePresentationMode()
        }
    }

    private func dismissIfTransient() {
        guard !presentation.isPinned else { return }
        hide(resetPin: false)
    }

    // MARK: - Show / Hide / Toggle

    /// 显示快捷键面板。每次呼出都从普通状态开始。
    func show() {
        guard !panel.isVisible else { return }
        // 开闸补发:隐藏期冻结的视图树先追平 store 当前值,
        // 随后的强制布局/测量才带最新数据。
        panelRefreshGate.open()
        panelMotion?.resume()
        // 隐藏时未收敛的窗口弹簧在此清场,本次呼出由重定位接管。
        presentation.resetPin()
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_BENCH"] != nil,
           NativePanelMotionMode.testHost == "pinned" { presentation.togglePinState() }
        updatePresentationMode()

        hostingView?.layoutSubtreeIfNeeded()
        if panelMotion?.currentFrame == nil {
            awaitingGeometry = true
            if !panel.isVisible {
                let screen = currentScreen() ?? NSScreen.main
                let size = CGSize(width: MonitorConstants.panelIdealWidth + MonitorConstants.panelNativeShadowInset * 2,
                    height: screen?.visibleFrame.height ?? 800)
                panel.setContentSize(size)
                if let screen {
                    panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - size.width / 2,
                        y: screen.visibleFrame.maxY - size.height))
                }
                panel.alphaValue = 0; panel.ignoresMouseEvents = true
                panel.orderFrontRegardless(); hostingView?.needsLayout = true
            }
            return
        }
        awaitingGeometry = false
        let intrinsic = hostingView?.intrinsicContentSize ?? .zero
        let size: CGSize

            size = CGSize(width: MonitorConstants.panelIdealWidth + MonitorConstants.panelNativeShadowInset * 2,
                height: (currentScreen() ?? NSScreen.main)?.visibleFrame.height ?? 800)


        // 读取记忆位置,无历史值则用默认位置（主屏右上角）。
        if let screen = NativePanelMotionMode.testScreen {
            panel.setFrame(CGRect(x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.maxY - size.height, width: size.width, height: size.height), display: false)
        } else if let savedOrigin = store.settings.pinnedPanelOrigin {
            var origin = savedOrigin

                let visibleHeight = panelMotion?.currentFrame?.windowContentSize.height ?? size.height
                origin.x -= MonitorConstants.panelNativeShadowInset
                origin.y += visibleHeight + MonitorConstants.panelNativeShadowInset - size.height

            panel.setFrame(CGRect(origin: origin, size: size), display: false)
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
        panel.alphaValue = 1
        panel.orderFrontRegardless()
panelMotion?.nativeLayer.panelDidShow()

        store.panelDidAppear(.pinned)
    }

    /// 隐藏快捷键面板；关闭后重置为普通状态。
    func hide(resetPin: Bool = true) {
        if awaitingGeometry {
            awaitingGeometry = false
            panelMotion?.suspend()
panel.orderOut(nil)
            panelRefreshGate.close()
            return
        }
        guard panel.isVisible else { return }
        panelMotion?.suspend()
panel.orderOut(nil)
        panelMotion?.resetForHiddenPanel?()
        store.panelDidDisappear(.pinned)
        if resetPin {
            presentation.resetPin()
            updatePresentationMode()
        }
        // 关门晚于上面的隐藏回调与图钉重置发布,保证它们送达视图
        // (isPanelVisible 变 false 驱动隐藏复位);此后冻结面板树。
        panelRefreshGate.close()
    }

    /// 切换快捷键面板显隐。
    func toggle() {
        if panel.isVisible || awaitingGeometry {
            hide(resetPin: true)
        } else {
            show()
        }
    }

    /// 面板是否可见。
    var isVisible: Bool {
        panel.isVisible
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
            var origin = panel.frame.origin

                origin.x += MonitorConstants.panelNativeShadowInset
                origin.y = panel.frame.maxY - MonitorConstants.panelNativeShadowInset
                    - (panelMotion?.nativeLayer.sample(at: CACurrentMediaTime())?.frame.windowContentSize.height ?? panel.frame.height)

            store.settings.savePinnedPanelOrigin(origin)
        }
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            dismissIfTransient()
        }
    }
}

@MainActor
final class QuickPanelPresentation: ObservableObject {
    @Published private(set) var isPinned = false

    private var togglePinAction: () -> Void = {}
    private var closeAction: () -> Void = {}

    func configure(togglePin: @escaping () -> Void, close: @escaping () -> Void) {
        togglePinAction = togglePin
        closeAction = close
    }

    func togglePin() {
        togglePinAction()
    }

    func togglePinState() {
        isPinned.toggle()
    }

    func resetPin() {
        isPinned = false
    }

    func close() {
        closeAction()
    }
}



extension PinnedPanelController: PanelWindowSubmissionAdapter {
    var isWindowUnoccluded: Bool { panel.isVisible && panel.occlusionState.contains(.visible) }
    func bindMotion(_ motion: SingleHostMotionCoordinator) {
        panelMotion = motion
        if motion.currentFrame != nil { geometryDidPrepare() }
    }
    func geometryDidPrepare() {
        guard awaitingGeometry else { return }
        awaitingGeometry = false
panel.orderOut(nil)
        show()
    }
    func submitWindowFrame(size: CGSize, frameID: UInt) {
        var frame = panel.frame
        let top = frame.maxY
        // fullSizeContentView 的宿主覆盖整个 frame，内容高度已包含标题栏区域。
        frame.size = size
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: false, animate: false)
    }
    func currentScreen() -> NSScreen? { NativePanelMotionMode.testScreen ?? panel.screen }
    func completePresentationLayout() { hostingView?.layoutSubtreeIfNeeded() }
}
