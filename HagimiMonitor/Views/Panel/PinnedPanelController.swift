import AppKit
import Combine
import SwiftUI

/// 快捷键面板控制器。默认是失焦即收的临时面板，钉住后才变为常驻窗口。
@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    private let openSettingsAction: () -> Void

    private let panel: NSPanel
    private let presentation = QuickPanelPresentation()
    private var hostingView: NSHostingView<AnyView>?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    /// 面板圆角半径,与 FluidPanelController 一致(rowCornerRadius)。
    private static let panelCornerRadius = CGFloat(MonitorConstants.rowCornerRadius)

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
        presentation.configure(
            togglePin: { [weak self] in self?.togglePin() },
            close: { [weak self] in self?.hide(resetPin: true) }
        )
        installEventMonitor()
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        // 若面板仍可见,通知 store 移除引用。
        if panel.isVisible {
            store.panelDidDisappear(.pinned)
        }
    }

    // MARK: - Setup

    private func configurePanel() {
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

        let root = MonitorPanelView(store: store, quickPanelPresentation: presentation)
            .environment(\.fluidOpenSettings, OpenSettingsActionKey.Action { [weak self] in
                self?.hide(resetPin: true)
                self?.openSettingsAction()
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

        updatePresentationMode()
    }

    private func installEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel else { return event }
            self.dismissIfTransient()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissIfTransient()
            }
        }
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
        presentation.resetPin()
        updatePresentationMode()

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

    /// 隐藏快捷键面板；关闭后重置为普通状态。
    func hide(resetPin: Bool = true) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        store.panelDidDisappear(.pinned)
        if resetPin {
            presentation.resetPin()
            updatePresentationMode()
        }
    }

    /// 切换快捷键面板显隐。
    func toggle() {
        if panel.isVisible {
            hide(resetPin: true)
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
            // 固定顶部，内容展开时只向下生长。
            var frame = self.panel.frame
            let top = frame.maxY
            frame.size = size
            frame.origin.y = top - size.height
            // 展开/收起（高度变化显著）且源自用户 toggle 时，用与内容 `CollapsibleDetail`
            // 完全一致的时长/easeInOut 曲线并行补间；数据到达/定时刷新引起的变化瞬时贴合。
            let userToggled = self.store.consumeExpansionAnimationFlag()
            if self.panel.isVisible, abs(self.panel.frame.height - size.height) > 8, userToggled {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = MonitorConstants.panelExpansionDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.panel.animator().setFrame(frame, display: true)
                }
            } else {
                // 数据驱动的即时贴合:用 0 时长动画组抢占并取消可能仍在进行的展开补间,
                // 否则进程列表(磁盘/网络行数随采样变动)展开后异步到达的高度变化会被在途补间
                // 覆盖回旧终值(表现为容器过高留白或过矮裁掉底部按钮),直到下个采样周期才纠正。
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    self.panel.animator().setFrame(frame, display: true)
                }
            }
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
            store.settings.savePinnedPanelOrigin(panel.frame.origin)
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
