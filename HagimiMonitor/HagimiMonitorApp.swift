import SwiftUI

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@main
struct HagimiMonitorApp: App {
    @StateObject private var monitorStore = MonitorStore()
    @Environment(\.colorScheme) private var colorScheme

    init() {
        CrashHandler.install()
        let previousUnexpected = AppLaunchStateTracker.shared.markLaunch()
        AppLogStore.shared.info("App launched", category: "app")
        if previousUnexpected {
            AppLogStore.shared.warning("Previous run may have ended unexpectedly", category: "app")
        }
        HealthMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MonitorPanelView(store: monitorStore)
                .preferredColorScheme(effectiveColorScheme)
                .onAppear { monitorStore.panelDidAppear() }
                .onDisappear { monitorStore.panelDidDisappear() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    handleWillTerminate()
                }
        } label: {
            MenuBarStatusLabel(store: monitorStore, darkMode: NSApp.effectiveAppearance.isDark)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("HagimiMonitor Preview") {
            ContentView(store: monitorStore)
                .preferredColorScheme(effectiveColorScheme)
        }
        .windowResizability(.contentSize)
        .commands { AppMenuCommands() }

        Settings {
            SettingsRootView(settings: monitorStore.settings, store: monitorStore)
                // 设置窗口始终跟随系统外观
        }
        .windowResizability(.contentSize)
    }

    private var effectiveColorScheme: ColorScheme? {
        monitorStore.settings.themePreference.colorScheme
    }

    private func handleWillTerminate() {
        AppLogStore.shared.info("App will terminate", category: "app")
        monitorStore.flushStatistics()
        AppLaunchStateTracker.shared.markCleanExit()
        AppLogStore.shared.flush()
    }
}

// MARK: - Menu Commands

struct AppMenuCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "menu.about")) {
                SettingsWindowPresenter.open(openSettings, tab: .about)
            }

            Divider()

            Button(String(localized: "menu.quit")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
