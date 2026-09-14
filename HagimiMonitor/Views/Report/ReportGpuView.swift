import AppKit
import Charts
import SwiftUI

/// GPU 模块报表视图：包含 GPU 使用率趋势（均值与逐桶峰值）、显存使用历史、负载分布与右栏硬件规格。
struct ReportGpuView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?
    @State private var selectedVramDate: Date?

    private let gpuColor = ReportUIHelper.gpuColor
    private let peakColor = ReportUIHelper.peakColor
    private let vramColor = Color(hex: 0x8B5CF6)

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行
                kpiSummaryRow

                // 2. 主 GPU 使用率趋势图（均值与逐桶峰值折线）
                usageTrendCard

                // 3. 显存使用历史趋势图 (R16)
                vramHistoryCard

                // 4. 负载分布统计
                distributionCard
            }
            .frame(maxWidth: .infinity)

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离观察源)
            ReportHardwareRailView(
                moduleId: "gpu",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let gpu = viewModel.rangeModel?.gpu
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.sAvg", defaultValue: "平均使用率"),
                value: gpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: gpuColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeak", defaultValue: "峰值使用率"),
                value: gpu?.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: peakColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.gpuMem", defaultValue: "动态显存均值"),
                value: gpu?.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: vramColor
            )
        }
    }

    // MARK: - 2. 主使用率趋势卡片 (R16: 逐桶峰值曲线，R07: 缺口断开)

    private var usageTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let avgPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.gpuAvg,
            seriesID: "avg",
            granularitySeconds: granularity
        )
        let peakPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.gpuMax,
            seriesID: "peak",
            granularitySeconds: granularity
        )

        let avgSegments = Dictionary(grouping: avgPoints, by: \.segmentID)
        let peakSegments = Dictionary(grouping: peakPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.kGpu", defaultValue: "GPU 使用率趋势"),
            icon: "display"
        ) {
            if rows.isEmpty || !rows.contains(where: { $0.gpuAvg != nil }) {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无 GPU 采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sAvg", defaultValue: "平均"), color: gpuColor, isDashed: false)
                        ReportLegendItem(title: String(localized: "stats.r.sPeak", defaultValue: "峰值"), color: peakColor, isDashed: true)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows), let usage = row.gpuAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): GPU \(String(format: "%.1f%%", usage)) | 峰值 \(row.gpuMax.map { String(format: "%.1f%%", $0) } ?? "—")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        // 1. 均值线与面积
                        ForEach(Array(avgSegments.keys.sorted()), id: \.self) { seg in
                            let points = avgSegments[seg] ?? []
                            ForEach(points) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("GPU", pt.value ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [gpuColor.opacity(0.30), gpuColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("GPU", pt.value ?? 0),
                                    series: .value("Series", "avg-\(seg)")
                                )
                                .foregroundStyle(gpuColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 2. 逐桶峰值折线 (R16)
                        ForEach(Array(peakSegments.keys.sorted()), id: \.self) { seg in
                            let points = peakSegments[seg] ?? []
                            ForEach(points) { pt in
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
                    .frame(height: 220)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 显存使用历史趋势图 (R16)

    private var vramHistoryCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let hasVram = rows.contains { ($0.gpuMemAvg ?? 0) > 0 }
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let vramPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.gpuMemAvg,
            seriesID: "vram",
            granularitySeconds: granularity
        )
        let vramSegments = Dictionary(grouping: vramPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.sGpuMem", defaultValue: "显存占用趋势"),
            icon: "memorychip"
        ) {
            if !hasVram || rows.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无动态显存历史记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ReportLegendItem(title: String(localized: "stats.r.gpuMem", defaultValue: "动态显存"), color: vramColor)
                        Spacer()
                        if let selectedVramDate, let row = ReportUIHelper.findClosestRow(to: selectedVramDate, in: rows), let vram = row.gpuMemAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): \(ReportUIHelper.formatBytes(vram))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(Array(vramSegments.keys.sorted()), id: \.self) { seg in
                            let points = vramSegments[seg] ?? []
                            ForEach(points) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("VRAM", (pt.value ?? 0) / (1024 * 1024))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [vramColor.opacity(0.30), vramColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("VRAM", (pt.value ?? 0) / (1024 * 1024)),
                                    series: .value("Series", "vram-\(seg)")
                                )
                                .foregroundStyle(vramColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedVramDate {
                            RuleMark(x: .value("Selected", selectedVramDate))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel {
                                if let mb = val.as(Double.self) {
                                    Text(ReportUIHelper.formatBytes(mb * 1024 * 1024))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedVramDate)
                    .frame(height: 180)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 负载分布统计卡片

    private var distributionCard: some View {
        ReportLoadDistributionCard(
            distribution: viewModel.rangeModel?.gpu.distribution,
            title: String(localized: "stats.r.sLoadDist", defaultValue: "负载区间分布")
        )
    }
}
