import SwiftUI

nonisolated extension NSAppearance {
    /// 优先级把高对比度变体放在普通变体之前，确保系统开启「增强对比度」时命中高对比度分支；
    /// 未开启增强对比度时，AppKit 只会匹配普通变体。
    static let supportedAppearances: [NSAppearance.Name] = [
        .accessibilityHighContrastVibrantDark,
        .accessibilityHighContrastVibrantLight,
        .accessibilityHighContrastDarkAqua,
        .accessibilityHighContrastAqua,
        .vibrantDark,
        .vibrantLight,
        .darkAqua,
        .aqua
    ]

    var isDark: Bool {
        Self.isDark(appearanceName: bestMatch(from: Self.supportedAppearances))
    }

    var isHighContrast: Bool {
        Self.isHighContrast(appearanceName: bestMatch(from: Self.supportedAppearances))
    }

    static func isDark(appearanceName: NSAppearance.Name?) -> Bool {
        switch appearanceName {
        case .darkAqua,
             .vibrantDark,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }

    static func isHighContrast(appearanceName: NSAppearance.Name?) -> Bool {
        switch appearanceName {
        case .accessibilityHighContrastAqua,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantLight,
             .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
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
    @ObservedObject private var reportCommands = ReportWindowPresenter.commandState
    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button(String(localized: "menu.print-report")) { ReportWindowPresenter.printCurrentReport() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(!reportCommands.isAvailable)
            Button(String(localized: "menu.export-report")) { ReportWindowPresenter.exportCurrentReport() }
                .disabled(!reportCommands.isAvailable)
        }
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
