import AppKit
import Charts
import SwiftUI

/// 内存模块报表视图：包含内存构成趋势、系统内存压力变化、交换文件使用与右栏硬件规格。
struct ReportMemoryView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?
    @State private var selectedPressureDate: Date?

    private let memColor = ReportUIHelper.memoryColor
    private let compColor = Color(hex: 0xEC4899)
    private let pressureColor = Color(hex: 0xEF4444)
    private let swapColor = ReportUIHelper.swapColor

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行
                kpiSummaryRow

                // 2. 内存使用构成趋势 (已用与压缩内存)
                memoryUsageTrendCard

                // 3. 系统内存压力趋势 (0~100%) (R16)
                memoryPressureTrendCard

                // 4. 交换文件趋势 (R04)
                swapTrendCard
            }
            .frame(maxWidth: .infinity)

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离观察源)
            ReportHardwareRailView(
                moduleId: "memory",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let mem = viewModel.rangeModel?.memory
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgUsed", defaultValue: "平均已用"),
                value: mem?.usedAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: memColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeakUsed", defaultValue: "峰值占比"),
                value: mem?.usedPeakPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: ReportUIHelper.peakColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.kMemPressure", defaultValue: "内存压力均值"),
                value: mem?.pressureAvgPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: (mem?.pressureAvgPercent ?? 0) > 60 ? pressureColor : memColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sSwap", defaultValue: "交换文件 (Swap)"),
                value: mem?.swapAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: (mem?.swapAvgBytes ?? 0) > 1024 * 1024 * 1024 ? Color(hex: 0xFF9500) : .secondary
            )
        }
    }

    // MARK: - 2. 内存使用构成趋势 (GB)

    private var memoryUsageTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let usedPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memUsedAvg,
            seriesID: "used",
            granularitySeconds: granularity,
            transform: { $0 / (1024 * 1024 * 1024) }
        )
        let compPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memCompAvg,
            seriesID: "comp",
            granularitySeconds: granularity,
            transform: { $0 / (1024 * 1024 * 1024) }
        )

        let usedSegments = Dictionary(grouping: usedPoints, by: \.segmentID)
        let compSegments = Dictionary(grouping: compPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.kMem", defaultValue: "内存空间构成趋势"),
            icon: "memorychip"
        ) {
            if rows.isEmpty || !rows.contains(where: { $0.memUsedAvg != nil }) {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无内存采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sAvgUsed", defaultValue: "已用内存"), color: memColor)
                        ReportLegendItem(title: String(localized: "stats.r.memCompressed", defaultValue: "已压缩"), color: compColor)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows), let used = row.memUsedAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): 已用 \(ReportUIHelper.formatBytes(used)) | 压缩 \(row.memCompAvg.map { ReportUIHelper.formatBytes($0) } ?? "—")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        // 1. 已用内存
                        ForEach(Array(usedSegments.keys.sorted()), id: \.self) { seg in
                            let points = usedSegments[seg] ?? []
                            ForEach(points) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Used", pt.value ?? 0),
                                    series: .value("Series", "used-\(seg)")
                                )
                                .foregroundStyle(memColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 2. 压缩内存
                        ForEach(Array(compSegments.keys.sorted()), id: \.self) { seg in
                            let points = compSegments[seg] ?? []
                            ForEach(points) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Comp", pt.value ?? 0),
                                    series: .value("Series", "comp-\(seg)")
                                )
                                .foregroundStyle(compColor)
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
                        AxisMarks(position: .leading) { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel {
                                if let gb = val.as(Double.self) {
                                    Text(String(format: "%.0f GB", gb))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 200)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 系统内存压力趋势 (0~100%) (R16)

    private var memoryPressureTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let pressurePoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memPressureAvg,
            seriesID: "pressure",
            granularitySeconds: granularity
        )
        let pressureSegments = Dictionary(grouping: pressurePoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.dimPressure", defaultValue: "系统内存压力趋势"),
            icon: "speedometer"
        ) {
            if rows.isEmpty || !rows.contains(where: { $0.memPressureAvg != nil }) {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无内存压力记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.dimPressure", defaultValue: "内存压力"), color: pressureColor)
                        Spacer()

                        if let selectedPressureDate, let row = ReportUIHelper.findClosestRow(to: selectedPressureDate, in: rows), let p = row.memPressureAvg {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): 压力 \(String(format: "%.1f%%", p))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(Array(pressureSegments.keys.sorted()), id: \.self) { seg in
                            let points = pressureSegments[seg] ?? []
                            ForEach(points) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Pressure", pt.value ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [pressureColor.opacity(0.30), pressureColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Pressure", pt.value ?? 0),
                                    series: .value("Series", "pressure-\(seg)")
                                )
                                .foregroundStyle(pressureColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 60% 警戒参考线
                        RuleMark(y: .value("Warning", 60.0))
                            .foregroundStyle(Color(hex: 0xFF9500).opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        if let selectedPressureDate {
                            RuleMark(x: .value("Selected", selectedPressureDate))
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
                    .chartXSelection(value: $selectedPressureDate)
                    .frame(height: 180)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 交换文件趋势 (R04: 区分 0 与 nil)

    private var swapTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let hasSwapData = viewModel.rangeModel?.memory.hasSwapData ?? false
        let swapAvg = viewModel.rangeModel?.memory.swapAvgBytes ?? 0.0
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let swapPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memSwapAvg,
            seriesID: "swap",
            granularitySeconds: granularity,
            transform: { $0 / (1024 * 1024) }
        )
        let swapSegments = Dictionary(grouping: swapPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.sSwap", defaultValue: "交换分区 (Swap) 趋势"),
            icon: "arrow.triangle.2.circlepath"
        ) {
            if !hasSwapData || rows.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.noSwapData", defaultValue: "所选范围内无交换分区采样数据"))
            } else if swapAvg == 0.0 && swapPoints.allSatisfy({ ($0.value ?? 0) == 0 }) {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(hex: 0x34C759))
                        Text(String(localized: "stats.r.swapZero", defaultValue: "所选范围内未产生交换分区（0 MB）"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ReportLegendItem(title: String(localized: "stats.r.sSwap", defaultValue: "Swap 占用"), color: swapColor)
                        Spacer()
                    }

                    Chart {
                        ForEach(Array(swapSegments.keys.sorted()), id: \.self) { seg in
                            let points = swapSegments[seg] ?? []
                            ForEach(points) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Swap", pt.value ?? 0)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [swapColor.opacity(0.35), swapColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Swap", pt.value ?? 0),
                                    series: .value("Series", "swap-\(seg)")
                                )
                                .foregroundStyle(swapColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                                .interpolationMethod(.monotone)
                            }
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
                    .frame(height: 180)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
