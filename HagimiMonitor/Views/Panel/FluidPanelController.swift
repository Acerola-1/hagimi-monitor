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
    /// 打开设置窗口的闭包。由外部注入,因为 `OpenSettingsAction` 只能在 SwiftUI 视图层获取。
    private let openSettingsAction: () -> Void

    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var hostingView: NSHostingView<AnyView>?
    private var labelHostingView: NSHostingView<AnyView>?

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// 面板与菜单栏按钮左边缘对齐时,补偿窗口阴影/边框带来的 2pt 偏移。
    private static let windowBorderSize: CGFloat = 2

    /// 面板圆角半径。由 window 层的 NSVisualEffectView / hosting layer 裁剪,
    /// 恢复系统 popover 般的圆角外观(自建 borderless 窗口默认是方角)。
    private static let panelCornerRadius: CGFloat = 12

    /// 状态项内容左右留白,避免图标/文字贴住菜单栏边缘(系统 MenuBarExtra 自带此留白)。
    private static let statusItemHorizontalPadding: CGFloat = 6

    init(store: MonitorStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettingsAction = openSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: MonitorConstants.panelIdealWidth, height: 200),
            // 对齐 FluidMenuBarExtra:保留 `.titled` 让 `setFrame(display:animate:)` 的
            // 高度动画可靠生效(borderless 窗口上 animate 常被忽略),再用
            // `.fullSizeContentView` + 隐藏标题栏做出无边框外观。
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
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

        // 隐藏标题栏,做出无边框外观(保留 `.titled` 的窗口行为)。
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // contentView 用 popover 毛玻璃:提供圆角遮罩 + 通透底(对齐 FluidMenuBarExtra)。
        // 这是恢复系统 popover 般外观的关键——实现者此前直接用透明 hosting 作 contentView,
        // 丢了圆角与毛玻璃底,面板才变成方盒子。
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.panelCornerRadius
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        // 面板内容:MonitorPanelView 通过自定义环境键获取 openSettings 闭包。
        let root = MonitorPanelView(store: store)
            .environment(\.fluidOpenSettings, OpenSettingsActionKey.Action(openSettingsAction))
            .modifier(FluidPanelSizeReader { [weak self] size in
                self?.contentSizeDidChange(to: size)
            })

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // hosting 也做圆角裁剪,否则 SwiftUI 内容(含 panelBackgroundColor 矩形)方角会溢出圆角。
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

        // 用内容固有尺寸初始化窗口大小(对齐 FluidMenuBarExtra)。避免首帧为默认 200 高。
        hosting.layoutSubtreeIfNeeded()
        let intrinsic = hosting.intrinsicContentSize
        if intrinsic.width > 1, intrinsic.height > 1 {
            panel.setContentSize(intrinsic)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let hosting = NSHostingView(rootView: makeStatusLabelRoot())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        labelHostingView = hosting

        // hosting 填满 button;button 宽度由 statusItem.length 控制,
        // 后者随内容固有宽度动态更新(见 updateStatusItemLength)。
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        button.setAccessibilityTitle("HagimiMonitor")

        // dark mode 变化时刷新图标外观(SwiftUI 内部不感知 NSStatusItem 的 appearance)。
        store.settings.$themePreference
            .sink { [weak self] _ in self?.refreshLabelAppearance() }
            .store(in: &cancellables)

        // 监听外观变化(系统浅/深色切换)
        NSApp.publisher(for: \.effectiveAppearance)
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
        // 用 intrinsicContentSize(NSHostingView 返回 SwiftUI 理想尺寸),不能用
        // fittingSize——hosting 被四边约束钉在 contentView 上,fittingSize 会解算成
        // 窗口现尺寸甚至 0,导致面板 0×0 看不见(这正是「有高亮但没面板」的根因)。
        hostingView?.layoutSubtreeIfNeeded()
        let intrinsic = hostingView?.intrinsicContentSize ?? .zero
        let size = (intrinsic.width > 1 && intrinsic.height > 1) ? intrinsic : panel.frame.size
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
    ///
    /// 关键:必须 `DispatchQueue.main.async` 异步派发(对齐 FluidMenuBarExtra)。
    /// 该回调发生在 SwiftUI 的布局事务内,若同步调用 `setFrame(animate:true)`,
    /// 窗口动画会被当前事务吞掉、退化为瞬间跳变——这正是「动画尽数丢失」的直接原因。
    /// 异步派发到下一个 runloop,让 SwiftUI 先完成布局,窗口再独立跑高度动画。
    private func contentSizeDidChange(to size: CGSize) {
        // 不能 guard panel.isVisible!对齐 FluidMenuBarExtra:size reader 的首次
        // onAppear 上报常发生在面板可见之前(init 布局阶段),若在此丢弃,窗口尺寸
        // 就永远停在默认值、之后 onChange 不再触发。始终更新尺寸,仅在可见时才动画。
        guard panel.frame.size != size else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.frame.size != size else { return }
            self.setPanelFrame(size: size, animate: self.panel.isVisible)
        }
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

        // 越过屏幕右缘时向左回收;越左缘时向右回收。
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

    /// 构造状态项 label 视图:内嵌尺寸读取器,内容宽度变化时更新 `statusItem.length`,
    /// 使 variableLength 状态项宽度精确跟随图标/文字固有宽度(否则 button 会塌成默认窄宽,
    /// 图标被挤)。水平留白模拟系统 MenuBarExtra 的边距。
    private func makeStatusLabelRoot() -> AnyView {
        let label = MenuBarStatusLabel(store: store, darkMode: NSApp.effectiveAppearance.isDark)
            .padding(.horizontal, Self.statusItemHorizontalPadding)
            .fixedSize()
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { [weak self] in self?.updateStatusItemLength(geometry.size.width) }
                        .onChange(of: geometry.size.width) { [weak self] _, newWidth in
                            self?.updateStatusItemLength(newWidth)
                        }
                }
            )
        return AnyView(label)
    }

    private func updateStatusItemLength(_ width: CGFloat) {
        let target = max(width.rounded(.up), 24)
        guard statusItem.length != target else { return }
        statusItem.length = target
    }

    private func refreshLabelAppearance() {
        labelHostingView?.rootView = makeStatusLabelRoot()
    }

    /// 打开设置窗口前关闭面板(供 AppDelegate 的 openSettings 闭包调用)。
    /// 不直接调用 openSettingsAction,因为关闭面板和打开设置需要由外部协调。
    func dismissPanelForSettings() {
        guard panel.isVisible else { return }
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)
        panel.orderOut(nil)
        panel.alphaValue = 1
        statusItem.button?.highlight(false)
        store.panelDidDisappear()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            dismissPanel()
        }
    }
}

