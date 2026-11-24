import AppKit
import Charts
import SwiftUI

/// 电源与电池模块报表视图：包含整机功耗趋势、电池电量/温度分切图、电池健康与循环历史，以及区分台式机与笔记本无历史场景。
struct ReportPowerView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var batteryChartMode: BatteryChartMode = .level
    @State private var hoveredHealthDate: Date?

    enum BatteryChartMode: String, CaseIterable, Identifiable {
        case level
        case temperature

        var id: String { rawValue }

        var label: String {
            switch self {
            case .level: return String(localized: "stats.r.battLevel", defaultValue: "电量 (%)")
            case .temperature: return String(localized: "stats.r.battTemp", defaultValue: "温度 (°C)")
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 16) {
                kpiSummaryRow
                powerTrendCard

                if let battery = viewModel.rangeModel?.battery {
                    if battery.isSupported {
                        if battery.hasHistoryInRange {
                            batteryLevelCard
                            if !viewModel.isSingleDaySelected && !battery.dailyHistory.isEmpty {
                                batteryHealthHistoryCard(history: battery.dailyHistory)
                            }
                        } else {
                            batteryNoHistoryCard
                        }
                    } else {
                        desktopMacCard
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ReportHardwareRailView(
                moduleId: "power",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let p = viewModel.rangeModel?.power
        let b = viewModel.rangeModel?.battery
        let hasBatt = b?.isSupported ?? false

        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgPower", defaultValue: "平均功耗"),
                value: p?.avgPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                caption: nil,
                color: palette.power
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeakPower", defaultValue: "峰值功耗"),
                value: p?.peakPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                caption: nil,
                color: palette.cpuPeak
            )
            if hasBatt {
                ReportKpiCard(
                    title: String(localized: "stats.r.battLevel", defaultValue: "电池均值"),
                    value: b?.avgLevel.map { String(format: "%.0f%%", $0) } ?? "—",
                    caption: b?.acFraction.map {
                        String(format: String(localized: "stats.r.acShare"), $0 * 100)
                    },
                    color: palette.battery
                )
                ReportKpiCard(
                    title: String(localized: "stats.r.sBattTemp", defaultValue: "电池温度"),
                    value: b?.avgTemp.map { String(format: "%.1f°C", $0) } ?? "—",
                    caption: nil,
                    color: (b?.avgTemp ?? 0) > 40 ? palette.thermal : .secondary
                )
            } else {
                ReportKpiCard(
                    title: String(localized: "stats.r.powerSupply", defaultValue: "供电状态"),
                    value: String(localized: "stats.r.acPower"),
                    caption: String(localized: "stats.r.desktopMacFormFactor"),
                    color: .secondary
                )
            }
        }
    }

    // MARK: - 2. 整机功耗趋势图卡片

    private var powerTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.railPower", defaultValue: "整机功耗趋势"),
            icon: "powerplug"
        ) {
            if cache.powerWatts.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无功耗采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "power",
                            title: String(localized: "stats.r.systemPower", defaultValue: "系统功耗 (W)"),
                            series: cache.powerWatts,
                            color: palette.power,
                            lineWidth: 1.6,
                            showAreaFill: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .watts,
                    height: 220
                )
            }
        }
    }

    // MARK: - 3. 电池电量与温度分切卡片（独立单位轴，消除单轴混放）

    private var batteryLevelCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty
        let hasTemp = !cache.batteryTemp.isEmpty

        return ReportCardView(
            title: String(localized: "stats.r.battLevelTitle", defaultValue: "电池电量与温度"),
            icon: "battery.100",
            trailing: {
                if hasTemp {
                    ReportNavigationPicker(
                        title: "",
                        selection: $batteryChartMode,
                        options: BatteryChartMode.allCases.map { ReportSegmentOption(value: $0, label: $0.label) },
                        size: .compact
                    )
                    .fixedSize()
                }
            }
        ) {
            if batteryChartMode == .level || !hasTemp {
                if cache.batteryLevel.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无电量采样"))
                } else {
                    ReportTimeSeriesChart(
                        descriptors: [
                            ReportChartSeriesDescriptor(
                                id: "level",
                                title: String(localized: "stats.r.battLevel", defaultValue: "电量 (%)"),
                                series: cache.batteryLevel,
                                color: palette.battery,
                                lineWidth: 1.7,
                                showAreaFill: true
                            )
                        ],
                        isSingleDay: viewModel.isSingleDaySelected,
                        yAxisFormat: .percent,
                        yDomain: 0...100,
                        yAxisValues: [0, 25, 50, 75, 100],
                        height: 185
                    )
                }
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "battTemp",
                            title: String(localized: "stats.r.battTemp", defaultValue: "温度 (°C)"),
                            series: cache.batteryTemp,
                            color: palette.thermal,
                            lineWidth: 1.6,
                            showAreaFill: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .celsius,
                    height: 185
                )
            }
        }
    }

    // MARK: - 4. 电池健康与循环历史（连续时间轴 + 悬浮提示，解决全年分类文字重叠）

    private func batteryHealthHistoryCard(history: [ReportBatteryMetrics.DailyHealth]) -> some View {
        let validHealths = history.compactMap(\.healthPercent)
        let minHealth = validHealths.min() ?? 80
        let lowerBound = max(0, min(minHealth - 5, 60))

        let hoveredPoint: ReportBatteryMetrics.DailyHealth? = {
            guard let target = hoveredHealthDate else { return nil }
            return history.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })
        }()

        return ReportCardView(
            title: String(localized: "stats.r.battHistoryTitle", defaultValue: "电池健康度与循环变化"),
            icon: "heart.text.square"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    ReportLegendItem(title: String(localized: "stats.r.sBattHealth", defaultValue: "最大容量 (%)"), color: palette.battery)
                    Spacer()
                    if let pt = hoveredPoint {
                        let healthStr = pt.healthPercent.map { String(format: "%.1f%%", $0) } ?? "—"
                        let cycleStr = pt.cycleCount.map {
                            String(format: String(localized: "stats.r.battCyclesInline"), $0)
                        } ?? ""
                        Text("\(ReportUIHelper.formatDateShort(pt.date)): \(healthStr)\(cycleStr.isEmpty ? "" : " · \(cycleStr)")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                    } else if let latest = history.last, let latestCycles = latest.cycleCount {
                        Text(String(format: String(localized: "stats.r.battLatestCycle"), latestCycles))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart {
                    ForEach(history) { point in
                        if let healthVal = point.healthPercent {
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Health", healthVal)
                            )
                            .foregroundStyle(palette.battery)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                            .interpolationMethod(.monotone)

                            if history.count <= 45 {
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Health", healthVal)
                                )
                                .foregroundStyle(palette.battery)
                                .symbolSize(20)
                            }
                        }
                    }

                    if let hoveredPoint, let healthVal = hoveredPoint.healthPercent {
                        RuleMark(x: .value("Hover", hoveredPoint.date))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(
                            x: .value("Hover", hoveredPoint.date),
                            y: .value("Health", healthVal)
                        )
                        .foregroundStyle(palette.battery)
                        .symbolSize(40)
                    }
                }
                .chartYScale(domain: lowerBound...100)
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let intVal = val.as(Int.self) {
                                Text("\(intVal)%")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let date = val.as(Date.self) {
                                Text(ReportUIHelper.formatDateShort(date))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geo[plotFrame]
                                    let x = location.x - frame.origin.x
                                    guard x >= 0, x <= frame.size.width else {
                                        hoveredHealthDate = nil
                                        return
                                    }
                                    hoveredHealthDate = proxy.value(atX: x, as: Date.self)
                                case .ended:
                                    hoveredHealthDate = nil
                                }
                            }
                    }
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 电池历史无采样说明 & 台式机卡片

    private var batteryNoHistoryCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.battLevelTitle", defaultValue: "电池电量与健康"),
            icon: "battery.100"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "battery.50")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text(String(localized: "stats.r.battNoHistoryDesc", defaultValue: "当前设备具备内置电池，但在所选时间范围内未记录到电池充放电或健康度采样。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var desktopMacCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.desktopMacTitle", defaultValue: "台式形态 Mac"),
            icon: "desktopcomputer"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "powerplug")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text(String(localized: "stats.r.desktopMacDesc", defaultValue: "当前设备由交流电源直接供电，系统内不存在电池模组或循环损耗记录。整机功耗已准确记录。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}
