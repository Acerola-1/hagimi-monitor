//
//  HagimiMonitorApp.swift
//  HagimiMonitor
//
//  Created by Acerola on 2026/5/11.
//

import SwiftUI

@main
struct HagimiMonitorApp: App {
    @StateObject private var monitorStore = MonitorStore()
    @Environment(\.colorScheme) private var colorScheme

    var body: some Scene {
        MenuBarExtra {
            MonitorPanelView(store: monitorStore)
                .preferredColorScheme(monitorStore.settings.themePreference.colorScheme)
        } label: {
            Image(nsImage: MenuBarCatIcon.image(for: monitorStore.catModule, frame: monitorStore.menuBarFrame, darkMode: effectiveColorScheme == .dark))
                .resizable()
                .frame(width: 28, height: 18)
                .help("HagimiMonitor")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("HagimiMonitor Preview") {
            ContentView(store: monitorStore)
                .preferredColorScheme(monitorStore.settings.themePreference.colorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(settings: monitorStore.settings)
                .preferredColorScheme(monitorStore.settings.themePreference.colorScheme)
        }
        .windowResizability(.contentSize)
    }

    private var effectiveColorScheme: ColorScheme {
        monitorStore.settings.themePreference.colorScheme ?? colorScheme
    }
}
