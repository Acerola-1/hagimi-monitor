import Foundation

/// 纵轴始终有固定物理含义，不随最近样本的高低伸缩。
nonisolated struct PanelChartScale: Equatable, Sendable {
    var lower: Double = 0
    var upper: Double = 100

    func fraction(_ value: Double) -> Double? {
        guard value.isFinite, lower.isFinite, upper.isFinite, upper > lower else { return nil }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}

nonisolated enum PanelChartReadings {
    static func memorySamples(_ module: MonitorModule, pressureMode: Bool) -> [Double] {
        guard !module.isPlaceholder else { return [] }
        return pressureMode ? module.pressureSamples : module.samples
    }

    static func fanScale(_ fans: [FanInfo]) -> PanelChartScale? {
        guard !fans.isEmpty, fans.allSatisfy({ $0.maxRPM > 0 }) else { return nil }
        return PanelChartScale(upper: Double(fans.map(\.maxRPM).max() ?? 0))
    }

    static func fanSummary(_ module: MonitorModule) -> String {
        guard !module.isPlaceholder, let fans = module.fans, !fans.isEmpty else { return "—" }
        let rpm = fans.map(\.currentRPM).max() ?? 0
        return "\(rpm) RPM"
    }
}
