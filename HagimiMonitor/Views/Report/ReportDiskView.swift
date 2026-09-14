import AppKit
import Charts
import SwiftUI

/// 磁盘模块报表视图：包含读写速率趋势图、每日 I/O 读写量柱状图与右栏存储硬件规格。
struct ReportDiskView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?

    private let readColor = ReportUIHelper.diskReadColor
    private let writeColor = ReportUIHelper.diskWriteColor

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行
                kpiSummaryRow

                // 2. 磁盘读写速率趋势图
                rateTrendCard

                // 3. 每日 I/O 吞吐柱状图（跨天范围时显示）
                if let daily = viewModel.rangeModel?.disk.dailyBars, daily.count > 1 {
                    dailyThroughputCard(daily: daily)
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离高频广播)
            ReportHardwareRailView(
                moduleId: "disk",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let disk = viewModel.rangeModel?.disk
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.sReadRate", defaultValue: "读取峰值"),
                value: disk?.peakReadRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: readColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sWriteRate", defaultValue: "写入峰值"),
                value: disk?.peakWriteRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: writeColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sTotalRead", defaultValue: "读取总量"),
                value: disk?.totalReadBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: readColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sTotalWrite", defaultValue: "写入总量"),
                value: disk?.totalWriteBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: writeColor
            )
        }
    }

    // MARK: - 2. 速率趋势图卡片 (R01: 累计量除以桶秒数转速率, R07: 独立分段防跨睡眠连线)

    private var rateTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60
        let bucketSec = Double(granularity)

        let readPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.diskRead,
            seriesID: "read",
            granularitySeconds: granularity,
            transform: { ReportDataAggregator.rateFromTotal(totalBytes: $0, bucketSeconds: bucketSec) }
        )
        let writePoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.diskWrite,
            seriesID: "write",
            granularitySeconds: granularity,
            transform: { ReportDataAggregator.rateFromTotal(totalBytes: $0, bucketSeconds: bucketSec) }
        )

        return ReportCardView(
            title: String(localized: "stats.r.railDisk", defaultValue: "磁盘 I/O 速率趋势"),
            icon: "internaldrive"
        ) {
            if readPoints.isEmpty && writePoints.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无磁盘采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sReadRate", defaultValue: "读取速率"), color: readColor)
                        ReportLegendItem(title: String(localized: "stats.r.sWriteRate", defaultValue: "写入速率"), color: writeColor)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows) {
                            let readRate = ReportDataAggregator.rateFromTotal(totalBytes: row.diskRead ?? 0, bucketSeconds: bucketSec)
                            let writeRate = ReportDataAggregator.rateFromTotal(totalBytes: row.diskWrite ?? 0, bucketSeconds: bucketSec)
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): 读 \(ReportUIHelper.formatBytesRate(readRate)) | 写 \(ReportUIHelper.formatBytesRate(writeRate))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(readPoints) { pt in
                            if let val = pt.value {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Rate", val / (1024 * 1024)),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(readColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        ForEach(writePoints) { pt in
                            if let val = pt.value {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Rate", val / (1024 * 1024)),
                                    series: .value("Series", "\(pt.seriesID)_\(pt.segmentID)")
                                )
                                .foregroundStyle(writeColor)
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
                                    Text(String(format: "%.1f MB/s", val))
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

    // MARK: - 3. 每日 I/O 吞吐柱状图 (R01: 累计量单位为 GB，不带 /s)

    private func dailyThroughputCard(daily: [ReportDiskMetrics.DailyBar]) -> some View {
        ReportCardView(
            title: String(localized: "stats.r.dailyDiskTitle", defaultValue: "每日 I/O 读写量"),
            icon: "chart.bar.xaxis"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    ReportLegendItem(title: String(localized: "stats.r.sTotalRead", defaultValue: "读取总量"), color: readColor)
                    ReportLegendItem(title: String(localized: "stats.r.sTotalWrite", defaultValue: "写入总量"), color: writeColor)
                }

                Chart {
                    ForEach(daily) { item in
                        let readGB = item.readBytes / (1024 * 1024 * 1024)
                        let writeGB = item.writeBytes / (1024 * 1024 * 1024)

                        BarMark(
                            x: .value("Date", item.dateText),
                            y: .value("IO", readGB)
                        )
                        .foregroundStyle(readColor)
                        .position(by: .value("Type", "Read"))

                        BarMark(
                            x: .value("Date", item.dateText),
                            y: .value("IO", writeGB)
                        )
                        .foregroundStyle(writeColor)
                        .position(by: .value("Type", "Write"))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(String(format: "%.1f GB", val))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
