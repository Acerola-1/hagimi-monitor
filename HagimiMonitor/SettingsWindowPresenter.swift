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
        Task { await UpdateChecker.shared.checkForUpdatesIfStale() }

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
        window.title = ""
        // 标题栏与下方内容合并为一体：标题栏透明 + 内容延伸到标题栏区域，
        // 让侧栏的 `.bar` 材质一路延伸到红绿灯按钮下方，避免标题栏和内容区
        // 在视觉上像两块拼接起来的独立区域。
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        normalize(window)

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
        let targetSize = NSSize(width: 600, height: 382)
        window.minSize = NSSize(width: 560, height: 360)

        guard window.frame.width > 740 || window.frame.height > 520 else {
            return
        }

        var frame = window.frame
        frame.origin.x += (frame.width - targetSize.width) / 2
        frame.origin.y += (frame.height - targetSize.height) / 2
        frame.size = targetSize
        window.setFrame(frame, display: true)
    }
}
