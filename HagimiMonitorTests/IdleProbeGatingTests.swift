import Testing
@testable import HagimiMonitorDirect

@Suite("Idle probe gating policy")
struct IdleProbeGatingTests {
    @Test("Temperature stays enabled for any real consumer")
    func temperatureConsumerMatrix() {
        #expect(!IdleProbeGating.temperatureReadsEnabled(
            panelVisible: false,
            menuBarShowsMetrics: true,
            menuBarTemperatureSelected: false,
            gameHUDActive: false
        ))
        #expect(IdleProbeGating.temperatureReadsEnabled(
            panelVisible: true,
            menuBarShowsMetrics: false,
            menuBarTemperatureSelected: false,
            gameHUDActive: false
        ))
        #expect(IdleProbeGating.temperatureReadsEnabled(
            panelVisible: false,
            menuBarShowsMetrics: true,
            menuBarTemperatureSelected: true,
            gameHUDActive: false
        ))
        #expect(!IdleProbeGating.temperatureReadsEnabled(
            panelVisible: false,
            menuBarShowsMetrics: false,
            menuBarTemperatureSelected: true,
            gameHUDActive: false
        ), "环形模式不显示温度时不应为了勾选列表继续读 SMC")
        #expect(IdleProbeGating.temperatureReadsEnabled(
            panelVisible: false,
            menuBarShowsMetrics: false,
            menuBarTemperatureSelected: false,
            gameHUDActive: true
        ), "Game HUD 显示且勾选温度时保持读取")
    }

    @Test("Public IP requires both an open panel and enabled metric")
    func publicIPConsumerMatrix() {
        #expect(!IdleProbeGating.publicIPQueriesEnabled(panelVisible: false, metricEnabled: true))
        #expect(!IdleProbeGating.publicIPQueriesEnabled(panelVisible: true, metricEnabled: false))
        #expect(IdleProbeGating.publicIPQueriesEnabled(panelVisible: true, metricEnabled: true))
    }

    @Test("Bluetooth profiler requires both an open panel and visible row")
    func bluetoothProfilerConsumerMatrix() {
        #expect(!IdleProbeGating.bluetoothProfilerPollingEnabled(panelVisible: false, bluetoothVisible: true))
        #expect(!IdleProbeGating.bluetoothProfilerPollingEnabled(panelVisible: true, bluetoothVisible: false))
        #expect(IdleProbeGating.bluetoothProfilerPollingEnabled(panelVisible: true, bluetoothVisible: true))
    }
}
