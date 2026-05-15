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
        } label: {
            Image(nsImage: MenuBarCatIcon.image(for: monitorStore.catModule, frame: monitorStore.menuBarFrame, darkMode: colorScheme == .dark))
                .resizable()
                .frame(width: 28, height: 18)
                .help("HagimiMonitor")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("HagimiMonitor Preview") {
            ContentView(store: monitorStore)
        }
        .windowResizability(.contentSize)
    }
}
