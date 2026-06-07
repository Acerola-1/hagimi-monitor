//
//  HagimiMonitorTests.swift
//  HagimiMonitorTests
//
//  Created by Acerola on 2026/5/11.
//

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

    @Test func catDialogueEngineReturnsNonEmpty() {
        let module = MonitorModule.placeholder(kind: .cpu)
        let line = CatDialogueEngine.line(for: module, modules: [module])
        #expect(!line.isEmpty)
    }

    @Test func computeLoadCombinesCPUAndGPU() {
        #expect(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25) == 40)
        #expect(ComputeLoadModel.combined(cpuValue: 140, gpuValue: -20) == 60)
    }

    @Test func monitorRefreshScheduleTickInterval() {
        let schedule = MonitorRefreshSchedule()
        #expect(schedule.tickInterval == 1.0)
    }
}
