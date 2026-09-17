import AppKit
import Charts
import SwiftUI

/// CPU 模块报表视图：包含使用率趋势（均值与峰值）、P/E 核堆叠图、负载分布图与右栏硬件规格。
struct ReportCpuView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?

    private let cpuColor = ReportUIHelper.cpuColor
    private let peakColor = ReportUIHelper.peakColor
    private let pCoreColor = ReportUIHelper.cpuColor
    private let eCoreColor = Color(hex: 0x4A90E2)

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行
                kpiSummaryRow

                // 2. 主使用率趋势图
                usageTrendCard

                // 3. 并列子卡：P/E 核占用对比 与 负载分布统计
                HStack(alignment: .top, spacing: 16) {
                    peCoreCard
                    distributionCard
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离观察源)
            ReportHardwareRailView(
                moduleId: "cpu",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let cpu = viewModel.rangeModel?.cpu
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.sAvg", defaultValue: "平均使用率"),
                value: cpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: cpuColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeak", defaultValue: "峰值使用率"),
                value: cpu?.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: cpu?.peakTime.map { ReportUIHelper.formatDateTime($0) },
                color: peakColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sSys", defaultValue: "系统核心均值"),
                value: cpu?.sysAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: Color(hex: 0x64748B)
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sUser", defaultValue: "用户态均值"),
                value: cpu?.userAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: Color(hex: 0x38BDF8)
            )
        }
    }

    // MARK: - 2. 主使用率趋势卡片 (R07: 独立系列与缺口断开)

    private var usageTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let avgPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuAvg,
            seriesID: "avg",
            granularitySeconds: granularity
        )
        let peakPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuMax,
            seriesID: "peak",
            granularitySeconds: granularity
        )

        let avgSegments = Dictionary(grouping: avgPoints, by: \.segmentID)
        let peakSegments = Dictionary(grouping: peakPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.kCpu", defaultValue: "CPU 使用率趋势"),
            icon: "cpu"
        ) {
            if rows.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // 图例与悬停读数
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sAvg", defaultValue: "平均"), color: cpuColor, isDashed: false)
                        ReportLegendItem(title: String(localized: "stats.r.sPeak", defaultValue: "峰值"), color: peakColor, isDashed: true)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows) {
                            HStack(spacing: 8) {
                                Text(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t))))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if let avg = row.cpuAvg {
                                    Text("\(String(format: "%.1f%%", avg))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(cpuColor)
                                }
                                if let max = row.cpuMax {
                                    Text("(Max: \(String(format: "%.1f%%", max)))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(peakColor)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    // 趋势图表
                    Chart {
                        // 1. 均值线与渐变面积（按 segmentID 断开缺口）
                        ForEach(Array(avgSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = avgSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("CPU", pt.value ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [cpuColor.opacity(0.30), cpuColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("CPU", pt.value ?? 0),
                                    series: .value("Series", "avg-\(seg)")
                                )
                                .foregroundStyle(cpuColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 2. 峰值虚线（按 segmentID 断开缺口，独立 series 避免竖线连接）
                        ForEach(Array(peakSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = peakSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Peak", pt.value ?? 0),
                                    series: .value("Series", "peak-\(seg)")
                                )
                                .foregroundStyle(peakColor.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedDate {
                            RuleMark(x: .value("Selected", selectedDate))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { val in
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
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 240)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. P/E 核对比卡片

    private var peCoreCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let hasPE = rows.contains { ($0.cpuPAvg ?? 0) > 0 || ($0.cpuEAvg ?? 0) > 0 }
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let pPoints = ReportDataAggregator.buildTimeSeries(rows: rows, keyPath: \.cpuPAvg, seriesID: "p", granularitySeconds: granularity)
        let ePoints = ReportDataAggregator.buildTimeSeries(rows: rows, keyPath: \.cpuEAvg, seriesID: "e", granularitySeconds: granularity)
        let pSegments = Dictionary(grouping: pPoints, by: \.segmentID)
        let eSegments = Dictionary(grouping: ePoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.sPerfVsEff", defaultValue: "性能核与能效核"),
            icon: "square.grid.2x2"
        ) {
            if !hasPE || rows.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.peNotSupported", defaultValue: "当前芯片或所选范围无 P/E 核心细分数据"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sPerfCore", defaultValue: "性能核 (P)"), color: pCoreColor, isDashed: false)
                        ReportLegendItem(title: String(localized: "stats.r.sEffCore", defaultValue: "能效核 (E)"), color: eCoreColor, isDashed: false)
                        Spacer()
                    }

                    Chart {
                        ForEach(Array(pSegments.keys.sorted()), id: \.self) { seg in
                            let points = pSegments[seg] ?? []
                            ForEach(points) { pt in
                                LineMark(x: .value("Time", pt.date), y: .value("P-Core", pt.value ?? 0), series: .value("Series", "p-\(seg)"))
                                    .foregroundStyle(pCoreColor)
                                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                                    .interpolationMethod(.monotone)
                            }
                        }
                        ForEach(Array(eSegments.keys.sorted()), id: \.self) { seg in
                            let points = eSegments[seg] ?? []
                            ForEach(points) { pt in
                                LineMark(x: .value("Time", pt.date), y: .value("E-Core", pt.value ?? 0), series: .value("Series", "e-\(seg)"))
                                    .foregroundStyle(eCoreColor)
                                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { val in
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
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 负载分布统计卡片

    private var distributionCard: some View {
        ReportLoadDistributionCard(
            distribution: viewModel.rangeModel?.cpu.distribution,
            title: String(localized: "stats.r.sLoadDist", defaultValue: "负载区间分布")
        )
    }
}
