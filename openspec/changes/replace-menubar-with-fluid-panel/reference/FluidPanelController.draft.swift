import AppKit
import Combine
import SwiftUI

/// 自建的菜单栏面板控制器,替换系统 `MenuBarExtra(.window)`。
///
/// 背景:SwiftUI 的 `MenuBarExtra(.window)` 在 macOS 15 及更早版本对宿主窗口的
/// resize 实现很差——内容高度变化时系统会整窗重绘,导致展开子项时面板连同顶部
/// SYSTEM·LIVE 一起闪烁、像被重新加载;Apple 直到 macOS 26 才改进。为在 15 上
/// 同时拿到「不闪」和「平滑展开动画」,这里借鉴 FluidMenuBarExtra 的思路,自建
/// `NSPanel` 承载面板内容,由 AppKit 的 `setFrame(display:animate:)` 驱动高度动画:
/// 窗口原生动画 resize 不会 rebuild SwiftUI 视图树,因此不闪;顶边锚定在菜单栏
/// 下沿,只向下增长。
///
/// 动画分工(关键):内容尺寸由 SwiftUI 瞬时上报(不加 `withAnimation`),平滑
/// 的高度补间完全交给窗口层的 `animate: true`。这正好避开上一轮「SwiftUI 几何
/// 动画 + 窗口 resize 抢锚点」导致的顶部抖动。
///
/// 动态图标:`NSStatusItem.button` 内嵌 `NSHostingView(MenuBarStatusLabel)`,
/// 因此负载环 / 可变宽指标文本等动态内容都能正常显示——这是无法直接使用
/// FluidMenuBarExtra(仅支持静态图标)的原因。
@MainActor
final class FluidPanelController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    private let openSettings: OpenSettingsAction

    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var hostingView: NSHostingView<AnyView>?
    private var labelHostingView: NSHostingView<AnyView>?

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// 面板与菜单栏按钮左边缘对齐时,补偿窗口阴影/边框带来的 2pt 偏移。
    private static let windowBorderSize: CGFloat = 2

    init(store: MonitorStore, openSettings: OpenSettingsAction) {
        self.store = store
        self.openSettings = openSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: MonitorConstants.panelIdealWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureStatusItem()
        installEventMonitors()
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let root = MonitorPanelView(store: store)
            .environment(\.openSettings, openSettings)
            .modifier(FluidPanelSizeReader { [weak self] size in
                self?.contentSizeDidChange(to: size)
            })

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hosting
        hostingView = hosting
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let label = MenuBarStatusLabel(store: store, darkMode: NSApp.effectiveAppearance.isDark)
        let hosting = NSHostingView(rootView: AnyView(label))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        labelHostingView = hosting

        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        button.setAccessibilityTitle("HagimiMonitor")

        // dark mode 变化时刷新图标外观(SwiftUI 内部不感知 NSStatusItem 的 appearance)。
        store.settings.$themePreference
            .sink { [weak self] _ in self?.refreshLabelAppearance() }
            .store(in: &cancellables)
    }

    private func installEventMonitors() {
        // 左键点击状态项:切换面板显隐。拦截事件避免系统默认高亮行为与我们冲突。
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let button = self.statusItem.button,
                  event.window == button.window else {
                return event
            }
            self.togglePanel()
            return nil
        }

        // 面板打开时点击外部区域:关闭面板。
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.dismissPanel()
        }
    }

    // MARK: - Show / Hide

    private func togglePanel() {
        if panel.isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // 先让 SwiftUI 布局出内容固有尺寸,再据此定位窗口,避免首帧尺寸跳变。
        hostingView?.layoutSubtreeIfNeeded()
        let size = hostingView?.fittingSize ?? panel.frame.size
        setPanelFrame(size: size, animate: false)

        store.panelDidAppear()
        statusItem.button?.highlight(true)

        // 通知系统在全屏模式下保持菜单栏可见。
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissPanel() {
        guard panel.isVisible else { return }

        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.statusItem.button?.highlight(false)
            self.store.panelDidDisappear()
        }
    }

    // MARK: - Sizing / Positioning

    /// SwiftUI 内容尺寸变化时:平滑动画调整窗口高度,顶边保持锚定。
    /// 高度动画由窗口层 `animate: true` 提供,SwiftUI 侧不做几何动画,避免抖动。
    private func contentSizeDidChange(to size: CGSize) {
        guard panel.isVisible, panel.frame.size != size else { return }
        setPanelFrame(size: size, animate: true)
    }

    private func setPanelFrame(size: CGSize, animate: Bool) {
        guard let buttonWindow = statusItem.button?.window else {
            panel.setContentSize(size)
            panel.center()
            return
        }

        let buttonFrame = buttonWindow.frame
        var origin = buttonFrame.origin

        // macOS 坐标原点在左下:origin.y 减去窗口高度,使顶边钉在菜单栏下沿,
        // 面板只向下生长。左边缘与按钮对齐,补偿窗口边框。
        origin.y -= size.height
        origin.x -= Self.windowBorderSize

        var newFrame = CGRect(origin: origin, size: size)

        // 越过屏幕右缘时向左回收。
        if let screen = buttonWindow.screen {
            if newFrame.maxX > screen.visibleFrame.maxX {
                newFrame.origin.x = screen.visibleFrame.maxX - size.width - Self.windowBorderSize
            }
            if newFrame.minX < screen.visibleFrame.minX {
                newFrame.origin.x = screen.visibleFrame.minX + Self.windowBorderSize
            }
        }

        guard newFrame != panel.frame else { return }
        panel.setFrame(newFrame, display: true, animate: animate)
    }

    private func refreshLabelAppearance() {
        let label = MenuBarStatusLabel(store: store, darkMode: NSApp.effectiveAppearance.isDark)
        labelHostingView?.rootView = AnyView(label)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        dismissPanel()
    }
}

/// 读取 SwiftUI 内容固有尺寸并回调。内容瞬时上报尺寸,高度动画交给窗口层。
private struct FluidPanelSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            .fixedSize()
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { onChange(geometry.size) }
                        .onChange(of: geometry.size) { newValue in
                            onChange(newValue)
                        }
                }
            )
    }
}

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}
