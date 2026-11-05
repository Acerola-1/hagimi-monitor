import AppKit
import Charts
import SwiftUI

/// 热状态与风扇模块报表视图：包含热状态档位（0~3 档，杜绝乘 100 误读）、CPU 核心温度趋势、风扇转速，以及处理无风扇机型与沙盒传感器受限场景。
struct ReportThermalView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedTempDate: Date?
    @State private var selectedThermalDate: Date?
    @State private var selectedFanDate: Date?

    private let tempColor = ReportUIHelper.thermalColor
    private let peakColor = ReportUIHelper.peakColor
    private let fanColor = Color(hex: 0x6366F1)
    private let pressureColor = Color(hex: 0xFF9500)

    var body: some View {
        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            // 1. KPI 概览指标行 (R05: 正确语义呈现)
            kpiSummaryRow

            // 2. CPU 核心温度趋势图（若有温度传感器数据）
            cpuTempTrendCard

            // 3. 系统热状态历史档位图 (R05: 0~3 独立展示，沙盒与直连均可用)
            thermalStateTrendCard

            // 4. 风扇转速趋势图 或 无风扇被动散热说明 (R03: 区分无风扇与 0 RPM 停转)
            fanSectionView
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let th = viewModel.rangeModel?.thermal
        let fanReadout = ReportFanReadoutState.resolve(
            hasFans: th?.hasFans ?? false,
            sensorAvailable: th?.fanSensorAvailable ?? false,
            averageRPM: th?.fanAvgRPM,
            peakRPM: th?.fanMaxRPM
        )

        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.secThermal", defaultValue: "系统热状态"),
                value: ReportUIHelper.thermalStateLabel(th?.cpuThermalAvg),
                caption: th?.cpuThermalAvg.map { level in
                    String(localized: "stats.r.thermalAverage \(String(format: "%.1f", level))")
                },
                color: (th?.cpuThermalAvg ?? 0) > 0.5 ? tempColor : Color(hex: 0x34C759)
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgCpuTemp", defaultValue: "CPU 平均温度"),
                value: th?.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? "—",
                caption: nil,
                color: tempColor
            )
            fanKpiCard(for: fanReadout)
        }
    }

    @ViewBuilder
    private func fanKpiCard(for state: ReportFanReadoutState) -> some View {
        switch state {
        case .fanless:
            ReportKpiCard(
                title: String(localized: "stats.r.fanStatus"),
                value: String(localized: "stats.r.fanlessTitle"),
                caption: String(localized: "stats.r.fanlessSubtitle"),
                color: .secondary
            )
        case .unavailable:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: String(localized: "stats.r.fanUnavailableValue"),
                caption: String(localized: "stats.r.fanUnavailableCaption"),
                color: .secondary
            )
        case .noHistory:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: String(localized: "stats.r.fanNoHistoryValue"),
                caption: String(localized: "stats.r.fanNoHistoryCaption"),
                color: .secondary
            )
        case .stopped:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: "0 RPM",
                caption: String(localized: "stats.r.fanStoppedCaption"),
                color: Color(hex: 0x34C759)
            )
        case let .measured(averageRPM, peakRPM):
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: averageRPM.map { String(format: "%.0f RPM", $0) } ?? "—",
                caption: peakRPM.map { String(localized: "stats.r.fanPeak \(String(format: "%.0f", $0))") },
                color: fanColor
            )
        }
    }

    // MARK: - 2. CPU 核心温度趋势图卡片

    private var cpuTempTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let tempPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuTempAvg,
            seriesID: "temp",
            granularitySeconds: granularity
        )

        return ReportCardView(
            title: String(localized: "stats.r.cpuTempTitle", defaultValue: "CPU 核心温度趋势"),
            icon: "thermometer.medium"
        ) {
            if tempPoints.isEmpty {
                ReportEmptyPlaceholder(
                    text: viewModel.snapshot?.meta.isDirect == false
                        ? String(localized: "stats.r.tempSandboxNotice", defaultValue: "沙盒受限：CPU 核心温度传感器仅在直连版可用，请参考下方系统热状态")
                        : String(localized: "stats.r.emptySection", defaultValue: "所选范围内无温度传感器记录")
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.cpuTemp", defaultValue: "CPU 温度 (°C)"), color: tempColor)

                        Spacer()

                        if let selectedTempDate, let row = ReportUIHelper.findClosestRow(to: selectedTempDate, in: rows), let t = row.cpuTempAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): 温度 \(String(format: "%.1f°C", t))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(tempPoints) { pt in
                            if let val = pt.value {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Temp", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(tempColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedTempDate {
                            RuleMark(x: .value("Selected", selectedTempDate))
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
                                    Text(String(format: "%.0f°C", val))
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
                    .chartXSelection(value: $selectedTempDate)
                    .frame(height: 180)
                }
            }
        }
    }

    // MARK: - 3. 系统热状态历史档位图 (R05: 0~3 档，使用阶梯插值展示)

    private var thermalStateTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let statePoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuThermalAvg,
            seriesID: "thermalState",
            granularitySeconds: granularity
        )

        return ReportCardView(
            title: String(localized: "stats.r.secThermal", defaultValue: "系统热状态档位"),
            icon: "flame"
        ) {
            if statePoints.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无热状态记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.thermalNominal", defaultValue: "正常 (0)"), color: Color(hex: 0x34C759))
                        ReportLegendItem(title: String(localized: "stats.r.thermalFair", defaultValue: "中度 (1)"), color: Color(hex: 0xF5A623))
                        ReportLegendItem(title: String(localized: "stats.r.thermalSerious", defaultValue: "严重 (2)"), color: Color(hex: 0xFF9500))
                        ReportLegendItem(title: String(localized: "stats.r.thermalCritical", defaultValue: "紧急 (3)"), color: Color(hex: 0xFF3B30))

                        Spacer()

                        if let selectedThermalDate, let row = ReportUIHelper.findClosestRow(to: selectedThermalDate, in: rows), let lvl = row.cpuThermalAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): \(ReportUIHelper.formatThermalLevel(lvl))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(statePoints) { pt in
                            if let val = pt.value {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Level", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(pressureColor)
                                .interpolationMethod(.stepEnd)

                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Level", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [pressureColor.opacity(0.25), pressureColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.stepEnd)
                            }
                        }

                        if let selectedThermalDate {
                            RuleMark(x: .value("Selected", selectedThermalDate))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: 0...3)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel {
                                if let val = value.as(Int.self) {
                                    switch val {
                                    case 0: Text("正常").font(.system(size: 9)).foregroundStyle(.secondary)
                                    case 1: Text("中度").font(.system(size: 9)).foregroundStyle(.secondary)
                                    case 2: Text("严重").font(.system(size: 9)).foregroundStyle(.secondary)
                                    case 3: Text("紧急").font(.system(size: 9)).foregroundStyle(.secondary)
                                    default: EmptyView()
                                    }
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
                    .chartXSelection(value: $selectedThermalDate)
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: - 4. 风扇趋势或说明区域 (R03)

    @ViewBuilder
    private var fanSectionView: some View {
        let th = viewModel.rangeModel?.thermal
        if th?.hasFans == true {
            if th?.fanSensorAvailable == false {
                fanSandboxNoticeCard
            } else {
                fanTrendCard
            }
        } else {
            fanlessNoticeCard
        }
    }

    private var fanTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let fanPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.fanAvg,
            seriesID: "fan",
            granularitySeconds: granularity
        )

        return ReportCardView(
            title: String(localized: "stats.r.fanTrendTitle", defaultValue: "风扇转速趋势"),
            icon: "fan.fill"
        ) {
            if fanPoints.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.fanNoTrend"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sAvgFan", defaultValue: "风扇转速 (RPM)"), color: fanColor)

                        Spacer()

                        if let selectedFanDate, let row = ReportUIHelper.findClosestRow(to: selectedFanDate, in: rows), let rpm = row.fanAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): \(String(format: "%.0f RPM", rpm))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(fanPoints) { pt in
                            if let val = pt.value {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("RPM", val),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(fanColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedFanDate {
                            RuleMark(x: .value("Selected", selectedFanDate))
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
                                    Text(String(format: "%.0f", val))
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
                                    Text(ReportUIHelper.formatDateShort(date))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedFanDate)
                    .frame(height: 180)
                }
            }
        }
    }

    private var fanSandboxNoticeCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.fanStatus", defaultValue: "风扇模组状态"),
            icon: "fan.fill"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.r.fanUnavailableDescription"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var fanlessNoticeCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.fanlessTitle", defaultValue: "被动散热设计"),
            icon: "wind"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "fan.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.r.fanlessDesc", defaultValue: "当前设备采用全被动静音散热架构（如 MacBook Air），机身内部未搭载机械主动散热风扇。系统热状态由能效核与调度器智能管控。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// 将设备能力和所选时段的实测结果分开映射，缺失记录不再解释成零转速。
enum ReportFanReadoutState: Equatable {
    case fanless
    case unavailable
    case noHistory
    case stopped
    case measured(averageRPM: Double?, peakRPM: Double?)

    static func resolve(
        hasFans: Bool,
        sensorAvailable: Bool,
        averageRPM: Double?,
        peakRPM: Double?
    ) -> Self {
        guard hasFans else { return .fanless }
        guard sensorAvailable else { return .unavailable }
        guard averageRPM != nil || peakRPM != nil else { return .noHistory }
        if peakRPM == 0, averageRPM == nil || averageRPM == 0 { return .stopped }
        return .measured(averageRPM: averageRPM, peakRPM: peakRPM)
    }
}
