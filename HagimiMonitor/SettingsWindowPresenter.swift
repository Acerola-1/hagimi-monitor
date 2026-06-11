import AppKit
import SwiftUI
import OSLog

@MainActor
enum SettingsWindowPresenter {
    static let selectedTabDefaultsKey = "settings.selectedTab"

    private static weak var settingsWindow: NSWindow?
    private static var pendingFocus = false

    static func open(_ openSettings: OpenSettingsAction, tab: SettingsTab? = nil) {
        AppLogger.settings.info("Opening settings window")
        if let tab {
            UserDefaults.standard.set(tab.rawValue, forKey: selectedTabDefaultsKey)
        }

        if let window = settingsWindow {
            focus(window)
            return
        }

        pendingFocus = true
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    static func register(_ window: NSWindow) {
        AppLogger.settings.info("Registering settings window")
        settingsWindow = window
        window.title = ""

        if pendingFocus {
            pendingFocus = false
            focus(window)
        }
    }

    private static func focus(_ window: NSWindow) {
        AppLogger.settings.debug("Focusing settings window")
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
