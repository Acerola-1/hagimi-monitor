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

    @Test func metricSelectionAllowsMoreThanFourItems() {
        let defaults = UserDefaults(suiteName: "metricSelectionAllowsMoreThanFourItems")!
        defaults.removePersistentDomain(forName: "metricSelectionAllowsMoreThanFourItems")
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
        #expect(settings.isMetricEnabled("temperature", for: .cpu))
        #expect(settings.canEnableMetric("temperature", for: .cpu))
    }

    @Test func defaultMenuBarDisplaySettings() {
        let defaults = UserDefaults(suiteName: "defaultMenuBarDisplaySettings")!
        defaults.removePersistentDomain(forName: "defaultMenuBarDisplaySettings")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.menuBarDisplayMode == .ring)
        #expect(settings.menuBarMetricKinds == [.cpuUsage])
        #expect(settings.ringSource == .combined)
    }

    @Test func menuBarMetricSelectionLimit() {
        let defaults = UserDefaults(suiteName: "menuBarMetricSelectionLimit")!
        defaults.removePersistentDomain(forName: "menuBarMetricSelectionLimit")
        let settings = MonitorSettings(defaults: defaults)

        settings.setMenuBarMetric(.gpuUsage, selected: true)
        settings.setMenuBarMetric(.memoryUsage, selected: true)
        settings.setMenuBarMetric(.batteryLevel, selected: true)
        settings.setMenuBarMetric(.networkDownload, selected: true)

        #expect(settings.menuBarMetricKinds == [.cpuUsage, .gpuUsage, .memoryUsage, .batteryLevel])
        #expect(!settings.canSelectMenuBarMetric(.networkDownload))
    }

    @Test func menuBarMetricSelectionCannotBecomeEmpty() {
        let defaults = UserDefaults(suiteName: "menuBarMetricSelectionCannotBecomeEmpty")!
        defaults.removePersistentDomain(forName: "menuBarMetricSelectionCannotBecomeEmpty")
        let settings = MonitorSettings(defaults: defaults)

        settings.setMenuBarMetric(.cpuUsage, selected: false)

        #expect(settings.menuBarMetricKinds == [.cpuUsage])
    }

    @Test func menuBarMetricOrderCanMove() {
        let defaults = UserDefaults(suiteName: "menuBarMetricOrderCanMove")!
        defaults.removePersistentDomain(forName: "menuBarMetricOrderCanMove")
        let settings = MonitorSettings(defaults: defaults)

        settings.setMenuBarMetric(.gpuUsage, selected: true)
        settings.moveMenuBarMetric(.gpuUsage, direction: -1)

        #expect(settings.menuBarMetricKinds == [.gpuUsage, .cpuUsage])
    }

    @Test func menuBarDisplaySettingsPersist() async throws {
        let defaults = UserDefaults(suiteName: "menuBarDisplaySettingsPersist")!
        defaults.removePersistentDomain(forName: "menuBarDisplaySettingsPersist")

        let settings = MonitorSettings(defaults: defaults)
        settings.menuBarDisplayMode = .metrics
        settings.setMenuBarMetric(.gpuUsage, selected: true)
        settings.moveMenuBarMetric(.gpuUsage, direction: -1)
        try await Task.sleep(for: .milliseconds(50))

        let restored = MonitorSettings(defaults: defaults)

        #expect(restored.menuBarDisplayMode == .metrics)
        #expect(restored.menuBarMetricKinds == [.gpuUsage, .cpuUsage])
    }

    @Test func legacyRingSourceMigratesToCombined() {
        let defaults = UserDefaults(suiteName: "legacyRingSourceMigratesToCombined")!
        defaults.removePersistentDomain(forName: "legacyRingSourceMigratesToCombined")
        defaults.set("memory", forKey: "settings.ringSource")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.ringSource == .combined)
    }

    @Test func compactMenuBarMetricFormatting() {
        #expect(MenuBarMetricFormatter.percentage(42.4) == "42%")
        #expect(MenuBarMetricFormatter.percentage(nil) == "--")
        #expect(MenuBarMetricFormatter.fixedPercentage(42.4) == " 42%")
        #expect(MenuBarMetricFormatter.temperature(88.4) == " 88°")
        #expect(MenuBarMetricFormatter.throughput(2_516_582, direction: "↓") == "↓2.4M")
        #expect(MenuBarMetricFormatter.capacity(137_438_953_472) == "128G")
    }
}
