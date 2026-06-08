//
//  HagimiMonitorTests.swift
//  HagimiMonitorTests
//
//  Created by Acerola on 2026/5/11.
//

import Foundation
import Testing
@testable import HagimiMonitor

struct HagimiMonitorTests {

    @Test func monitorSeverityCalculation() {
        #expect(MonitorSeverity.calm.title == "正常")
        #expect(MonitorSeverity.warning.title == "接近阈值")
        #expect(MonitorSeverity.critical.title == "需要注意")
    }

    @Test func monitorKindIdentification() {
        #expect(MonitorKind.cpu.title == "CPU")
        #expect(MonitorKind.gpu.title == "GPU")
        #expect(MonitorKind.memory.title == "内存")
    }

    @Test func monitorModuleSeverityForCPU() {
        let module = MonitorModule(
            kind: .cpu,
            value: 90,
            summary: "90%",
            metrics: [],
            samples: []
        )
        #expect(module.severity == .critical)
    }

    @Test func computeLoadCombinesCPUAndGPU() {
        #expect(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25) == 30)
        #expect(ComputeLoadModel.combined(cpuValue: 140, gpuValue: -20) == 40)
    }

    @Test func computeLoadIncludesMemoryPressure() {
        #expect(ComputeLoadModel.memoryPressureScore(.normal) == 0)
        #expect(ComputeLoadModel.memoryPressureScore(.warning) == 70)
        #expect(ComputeLoadModel.memoryPressureScore(.critical) == 100)
        #expect(ComputeLoadModel.memoryPressureScore(.unknown) == 0)
        #expect(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25, memoryPressure: .warning) == 44)
        #expect(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25, memoryPressure: .critical) == 50)
    }

    @Test func computeLoadDisplayValueMovesTowardTarget() {
        #expect(ComputeLoadModel.smoothedDisplayValue(current: 10, target: 50) == 11.25)
        #expect(ComputeLoadModel.smoothedDisplayValue(current: 50, target: 10) == 48.75)
        #expect(ComputeLoadModel.smoothedDisplayValue(current: 49, target: 50) == 50)
    }

    @Test func menuBarTargetIgnoresSmallComputeLoadChanges() {
        #expect(!ComputeLoadModel.shouldUpdateMenuBarTarget(currentTarget: 30, nextTarget: 34.9))
        #expect(ComputeLoadModel.shouldUpdateMenuBarTarget(currentTarget: 30, nextTarget: 35))
        #expect(ComputeLoadModel.shouldUpdateMenuBarTarget(currentTarget: 35, nextTarget: 30))
    }

    @Test func monitorRefreshScheduleTickInterval() {
        let schedule = MonitorRefreshSchedule()
        #expect(schedule.tickInterval == 1.0)
    }

    @Test func networkAddressSummaryFormatsAddresses() {
        #expect(networkAddressSummary(["192.168.1.8"]) == "192.168.1.8")
        #expect(networkAddressSummary(["192.168.1.8", "2001:db8::8"]) == "192.168.1.8, 2001:db8::8")
        #expect(networkAddressSummary([]) == "--")
    }

    @Test func monitorColorSchemeDefaultsToBalanced() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.default")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.default")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .balanced)
    }

    @Test func monitorColorSchemeLoadsPersistedValue() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.persisted")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.persisted")
        defaults.set(MonitorColorSchemePreference.vibrant.rawValue, forKey: "settings.colorSchemePreference")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .vibrant)
    }

    @Test func monitorColorSchemeFallsBackForUnknownValue() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.unknown")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.unknown")
        defaults.set("unknown", forKey: "settings.colorSchemePreference")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .balanced)
    }
}
