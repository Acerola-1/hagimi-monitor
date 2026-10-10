import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct PanelChartStyleSettingsTests {
    @Test func freshInstallKeepsBarsAcrossLaunches() {
        let suite = "panelChartStyleSettings.fresh." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // 首次启动的无关记录不代表曾经使用过监控设置。
        defaults.set(true, forKey: "app.launch.started")
        for _ in 0..<3 {
            let settings = MonitorSettings(defaults: defaults)
            for kind in [MonitorKind.cpu, .gpu, .fan, .memory] {
                #expect(settings.panelChartStyle(for: kind) == .bars)
            }
        }
        #expect(defaults.bool(forKey: "settings.panel.chartStylesMigrated"))
    }

    @Test func existingDefaultUserKeepsLinesAndCanChangeAfterMigration() {
        let suite = "panelChartStyleSettings.upgrade." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // 旧版初始化会保存此标记，即使用户从未更改任何设置。
        defaults.set(true, forKey: "settings.metricsDefaultOnMigrated")
        for _ in 0..<2 {
            let settings = MonitorSettings(defaults: defaults)
            for kind in [MonitorKind.cpu, .gpu, .fan, .memory] {
                #expect(settings.panelChartStyle(for: kind) == .line)
            }
        }
        let stored = defaults.dictionary(forKey: "settings.panel.chartStyles") as? [String: String]
        #expect(stored == ["cpu": "line", "gpu": "line", "fan": "line", "memory": "line"])
        let settings = MonitorSettings(defaults: defaults)
        settings.setPanelChartStyle(.bars, for: .cpu)
        let restored = MonitorSettings(defaults: defaults)
        #expect(restored.panelChartStyle(for: .cpu) == .bars)
        for kind in [MonitorKind.gpu, .fan, .memory] {
            #expect(restored.panelChartStyle(for: kind) == .line)
        }
    }

    @Test(arguments: ["settings.themePreference", "settings.enabledMetrics.cpu"])
    func olderPreferencesWithoutMigrationMarkerKeepLines(key: String) {
        let suite = "panelChartStyleSettings.older." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        if key == "settings.themePreference" {
            defaults.set("dark", forKey: key)
        } else {
            defaults.set(["usage"], forKey: key)
        }
        let settings = MonitorSettings(defaults: defaults)
        for kind in [MonitorKind.cpu, .gpu, .fan, .memory] {
            #expect(settings.panelChartStyle(for: kind) == .line)
        }
    }

    @Test(arguments: [true, false])
    func existingChartPreferencesArePreservedIncludingEmptyDictionary(empty: Bool) {
        let suite = "panelChartStyleSettings.selected." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "settings.metricsDefaultOnMigrated")
        let choices: [String: String] = empty ? [:] : ["cpu": "line", "gpu": "bars"]
        defaults.set(choices, forKey: "settings.panel.chartStyles")
        for _ in 0..<2 {
            let settings = MonitorSettings(defaults: defaults)
            #expect(settings.panelChartStyle(for: .cpu) == (empty ? .bars : .line))
            for kind in [MonitorKind.gpu, .fan, .memory] {
                #expect(settings.panelChartStyle(for: kind) == .bars)
            }
        }
        #expect(defaults.dictionary(forKey: "settings.panel.chartStyles") as? [String: String] == choices)
    }

    @Test func choicesPersistIndependentlyAndResetOnlyTheirModule() {
        let suite = "panelChartStyleSettings." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        let supported: [MonitorKind] = [.cpu, .gpu, .fan, .memory]
        for kind in supported { #expect(settings.panelChartStyle(for: kind) == .bars) }
        settings.setPanelChartStyle(.line, for: .cpu)
        settings.setPanelChartStyle(.line, for: .fan)
        settings.setPanelChartStyle(.line, for: .memory)
        settings.memoryPrimaryMetric = .usage

        let restored = MonitorSettings(defaults: defaults)
        #expect(restored.panelChartStyle(for: .cpu) == .line)
        #expect(restored.panelChartStyle(for: .gpu) == .bars)
        #expect(restored.panelChartStyle(for: .fan) == .line)
        #expect(restored.panelChartStyle(for: .memory) == .line)
        #expect(restored.memoryPrimaryMetric == .usage)
        restored.setPanelChartStyle(.line, for: .gpu)
        restored.resetMetrics(for: .cpu)
        let reset = MonitorSettings(defaults: defaults)
        #expect(reset.panelChartStyle(for: .cpu) == .bars)
        #expect(reset.panelChartStyle(for: .gpu) == .line)
        #expect(reset.panelChartStyle(for: .fan) == .line)
        #expect(reset.panelChartStyle(for: .memory) == .line)
    }

    @Test func invalidStoredValuesDoNotDiscardOtherModuleChoices() {
        let suite = "panelChartStyleSettings.invalid." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored: [String: Any] = ["cpu": "future-style", "gpu": "line", "fan": 42,
                                     "memory": "line", "storage": "line", "unknown": "line"]
        defaults.set(stored, forKey: "settings.panel.chartStyles")
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.panelChartStyle(for: .cpu) == .bars)
        #expect(settings.panelChartStyle(for: .fan) == .bars)
        #expect(settings.panelChartStyle(for: .gpu) == .line)
        #expect(settings.panelChartStyle(for: .memory) == .line)
        #expect(settings.panelChartStyles[.storage] == nil)
    }

    @Test func nonChartModulesCannotAcquireAChartPreference() {
        let suite = "panelChartStyleSettings.unsupported." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        for kind in [MonitorKind.storage, .network, .battery, .bluetooth] {
            #expect(!PanelHistoryChartStyle.supports(kind))
            settings.setPanelChartStyle(.line, for: kind)
        }
        #expect(settings.panelChartStyles.isEmpty)
        #expect(defaults.object(forKey: "settings.panel.chartStyles") == nil)
    }
}
