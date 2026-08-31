import Foundation
import Testing
@testable import HagimiMonitorDirect

struct HagimiMonitorTests {

    @Test func monitorSeverityCalculation() {
        #expect(MonitorSeverity.calm != .warning)
        #expect(MonitorSeverity.warning != .critical)
        #expect(MonitorSeverity.critical != .calm)
    }

    @Test func monitorKindIdentification() {
        #expect(MonitorKind.cpu.id == "cpu")
        #expect(MonitorKind.gpu.id == "gpu")
        #expect(MonitorKind.memory.id == "memory")
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

    @Test func batterySeverityUsesRawPowerTypeKey() {
        let module = MonitorModule(
            kind: .battery,
            value: 100,
            summary: "ac-power",
            metrics: [
                MonitorMetric(name: "type", value: "ac-power")
            ],
            samples: []
        )

        #expect(module.severity == .calm)
    }

    @Test func systemPowerCalculationUsesSignedBatteryPowerForCharging() {
        let result = systemPowerWattsFromTelemetry(systemPowerIn: 1200, batteryPower: -200)

        #expect(result != nil)
        #expect(abs(result! - 1.0) < 0.0001)
    }

    @Test func placeholderMetricNamesAreStableKeys() {
        let module = MonitorModule.placeholder(kind: .cpu)

        #expect(module.metrics.map(\.name) == ["current", "average", "peak"])
    }

    @Test func computeLoadCombinesCPUAndGPU() {
        // softmax 聚合(k=0.08)：落在 [mean, max] 之间，偏向瓶颈
        #expect(abs(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25) - 38.053992) < 1e-4)
        #expect(abs(ComputeLoadModel.combined(cpuValue: 140, gpuValue: -20) - 86.275730) < 1e-4)
    }

    @Test func computeLoadIncludesMemoryPressure() {
        #expect(ComputeLoadModel.memoryPressureScore(.normal) == 0)
        #expect(ComputeLoadModel.memoryPressureScore(.warning) == 50)
        #expect(ComputeLoadModel.memoryPressureScore(.critical) == 85)
        #expect(ComputeLoadModel.memoryPressureScore(.unknown) == 0)
        #expect(abs(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25, memoryPressure: .warning) - 45.750142) < 1e-4)
        #expect(abs(ComputeLoadModel.combined(cpuValue: 50, gpuValue: 25, memoryPressure: .critical) - 72.101857) < 1e-4)
    }

    @Test func computeLoadSoftmaxSurfacesSingleBottleneck() {
        // 内存 critical 但 CPU/GPU 空闲：聚合值应进入 busy 区(≥50)，不被均值掩盖
        let load = ComputeLoadModel.combined(cpuValue: 5, gpuValue: 5, memoryPressure: .critical)
        #expect(load >= 50)
        #expect(ComputeLoadModel.loadLevel(for: load) == .busy)
        #expect(ComputeLoadModel.combined(cpuValue: 5, gpuValue: 5, memoryPressure: .normal) < 10)
    }

    @Test func loadLevelThresholdsCalibratedForSoftmax() {
        #expect(ComputeLoadModel.loadLevel(for: 24) == .idle)
        #expect(ComputeLoadModel.loadLevel(for: 25) == .working)
        #expect(ComputeLoadModel.loadLevel(for: 49) == .working)
        #expect(ComputeLoadModel.loadLevel(for: 50) == .busy)
        #expect(ComputeLoadModel.loadLevel(for: 77) == .busy)
        #expect(ComputeLoadModel.loadLevel(for: 78) == .stressed)
        #expect(ComputeLoadModel.loadLevel(for: ComputeLoadModel.combined(cpuValue: 100, gpuValue: 0)) == .stressed)
        #expect(ComputeLoadModel.loadLevel(for: ComputeLoadModel.combined(cpuValue: 70, gpuValue: 0)) == .busy)
    }

    @Test func computeLoadDisplayValueMovesTowardTarget() {
        // ease-out：每帧靠拢 distance×factor(0.10)，不小于 minStep(0.6)
        #expect(abs(ComputeLoadModel.smoothedDisplayValue(current: 10, target: 50) - 14) < 1e-9)
        #expect(abs(ComputeLoadModel.smoothedDisplayValue(current: 50, target: 10) - 46) < 1e-9)
        #expect(abs(ComputeLoadModel.smoothedDisplayValue(current: 49, target: 50) - 49.6) < 1e-9)
        #expect(ComputeLoadModel.smoothedDisplayValue(current: 49.7, target: 50) == 50)
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

    @Test func monitorColorSchemeDefaultsToVibrant() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.default")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.default")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .vibrant)
    }

    @Test func monitorColorSchemeLoadsPersistedValue() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.persisted")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.persisted")
        defaults.set(MonitorColorSchemePreference.balanced.rawValue, forKey: "settings.colorSchemePreference")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .balanced)
    }

    @Test func monitorColorSchemeFallsBackForUnknownValue() {
        let defaults = UserDefaults(suiteName: "HagimiMonitorTests.colorScheme.unknown")!
        defaults.removePersistentDomain(forName: "HagimiMonitorTests.colorScheme.unknown")
        defaults.set("unknown", forKey: "settings.colorSchemePreference")

        let settings = MonitorSettings(defaults: defaults)

        #expect(settings.colorSchemePreference == .vibrant)
    }

    @Test func batteryAvailableMetricsExcludePowerFlowChain() {
        let ids = MonitorKind.battery.availableMetrics.map(\.id)
        // 转换损耗已从可开关指标中移除:功率流图承载功率数据,指标网格只留健康度/循环/温度。
        #expect(!ids.contains("loss"))
        // 功率流数据链(power-in/battery-flow/time-remaining)不是可开关的明细项,
        // 不应出现在指标网格的可选列表里。
        #expect(!ids.contains("power-in"))
        #expect(!ids.contains("battery-flow"))
        #expect(!ids.contains("time-remaining"))
    }
}
