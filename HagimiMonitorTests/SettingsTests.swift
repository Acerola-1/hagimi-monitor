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

    @Test func metricSelectionCapsAtFourItems() {
        let defaults = UserDefaults(suiteName: "metricSelectionCapsAtFourItems")!
        defaults.removePersistentDomain(forName: "metricSelectionCapsAtFourItems")
        let settings = MonitorSettings(defaults: defaults)

        settings.setMetric("system", enabled: true, for: .cpu)
        settings.setMetric("user", enabled: true, for: .cpu)
        settings.setMetric("idle", enabled: true, for: .cpu)
        settings.setMetric("uptime", enabled: true, for: .cpu)
        settings.setMetric("temperature", enabled: true, for: .cpu)

        #expect(settings.isMetricEnabled("system", for: .cpu))
        #expect(settings.isMetricEnabled("user", for: .cpu))
        #expect(settings.isMetricEnabled("idle", for: .cpu))
        #expect(settings.isMetricEnabled("uptime", for: .cpu))
        #expect(!settings.isMetricEnabled("temperature", for: .cpu))
        #expect(!settings.canEnableMetric("temperature", for: .cpu))
    }
}
