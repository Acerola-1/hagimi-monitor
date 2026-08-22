import SwiftUI

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@main
struct HagimiMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.colorScheme) private var colorScheme

    /// MonitorStore 由 AppDelegate 创建并持有。
    /// App 通过 appDelegate 引用访问。
    private var monitorStore: MonitorStore {
        appDelegate.store
    }

    init() {
        CrashHandler.install()
        let previousUnexpected = AppLaunchStateTracker.shared.markLaunch()
        AppLogStore.shared.info("App launched", category: "app")
        if previousUnexpected {
            AppLogStore.shared.warning("Previous run may have ended unexpectedly", category: "app")
        }
        HealthMonitor.shared.start()
        UsageReporter.shared.reportIfNeeded(trigger: .launch)
        UsageReporter.shared.start()
    }

    var body: some Scene {
        Settings {
            SettingsRootView(settings: monitorStore.settings, store: monitorStore)
        }
        .windowResizability(.contentSize)
        .commands { AppMenuCommands() }
    }

    private var effectiveColorScheme: ColorScheme? {
        monitorStore.settings.themePreference.colorScheme
    }
}

// MARK: - Menu Commands

struct AppMenuCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        let _ = SettingsWindowPresenter.cache(openSettings)

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

        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "menu.settings")) {
                SettingsWindowPresenter.open(openSettings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(String(localized: "menu.open-report")) {
                if let delegate = NSApp.delegate as? AppDelegate {
                    StatisticsReportFlow.open(recorder: delegate.store.statisticsRecorder)
                }
            }
        }
    }
}
