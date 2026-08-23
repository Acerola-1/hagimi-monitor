import SwiftUI

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

@main
struct HagimiMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        // 场景占位:设置窗口由 SettingsWindowPresenter 自建 NSWindow 承载
        // (SwiftUI 的 Settings 场景会重置窗口约束,无法钉死宽度只放开高度)。
        // 菜单命令已被替换为直连 presenter,此场景不会被打开。
        Settings { EmptyView() }
            .commands { AppMenuCommands() }
    }
}

// MARK: - Menu Commands

struct AppMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "menu.about")) {
                SettingsWindowPresenter.open(tab: .about)
            }

            Divider()

            Button(String(localized: "menu.quit")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "menu.settings")) {
                SettingsWindowPresenter.open()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(String(localized: "menu.open-report")) {
                if let delegate = AppDelegate.shared {
                    StatisticsReportFlow.open(recorder: delegate.store.statisticsRecorder)
                }
            }
        }
    }
}
