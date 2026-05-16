import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresenter {
    private static weak var settingsWindow: NSWindow?

    static func open(_ openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        focusRegisteredWindow()
        focusRegisteredWindow(after: 0.1)
        focusRegisteredWindow(after: 0.35)
    }

    static func register(_ window: NSWindow) {
        settingsWindow = window
        window.title = "HagimiMonitor 设置"
        focus(window)
    }

    private static func focusRegisteredWindow() {
        guard let settingsWindow else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        focus(settingsWindow)
    }

    private static func focusRegisteredWindow(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                focusRegisteredWindow()
            }
        }
    }

    private static func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
