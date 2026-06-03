import AppKit
import SwiftUI
import OSLog

@MainActor
enum SettingsWindowPresenter {
    private static weak var settingsWindow: NSWindow?
    private static var pendingFocus = false

    static func open(_ openSettings: OpenSettingsAction) {
        AppLogger.settings.info("Opening settings window")
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
        window.title = "HagimiMonitor 设置"

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
