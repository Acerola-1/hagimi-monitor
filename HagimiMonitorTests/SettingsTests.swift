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

        settings.setMetric("cpu.system", enabled: true, for: .cpu)
        settings.setMetric("cpu.user", enabled: true, for: .cpu)
        settings.setMetric("cpu.idle", enabled: true, for: .cpu)
        settings.setMetric("cpu.extra", enabled: true, for: .cpu)

        #expect(settings.isMetricEnabled("cpu.overall", for: .cpu))
        #expect(settings.isMetricEnabled("cpu.system", for: .cpu))
        #expect(settings.isMetricEnabled("cpu.user", for: .cpu))
        #expect(settings.isMetricEnabled("cpu.idle", for: .cpu))
        #expect(!settings.isMetricEnabled("cpu.extra", for: .cpu))
        #expect(!settings.canEnableMetric("cpu.extra", for: .cpu))
    }
}
