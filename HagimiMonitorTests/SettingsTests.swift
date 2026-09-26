import Foundation
import Testing
@testable import HagimiMonitorDirect

struct SettingsTests {
    @Test func batteryComponentPowerMetricsMigrateIntoNonEmptySelection() {
        let suite = "batteryComponentPowerMetricsMigrateIntoNonEmptySelection"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["health"], forKey: "settings.enabledMetrics.battery")
        defaults.set(true, forKey: "settings.batteryElectricalMetricsMigrated")

        let settings = MonitorSettings(defaults: defaults)

        for id in ["power", "display-power", "cpu-power", "gpu-power", "ane-power"] {
            #expect(settings.isMetricEnabled(id, for: .battery))
        }
        #expect(defaults.bool(forKey: "settings.batteryComponentPowerMetricsMigrated"))
        #expect(defaults.bool(forKey: "settings.batteryEnergyRailsMigrated"))
    }

    @Test func batteryComponentPowerMigrationPreservesExplicitAllOffSelection() {
        let suite = "batteryComponentPowerMigrationPreservesExplicitAllOffSelection"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set([String](), forKey: "settings.enabledMetrics.battery")

        let settings = MonitorSettings(defaults: defaults)

        #expect(!settings.isMetricEnabled("power", for: .battery))
        #expect(!settings.isMetricEnabled("display-power", for: .battery))
        #expect(!settings.isMetricEnabled("cpu-power", for: .battery))
        #expect(!settings.isMetricEnabled("ane-power", for: .battery))
    }

    @Test func defaultThemePreference() {
        // 用隔离域读取默认值:宿主 App 的真实偏好(用户选过的主题)不该左右默认值断言。
        let suite = "defaultThemePreference"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = MonitorSettings(defaults: defaults)
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
        #expect(settings.menuBarMetricKinds == MenuBarMetricKind.defaultSelection)
        #expect(settings.ringSource == .combined)
    }

    @Test func menuBarMetricSelectionHasNoMaximum() {
        let defaults = UserDefaults(suiteName: "menuBarMetricSelectionHasNoMaximum")!
        defaults.removePersistentDomain(forName: "menuBarMetricSelectionHasNoMaximum")
        let settings = MonitorSettings(defaults: defaults)

        for kind in MenuBarMetricKind.allCases {
            settings.setMenuBarMetric(kind, selected: true)
        }

        #expect(settings.menuBarMetricKinds.count == MenuBarMetricKind.allCases.count)
        #expect(settings.menuBarMetricKinds.count > 4)
    }

    @Test func menuBarMetricSelectionCannotBecomeEmpty() {
        let defaults = UserDefaults(suiteName: "menuBarMetricSelectionCannotBecomeEmpty")!
        defaults.removePersistentDomain(forName: "menuBarMetricSelectionCannotBecomeEmpty")
        defaults.set([MenuBarMetricKind.cpuUsage.rawValue], forKey: "settings.menuBar.metricKinds")
        let settings = MonitorSettings(defaults: defaults)

        settings.setMenuBarMetric(.cpuUsage, selected: false)

        #expect(settings.menuBarMetricKinds == [.cpuUsage])
    }

    @Test func menuBarMetricRestorePreservesMoreThanFourItems() {
        let defaults = UserDefaults(suiteName: "menuBarMetricRestorePreservesMoreThanFourItems")!
        defaults.removePersistentDomain(forName: "menuBarMetricRestorePreservesMoreThanFourItems")
        let stored = Array(MenuBarMetricKind.allCases.prefix(6))
        defaults.set(stored.map(\.rawValue), forKey: "settings.menuBar.metricKinds")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.menuBarMetricKinds == stored)
    }

    @Test func menuBarMetricOrderCanMove() {
        let defaults = UserDefaults(suiteName: "menuBarMetricOrderCanMove")!
        defaults.removePersistentDomain(forName: "menuBarMetricOrderCanMove")
        let settings = MonitorSettings(defaults: defaults)

        // gpuUsage 已在默认选择中(index 2),上移一位到 index 1。
        settings.moveMenuBarMetric(.gpuUsage, direction: -1)

        #expect(settings.menuBarMetricKinds == [.cpuUsage, .gpuUsage, .cpuTemperature, .systemPower])
    }

    @Test func menuBarMetricNativeReorderKeepsSelectionAndOrder() {
        let defaults = UserDefaults(suiteName: "menuBarMetricNativeReorderKeepsSelectionAndOrder")!
        defaults.removePersistentDomain(forName: "menuBarMetricNativeReorderKeepsSelectionAndOrder")
        let settings = MonitorSettings(defaults: defaults)
        let originalCount = settings.menuBarMetricKinds.count

        settings.reorderMenuBarMetrics([.systemPower], before: .cpuUsage)

        #expect(settings.menuBarMetricKinds.first == .systemPower)
        #expect(settings.menuBarMetricKinds.count == originalCount)
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
        #expect(restored.menuBarMetricKinds == [.cpuUsage, .gpuUsage, .cpuTemperature, .systemPower])
    }

    @Test func defaultExpandedKindsDefaultsToEmptyAndPersists() async throws {
        let suiteName = "defaultExpandedKindsDefaultsToEmptyAndPersists"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.defaultExpandedKinds.isEmpty)

        settings.setExpandedByDefault(true, for: .cpu)
        settings.setExpandedByDefault(true, for: .network)
        settings.setExpandedByDefault(false, for: .cpu)
        try await Task.sleep(for: .milliseconds(50))

        let restored = MonitorSettings(defaults: defaults)
        #expect(restored.defaultExpandedKinds == [.network])
        #expect(restored.isExpandedByDefault(.network))
        #expect(!restored.isExpandedByDefault(.cpu))
    }

    @MainActor
    @Test func pinnedPanelOriginPersists() async throws {
        let suiteName = "pinnedPanelOriginPersists"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.pinnedPanelOrigin == nil)

        settings.savePinnedPanelOrigin(CGPoint(x: 320, y: 180))
        try await Task.sleep(for: .milliseconds(50))

        let restored = MonitorSettings(defaults: defaults)
        #expect(restored.pinnedPanelOrigin == CGPoint(x: 320, y: 180))
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
        #expect(MenuBarMetricFormatter.throughput(512, direction: "↑") == "↑512B")
        #expect(MenuBarMetricFormatter.capacity(128_000_000_000) == "128G")
        #expect(MenuBarMetricFormatter.capacity(nil) == "  --")
        #expect(MenuBarMetricFormatter.refreshRate(120.0) == "120Hz")
        #expect(MenuBarMetricFormatter.refreshRate(nil) == " --Hz")
        #expect(MenuBarMetricFormatter.displayPower(1.5) == "1.5W")
        #expect(MenuBarMetricFormatter.displayPower(nil) == " --W")
        #expect(MenuBarMetricFormatter.bandwidth(9.4) == "9.4G")
        #expect(MenuBarMetricFormatter.bandwidth(128.0) == "128G")
        #expect(MenuBarMetricFormatter.bandwidth(nil) == " --G")
    }

    @Test func batteryCellBalanceMigratesForExistingUsers() {
        let suiteName = "batteryCellBalanceMigratesForExistingUsers"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // 模拟已存在老配置：存量中无 cell-balance
        let legacyMetrics = ["health", "cycle-count", "capacity", "temperature", "voltage", "current"]
        defaults.set(legacyMetrics, forKey: "settings.enabledMetrics.battery")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.isMetricEnabled("cell-balance", for: .battery))
        #expect(settings.isMetricEnabled("health", for: .battery))
        #expect(defaults.bool(forKey: "settings.batteryCellBalanceMigrated"))
    }

    @Test func gpuUsageAndClockStateOrderMigratesForExistingUsers() {
        let suiteName = "gpuUsageAndClockStateOrderMigratesForExistingUsers"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let legacyMetrics = ["gpu-memory", "allocated", "render", "tiler", "clock-state"]
        defaults.set(legacyMetrics, forKey: "settings.enabledMetrics.gpu")
        defaults.set([
            "metrics.gpu": ["gpu-memory", "allocated", "render", "tiler", "clock-state", "throttle", "power-cap"]
        ], forKey: "settings.panel.orders")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.isMetricEnabled("usage", for: .gpu))
        #expect(settings.isMetricEnabled("clock-state", for: .gpu))
        let order = settings.panelOrder(for: .metrics(.gpu))
        #expect(order.prefix(2) == ["usage", "clock-state"])
    }

    @MainActor
    @Test func settingsWindowLifecycleReleasesOnClose() {
        let appDelegate = AppDelegate()
        _ = appDelegate.store
        #expect(SettingsWindowPresenter.settingsWindow == nil)

        SettingsWindowPresenter.open()
        let window1 = SettingsWindowPresenter.settingsWindow
        #expect(window1 != nil)

        SettingsWindowPresenter.close()
        #expect(SettingsWindowPresenter.settingsWindow == nil)

        SettingsWindowPresenter.open()
        let window2 = SettingsWindowPresenter.settingsWindow
        #expect(window2 != nil)
        #expect(window2 !== window1)

        SettingsWindowPresenter.close()
        #expect(SettingsWindowPresenter.settingsWindow == nil)
    }
}
