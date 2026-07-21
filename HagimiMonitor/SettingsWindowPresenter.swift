import AppKit
import SwiftUI
import OSLog

enum SettingsWindowPresenter {
    static let selectedTabDefaultsKey = "settings.selectedTab"
    static let routeChangeNotification = Notification.Name("SettingsWindowPresenter.routeChange")
    static let tabUserInfoKey = "tab"

    @MainActor
    private static weak var settingsWindow: NSWindow?
    @MainActor
    private static var pendingFocus = false
    @MainActor
    private static var pendingTab: SettingsTab?
    @MainActor
    private static var cachedOpenSettings: OpenSettingsAction?
    /// 标记窗口是否已完成一次性外观配置(标题栏、尺寸、居中)。
    /// 避免每次 `register` 重复修改 styleMask 或重新居中已经被用户移动过的窗口。
    @MainActor
    private static var hasConfiguredWindow = false

    /// 由 `AppMenuCommands` 在每次刷新菜单时写入,供非 View 上下文(如面板按钮)复用。
    @MainActor
    static func cache(_ openSettings: OpenSettingsAction) {
        cachedOpenSettings = openSettings
    }

    /// 供面板等无法访问 `@Environment(\.openSettings)` 的调用方使用。
    @MainActor
    static func openFromOutsideSwiftUI(tab: SettingsTab? = nil) {
        guard let cachedOpenSettings else {
            AppLogger.settings.error("openSettings action not cached yet")
            return
        }
        open(cachedOpenSettings, tab: tab)
    }

    @MainActor
    static func open(_ openSettings: OpenSettingsAction, tab: SettingsTab? = nil) {
        AppLogger.settings.info("Opening settings window")
        // 更新检查已由 Sparkle 在启动时接管后台定时检查(仅直接分发版),
        // 无需在开窗时再手动触发。App Store 版更新交由商店管理。

        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: selectedTabDefaultsKey)
            pendingTab = tab
        }

        if let window = settingsWindow {
            focus(window)
            broadcastPendingTab()
            return
        }

        pendingFocus = true
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    @MainActor
    static func register(_ window: NSWindow) {
        AppLogger.settings.info("Registering settings window")
        settingsWindow = window

        // 一次性外观配置：只在首次注册时执行,避免重复修改 styleMask 造成的
        // 标题栏/内容重排闪烁,也避免重新居中用户已手动移动过的窗口。
        // 关键:该方法由 `viewDidMoveToWindow` 同步调用(窗口尚未真正显示前),
        // 这样样式与位置都在窗口可见之前就绪,消除首次打开时的闪烁与位置跳变。
        if !hasConfiguredWindow {
            hasConfiguredWindow = true
            window.title = ""
            // 标题栏与下方内容合并为一体：标题栏透明 + 内容延伸到标题栏区域，
            // 让侧栏的 `.bar` 材质一路延伸到红绿灯按钮下方，避免标题栏和内容区
            // 在视觉上像两块拼接起来的独立区域。
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            normalize(window)
            centerOnActiveScreen(window)
        }

        if pendingFocus {
            pendingFocus = false
            focus(window)
        }

        broadcastPendingTab()
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
        AppLogger.settings.debug("Focusing settings window")
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @MainActor
    private static func normalize(_ window: NSWindow) {
        let targetSize = NSSize(width: 600, height: 406)
        window.minSize = NSSize(width: 560, height: 384)

        guard window.frame.width > 740 || window.frame.height > 520 else {
            return
        }

        var frame = window.frame
        frame.origin.x += (frame.width - targetSize.width) / 2
        frame.origin.y += (frame.height - targetSize.height) / 2
        frame.size = targetSize
        window.setFrame(frame, display: false)
    }

    /// 将窗口居中到用户当前所在的屏幕(以鼠标位置判定),而非固定主屏,
    /// 以适配多显示器场景——面板按钮通常在鼠标所在的那块屏幕上被点击。
    /// 采用略微偏上的位置(约屏幕可见区上 60% 处),与 macOS 系统窗口居中习惯一致。
    @MainActor
    private static func centerOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? window.screen
            ?? NSScreen.main

        guard let screen else {
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
