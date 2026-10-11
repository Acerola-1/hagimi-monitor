import Foundation

nonisolated enum PanelHistoryChartStyle: String, CaseIterable, Identifiable, Sendable {
    case bars
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: String(localized: "panel.chart.type.bars")
        case .line: String(localized: "panel.chart.type.line")
        }
    }

    static func supports(_ kind: MonitorKind) -> Bool {
        [.cpu, .gpu, .fan, .memory].contains(kind)
    }
}

nonisolated struct PanelChartLinePoint: Equatable, Sendable {
    let slot: Int
    let fraction: Double
}

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
    /// 两种图表共用固定时间槽；缺失样本断开折线，不跨空缺连接或把空缺当零。
    static func lineSegments(_ samples: [Double], scale: PanelChartScale) -> [[PanelChartLinePoint]] {
        let capacity = MonitorConstants.sparklineMaxPoints
        let values = Array(samples.suffix(capacity))
        var segments: [[PanelChartLinePoint]] = []
        var segment: [PanelChartLinePoint] = []
        for (index, value) in values.enumerated() {
            if let fraction = scale.fraction(value) {
                segment.append(PanelChartLinePoint(slot: capacity - values.count + index, fraction: fraction))
            } else if !segment.isEmpty {
                segments.append(segment)
                segment.removeAll(keepingCapacity: true)
            }
        }
        if !segment.isEmpty { segments.append(segment) }
        return segments
    }

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