// MARK: - Size Reader

/// 读取 SwiftUI 内容固有尺寸并回调。内容瞬时上报尺寸,高度动画交给窗口层。
///
/// modifier 顺序对齐 FluidMenuBarExtra 的 `RootViewModifier`,三者缺一不可:
/// 1. `.background(GeometryReader)` 放在 `.fixedSize()` **之前**——测的是内容自然
///    布局尺寸,不受后面 `.frame(maxHeight:.infinity)` 拉伸影响;
/// 2. `.fixedSize()` 固定内容为固有尺寸;
/// 3. `.frame(maxWidth/Height:.infinity, alignment: .top)` 让内容在被窗口拉伸的
///    hosting 里顶部对齐——窗口高度动画时内容从顶部展开,而非居中跳变。
///    实现者此前把 `.fixedSize()` 放在测量之前、且缺少顶对齐 frame,是动画观感丢失的原因之一。
private struct FluidPanelSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            // 关键:必须忽略安全区。窗口是 `.titled`,SwiftUI 默认把顶部标题栏区域
            // 当安全区留白——内容被下顶(顶部大空白),底部溢出窗口(按钮被裁掉)。
            // 对齐 FluidMenuBarExtra 的 RootViewModifier,填掉标题栏空间。
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

// MARK: - OpenSettings Environment Key

/// 自定义环境键,用于将 openSettings 闭包注入到 NSHostingView 承载的 SwiftUI 视图树中。
/// `OpenSettingsAction` 是 SwiftUI 内部类型,无法在 NSHostingView 构造时直接注入,
/// 因此用自定义环境键传递闭包,在 MonitorPanelView 中读取并调用。
enum OpenSettingsActionKey: EnvironmentKey {
    struct Action: Sendable {
        let action: @Sendable () -> Void

        init(_ action: @escaping @Sendable () -> Void) {
            self.action = action
        }

        func callAsFunction() {
            action()
        }
    }

    static let defaultValue: Action = Action({})
}

extension EnvironmentValues {
    var fluidOpenSettings: OpenSettingsActionKey.Action {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }
}

// MARK: - Notification Names

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}
