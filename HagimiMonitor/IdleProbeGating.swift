import Foundation

/// 面板隐藏期的探针开关策略。集中在一个纯函数边界里,各调用方共用同一条件,
/// 也便于覆盖“菜单栏/主面板/Game HUD”三类温度消费者的组合。
nonisolated enum IdleProbeGating {
    static func temperatureReadsEnabled(
        panelVisible: Bool,
        menuBarShowsMetrics: Bool,
        menuBarTemperatureSelected: Bool,
        gameHUDActive: Bool
    ) -> Bool {
        panelVisible || (menuBarShowsMetrics && menuBarTemperatureSelected) || gameHUDActive
    }

    static func publicIPQueriesEnabled(panelVisible: Bool, metricEnabled: Bool) -> Bool {
        panelVisible && metricEnabled
    }

    static func bluetoothProfilerPollingEnabled(panelVisible: Bool, bluetoothVisible: Bool) -> Bool {
        panelVisible && bluetoothVisible
    }
}
