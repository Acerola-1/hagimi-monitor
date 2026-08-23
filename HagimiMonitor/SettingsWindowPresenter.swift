import AppKit
import SwiftUI
import OSLog

/// 设置窗口的持有者与打开入口。
///
/// 设置界面不走 SwiftUI 的 `Settings` 场景:该场景在窗口装配阶段会重置
/// styleMask 与 minSize/maxSize(实测插入的 `.resizable` 会被移除),无法实现
/// "宽度钉死、仅高度可拉伸"。这里自建 NSWindow,SwiftUI 内容经普通 AppKit
/// 容器承载(避免宿主反向改写窗口约束),宽度 min==max 钉死、高度上不封顶,
/// 用户拖拽的最小高度由拉伸代理裁定。
enum SettingsWindowPresenter {
    static let routeChangeNotification = Notification.Name("SettingsWindowPresenter.routeChange")
    static let tabUserInfoKey = "tab"

    /// 窗口强持有:关闭仅 orderOut,实例常驻,重开复用同一窗口与其中的 SwiftUI 状态。
    @MainActor
    private static var settingsWindow: NSWindow?
    @MainActor
    private static var pendingTab: SettingsTab?

    /// 拉伸代理需强持有:NSWindow.delegate 是弱引用,计算属性每次生成新实例会立刻
    /// 释放,代理方法将不再触发。
    @MainActor
    private static let resizeDelegate = SettingsResizeDelegate(
        fixedWidth: fixedWidth,
        minHeight: minHeight()
    )

    /// 打开设置窗口。菜单命令、面板按钮、深链 tab 等所有入口统一走这里。
    @MainActor
    static func open(tab: SettingsTab? = nil) {
        if let tab {
            pendingTab = tab
        }

        guard let window = ensureWindow() else {
            AppLogger.settings.error("Settings window unavailable: MonitorStore missing")
            return
        }

        focus(window)
        broadcastPendingTab()
    }

    /// 由 SettingsRootView 内的跟踪视图在挂载后调用:目标页路由观察者此时才就绪,
    /// 补发尚未消费的路由。
    @MainActor
    static func settingsViewDidAppear() {
        broadcastPendingTab()
    }

    @MainActor
    private static func ensureWindow() -> NSWindow? {
        if let settingsWindow {
            return settingsWindow
        }

        guard let store = AppDelegate.shared?.store else {
            return nil
        }

        let window = makeWindow(store: store)
        settingsWindow = window
        return window
    }

    /// 固定窗口宽度。设置布局不需要更宽,且在所有受支持机型的屏幕上都放得下。
    private static let fixedWidth: CGFloat = 600

    /// 窗口最小高度:恰好完整展示全部侧栏条目,底边留白约一个行高。
    /// 实测基准:侧栏行高 31.5,无风扇形态(11 行)末行底边 420;
    /// 有风扇形态多一行风扇入口,底边相应下移一个行高。
    /// 侧栏行数在启动后即确定——唯一变量是机型有无风扇(风扇入口按 `fanAvailable`
    /// 显隐),因此高度按两个形态各定一个实测值。默认高度等于最小高度,
    /// 用户可向上拉长、不可短于该值(保证侧栏永不裁切)。
    /// App Store 沙盒版无法读 SMC,`fanAvailable` 恒为 false,恒取无风扇值。
    private static let minHeightWithFan: CGFloat = 483
    private static let minHeightWithoutFan: CGFloat = 452

    @MainActor
    private static func minHeight() -> CGFloat {
        let hasFan = AppDelegate.shared?.store.fanAvailable ?? false
        return hasFan ? minHeightWithFan : minHeightWithoutFan
    }

    @MainActor
    private static func makeWindow(store: MonitorStore) -> NSWindow {
        let minH = minHeight()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: fixedWidth, height: minH),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 标题栏消失术:透明标题栏 + 空 unified 工具栏 + 无分隔线,系统不再绘制
        // 标题栏底色,内容借 fullSizeContentView 覆盖整窗——右侧内容区直达窗口
        // 顶边,红绿灯悬浮在侧栏材质上,左右两区在视觉上完全分离。
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = resizeDelegate

