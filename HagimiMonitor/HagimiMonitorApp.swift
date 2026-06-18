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

    var body: some Scene {
        MenuBarExtra {
            MonitorPanelView(store: monitorStore)
                .preferredColorScheme(effectiveColorScheme)
        } label: {
            Image(nsImage: MenuBarComputeRingIcon.image(
                load: monitorStore.displayedComputeLoad,
                darkMode: NSApp.effectiveAppearance.isDark,
                loadLevel: monitorStore.haloRingLoadLevel
            ))
            .resizable()
            .frame(width: 18, height: 18)
            .help("HagimiMonitor")
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
