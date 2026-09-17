import AppKit
import Charts
import SwiftUI

/// 电源与电池模块报表视图：包含整机功耗趋势、电池电量与温度、电池健康与循环历史，以及区分台式机与笔记本无历史场景。
struct ReportPowerView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?

    private let powerColor = ReportUIHelper.powerColor
    private let batteryColor = ReportUIHelper.batteryColor
    private let tempColor = ReportUIHelper.thermalColor

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行
                kpiSummaryRow

                // 2. 整机功耗趋势图
                powerTrendCard

                // 3. 电池电量与温度趋势（R03: 严格区分硬件支持与范围数据可用性）
                if let battery = viewModel.rangeModel?.battery {
                    if battery.isSupported {
                        if battery.hasHistoryInRange {
                            batteryLevelCard
                            if viewModel.selectedRange != .today && !battery.dailyHistory.isEmpty {
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

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离高频广播)
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
                color: powerColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeakPower", defaultValue: "峰值功耗"),
                value: p?.peakPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                caption: nil,
                color: ReportUIHelper.peakColor
            )
            if hasBatt {
                ReportKpiCard(
                    title: String(localized: "stats.r.battLevel", defaultValue: "电池均值"),
                    value: b?.avgLevel.map { String(format: "%.0f%%", $0) } ?? "—",
                    caption: nil,
                    color: batteryColor
                )
                ReportKpiCard(
                    title: String(localized: "stats.r.sBattTemp", defaultValue: "电池温度"),
                    value: b?.avgTemp.map { String(format: "%.1f°C", $0) } ?? "—",
                    caption: nil,
                    color: (b?.avgTemp ?? 0) > 40 ? tempColor : .secondary
                )
            } else {
                ReportKpiCard(
                    title: String(localized: "stats.r.powerSupply", defaultValue: "供电状态"),
                    value: "AC 交流供电",
                    caption: "台式机形态",
                    color: .secondary
                )
            }
        }
    }

    // MARK: - 2. 整机功耗趋势图卡片 (R07: 独立分段防跨睡眠连线)

    private var powerTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let powerPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.powerAvg,
            seriesID: "power",
            granularitySeconds: granularity
        )

        return ReportCardView(
            title: String(localized: "stats.r.railPower", defaultValue: "整机功耗趋势"),
            icon: "powerplug"
        ) {
            if powerPoints.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无功耗采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.systemPower", defaultValue: "系统功耗 (W)"), color: powerColor)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows), let w = row.powerAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): 功耗 \(String(format: "%.1f W", w))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(powerPoints) { pt in
                            if let val = pt.value {
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Power", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [powerColor.opacity(0.35), powerColor.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.monotone)

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Power", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(powerColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedDate {
                            RuleMark(x: .value("Selected", selectedDate))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text(String(format: "%.0f W", val))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.12))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(viewModel.selectedRange == .today ? ReportUIHelper.formatTimeOnly(date) : ReportUIHelper.formatDateShort(date))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 220)
                }
            }
        }
    }

    // MARK: - 3. 电池电量与温度趋势卡片 (R07: 独立分段防跨睡眠连线)

    private var batteryLevelCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let levelPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.battLevelAvg,
            seriesID: "level",
            granularitySeconds: granularity
        )
        let tempPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.battTempAvg,
            seriesID: "temp",
            granularitySeconds: granularity
        )

        return ReportCardView(
            title: String(localized: "stats.r.battLevelTitle", defaultValue: "电池电量与温度"),
            icon: "battery.100"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    ReportLegendItem(title: String(localized: "stats.r.battLevel", defaultValue: "电量 (%)"), color: batteryColor)
                    ReportLegendItem(title: String(localized: "stats.r.battTemp", defaultValue: "温度 (°C)"), color: tempColor, isDashed: true)
                }

                Chart {
                    ForEach(levelPoints) { pt in
                        if let val = pt.value {
                            LineMark(
                                x: .value("Time", pt.date),
                                y: .value("Level", val),
                                series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                            )
                            .foregroundStyle(batteryColor)
                            .interpolationMethod(.monotone)
                        }
                    }

                    ForEach(tempPoints) { pt in
                        if let val = pt.value {
                            LineMark(
                                x: .value("Time", pt.date),
                                y: .value("Temp", val),
                                series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                            )
                            .foregroundStyle(tempColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text("\(Int(val))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(ReportUIHelper.formatDateShort(date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - 4. 电池健康与循环历史 (R16: 动态 Y 轴不截断 <70% 健康度，保留循环独立呈现)

    private func batteryHealthHistoryCard(history: [ReportBatteryMetrics.DailyHealth]) -> some View {
        let validHealths = history.compactMap(\.healthPercent)
        let minHealth = validHealths.min() ?? 80
        let lowerBound = max(0, min(minHealth - 5, 60))

        return ReportCardView(
            title: String(localized: "stats.r.battHistoryTitle", defaultValue: "电池健康度与循环变化"),
            icon: "heart.text.square"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    ReportLegendItem(title: String(localized: "stats.r.sBattHealth", defaultValue: "最大容量 (%)"), color: batteryColor)
                }

                Chart {
                    ForEach(history) { point in
                        let dateStr = ReportUIHelper.formatDateShort(point.date)
                        let healthVal = point.healthPercent ?? 100

                        if point.healthPercent != nil {
                            LineMark(
                                x: .value("Date", dateStr),
                                y: .value("Health", healthVal)
                            )
                            .foregroundStyle(batteryColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                            .interpolationMethod(.monotone)

                            PointMark(
                                x: .value("Date", dateStr),
                                y: .value("Health", healthVal)
                            )
                            .foregroundStyle(batteryColor)
                            .symbolSize(20)
                        }

                        if let cycles = point.cycleCount {
                            PointMark(
                                x: .value("Date", dateStr),
                                y: .value("Health", healthVal)
                            )
                            .foregroundStyle(point.healthPercent != nil ? batteryColor : Color.secondary)
                            .annotation(position: .top) {
                                Text("\(cycles)循")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 电池历史无采样说明卡片 (R03)

    private var batteryNoHistoryCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.battLevelTitle", defaultValue: "电池电量与健康"),
            icon: "battery.100"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "battery.50")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.r.battNoHistoryDesc", defaultValue: "当前设备具备内置电池，但在所选时间范围内未记录到电池充放电或健康度采样。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 台式机说明卡片 (R03)

    private var desktopMacCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.desktopMacTitle", defaultValue: "台式形态 Mac"),
            icon: "desktopcomputer"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "powerplug")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.r.desktopMacDesc", defaultValue: "当前设备由交流电源直接供电，系统内不存在电池模组或循环损耗记录。整机功耗已准确记录。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}