        // SwiftUI 宿主以子控制器形式嵌入普通 AppKit 容器:直接作为
        // contentViewController 挂载时,SwiftUI 会在窗口每次展示时接管并改写窗口
        // min/max(sizingOptions 置空也拦不住)。隔一层普通 NSViewController 后,
        // 窗口约束不再受宿主干涉,与 AltTab 纯 AppKit 容器的窗口结构一致。
        let hostingController = NSHostingController(
            rootView: SettingsRootView(settings: store.settings, store: store)
        )
        hostingController.sizingOptions = []
        let containerController = NSViewController()
        let containerView = NSView()
        containerController.view = containerView
        containerController.addChild(hostingController)
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)
        window.contentViewController = containerController

        // 宽度 min==max 钉死:左右边缘拖不动,只有上下出现拉伸光标;高度上不封顶。
        // 高度下限不放进 minSize——此窗口形态(全尺寸内容视图)下系统对 minSize 的
        // 高度分量做标题栏换算(写入 418 读回 452),精确下限由拉伸代理的
        // windowWillResize 裁定。
        window.minSize = NSSize(width: fixedWidth, height: 1)
        window.maxSize = NSSize(width: fixedWidth, height: .greatestFiniteMagnitude)

        // 帧持久化:记住用户拉伸后的高度与位置,跨启动恢复。
        if setFrameAutosaveNameSafely(window, name: "SettingsWindow") {
            normalizeRestoredFrame(window)
        } else {
            // 首次开窗:默认高度(=最小高度)居中到鼠标所在屏。
            centerOnActiveScreen(window)
        }

        return window
    }

    /// `setFrameAutosaveName` 会立即应用 "NSWindow Frame <name>" 下的持久化帧,
    /// 值损坏时该应用会抛异常导致崩溃;先校验并丢弃坏值再交给系统。
    @discardableResult
    private static func setFrameAutosaveNameSafely(_ window: NSWindow, name: String) -> Bool {
        let key = "NSWindow Frame \(name)"
        let saved = UserDefaults.standard.string(forKey: key)
        let valid = saved.map(isValidPersistedFrame) ?? false
        if saved != nil && !valid {
            AppLogger.settings.warning("Dropping corrupt persisted settings window frame")
            UserDefaults.standard.removeObject(forKey: key)
        }
        window.setFrameAutosaveName(NSWindow.FrameAutosaveName(name))
        return valid
    }

    /// 持久化帧格式:"x y width height …",至少 4 个有限数值且在 Int32 范围内。
    private static func isValidPersistedFrame(_ string: String) -> Bool {
        let n = string.split(separator: " ").compactMap { Double($0) }
        guard n.count >= 4 else { return false }
        let lo = Double(Int32.min), hi = Double(Int32.max)
        guard n.allSatisfy({ $0.isFinite && $0 >= lo && $0 <= hi }) else { return false }
        let x = n[0], y = n[1], w = n[2], h = n[3]
        return w >= 0 && h >= 0 && (x + w) <= hi && (y + h) <= hi
    }

    /// 持久化帧兜底:程序化 setFrame 不受 min/max 约束,历史帧可能带出异常宽度
    /// 或低于当前最小高度的高度(如换机型后风扇行数变化),拉回约束内。
    @MainActor
    private static func normalizeRestoredFrame(_ window: NSWindow) {
        var frame = window.frame
        var changed = false

        if abs(frame.size.width - fixedWidth) > 1 {
            frame.size.width = fixedWidth
            changed = true
        }

        let minH = minHeight()
        if frame.size.height < minH {
            frame.size.height = minH
            changed = true
        }

        if changed {
            window.setFrame(frame, display: false)
        }
    }

    @MainActor
    private static func broadcastPendingTab() {
        guard let tab = pendingTab else { return }
        pendingTab = nil
        NotificationCenter.default.post(
            name: routeChangeNotification,
            object: nil,
            userInfo: [tabUserInfoKey: tab.rawValue]
        )
    }

    @MainActor
    private static func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// 鼠标所在屏(多显示器场景下即触发打开的那块屏),与居中逻辑共用同一判定。
    @MainActor
    private static func activeScreen(for window: NSWindow) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? window.screen
            ?? NSScreen.main
    }

    /// 将窗口居中到用户当前所在的屏幕,而非固定主屏,
    /// 以适配多显示器场景——面板按钮通常在鼠标所在的那块屏幕上被点击。
    /// 采用略微偏上的位置(约屏幕可见区上 60% 处),与 macOS 系统窗口居中习惯一致。
    @MainActor
    private static func centerOnActiveScreen(_ window: NSWindow) {
        guard let screen = activeScreen(for: window) else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.minX + (visible.width - size.width) / 2,
            y: visible.minY + (visible.height - size.height) * 0.6
        )
        window.setFrameOrigin(origin)
    }
}

/// 宽度锁死窗口的拉伸代理。用户拖拽的最终裁定走 `windowWillResize`:
/// 宽度一律回归固定值,高度不低于完整展示侧栏的下限;live resize 期间把 x 钉回
/// 起点,拖拽对角时 AppKit 按光标横向移动窗口的动作被抵消,窗口只竖向伸缩。
@MainActor
private final class SettingsResizeDelegate: NSObject, NSWindowDelegate {
    private let fixedWidth: CGFloat
    private let minHeight: CGFloat
    private var liveResizeOriginX: CGFloat?

    init(fixedWidth: CGFloat, minHeight: CGFloat) {
        self.fixedWidth = fixedWidth
        self.minHeight = minHeight
        super.init()
    }

    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        NSSize(width: fixedWidth, height: max(size.height, minHeight))
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            liveResizeOriginX = window.frame.origin.x
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.inLiveResize,
              let liveResizeOriginX else { return }
        guard abs(window.frame.origin.x - liveResizeOriginX) > 0 else { return }
        window.setFrameOrigin(NSPoint(x: liveResizeOriginX, y: window.frame.origin.y))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeOriginX = nil
    }
}
