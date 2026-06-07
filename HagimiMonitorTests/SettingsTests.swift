//
//  SettingsTests.swift
//  HagimiMonitorTests
//

import Foundation
import Testing
@testable import HagimiMonitor

struct SettingsTests {
    @Test func defaultThemePreference() {
        let settings = MonitorSettings()
        #expect(settings.themePreference == .system)
    }

    @Test func displayModuleIsHiddenByDefault() {
        let defaults = UserDefaults(suiteName: "displayModuleIsHiddenByDefault")!
        defaults.removePersistentDomain(forName: "displayModuleIsHiddenByDefault")

        let settings = MonitorSettings(defaults: defaults)

        #expect(!settings.displayModuleVisible)
    }

    @Test func visibilityToggle() {
        let settings = MonitorSettings()
        settings.setVisible(false, for: .cpu)
        #expect(!settings.isVisible(.cpu))
        settings.setVisible(true, for: .cpu)
        #expect(settings.isVisible(.cpu))
    }
}
