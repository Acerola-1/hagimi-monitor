import AppKit
import Charts
import SwiftUI

/// 网络模块报表视图：包含上下行速率趋势、每日总吞吐柱状图、沙盒渠道提示与右栏硬件规格。
struct ReportNetworkView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?

    private let downColor = ReportUIHelper.networkDownColor
    private let upColor = ReportUIHelper.networkUpColor

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧主要图表与指标区
            VStack(spacing: 16) {
                // 1. KPI 概览指标行 (R01: 区分累计量与速率)
                kpiSummaryRow

                // 2. 网络速率趋势图 (R01: 桶总字节 / 桶秒数 计算真实速率)
                speedTrendCard

                // 3. 每日网络吞吐柱状图 (累计量，非 /s)
                dailyThroughputCard

                // 4. 沙盒渠道限制说明卡片（若当前为 App Store 沙盒版）
                if !StandaloneHTMLReportExporter.isDirect {
                    sandboxNoticeCard
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧硬件规格与实时读数侧栏 (R09: 隔离观察源)
            ReportHardwareRailView(
                moduleId: "network",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行 (R01: 准确标注累计量与峰值速率)

    private var kpiSummaryRow: some View {
        let net = viewModel.rangeModel?.network
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.kNetDown", defaultValue: "下载总流量"),
                value: net?.totalDownBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: net?.peakDownRate.map { "峰 " + ReportUIHelper.formatBytesRate($0) },
                color: downColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.kNetUp", defaultValue: "上传总流量"),
                value: net?.totalUpBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: net?.peakUpRate.map { "峰 " + ReportUIHelper.formatBytesRate($0) },
                color: upColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sDownPeak", defaultValue: "下行峰值速率"),
                value: net?.peakDownRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: downColor
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sUpPeak", defaultValue: "上行峰值速率"),
                value: net?.peakUpRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: upColor
            )
        }
    }

    // MARK: - 2. 主网络速率趋势卡片 (R01: rateFromTotal = total / bucketSeconds)

    private var speedTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let bucketSec = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        // 速率转换为 Bytes/s，绘制时转为 MB/s
        let downPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.netDown,
            seriesID: "down",
            granularitySeconds: bucketSec,
            transform: { ReportDataAggregator.rateFromTotal(totalBytes: $0, bucketSeconds: bucketSec) }
        )
        let upPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.netUp,
            seriesID: "up",
            granularitySeconds: bucketSec,
            transform: { ReportDataAggregator.rateFromTotal(totalBytes: $0, bucketSeconds: bucketSec) }
        )

        let downSegments = Dictionary(grouping: downPoints, by: \.segmentID)
        let upSegments = Dictionary(grouping: upPoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.railNet", defaultValue: "网络流量速率趋势"),
            icon: "network"
        ) {
            if rows.isEmpty || (downPoints.isEmpty && upPoints.isEmpty) {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无网络采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sDownRate", defaultValue: "下载速率"), color: downColor)
                        ReportLegendItem(title: String(localized: "stats.r.sUpRate", defaultValue: "上传速率"), color: upColor)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows) {
                            let downRate = ReportDataAggregator.rateFromTotal(totalBytes: row.netDown ?? 0, bucketSeconds: bucketSec)
                            let upRate = ReportDataAggregator.rateFromTotal(totalBytes: row.netUp ?? 0, bucketSeconds: bucketSec)
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): ↓ \(ReportUIHelper.formatBytesRate(downRate)) | ↑ \(ReportUIHelper.formatBytesRate(upRate))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        // 1. 下行速率
                        ForEach(Array(downSegments.keys.sorted()), id: \.self) { seg in
                            let points = downSegments[seg] ?? []
                            ForEach(points) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Down", (pt.value ?? 0) / (1024 * 1024))
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [downColor.opacity(0.30), downColor.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Down", (pt.value ?? 0) / (1024 * 1024)),
                                    series: .value("Series", "down-\(seg)")
                                )
                                .foregroundStyle(downColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.8))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 2. 上行速率
                        ForEach(Array(upSegments.keys.sorted()), id: \.self) { seg in
                            let points = upSegments[seg] ?? []
                            ForEach(points) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Up", (pt.value ?? 0) / (1024 * 1024)),
                                    series: .value("Series", "up-\(seg)")
                                )
                                .foregroundStyle(upColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.4))
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
                                if let mb = val.as(Double.self) {
                                    Text(ReportUIHelper.formatBytesRate(mb * 1024 * 1024))
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

    // MARK: - 3. 每日吞吐量柱状图 (累计量，单位为字节)

    private var dailyThroughputCard: some View {
        let bars = viewModel.rangeModel?.network.dailyBars ?? []

        return ReportCardView(
            title: String(localized: "stats.r.sDailyNet", defaultValue: "每日流量吞吐"),
            icon: "chart.bar.fill"
        ) {
            if bars.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.singleDayNoBars", defaultValue: "单日范围内无需跨日吞吐柱状对比"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sDownRate", defaultValue: "下载"), color: downColor)
                        ReportLegendItem(title: String(localized: "stats.r.sUpRate", defaultValue: "上传"), color: upColor)
                        Spacer()
                    }

                    Chart {
                        ForEach(bars) { bar in
                            BarMark(
                                x: .value("Date", bar.dateText),
                                y: .value("Bytes", bar.downBytes)
                            )
                            .foregroundStyle(downColor)

                            BarMark(
                                x: .value("Date", bar.dateText),
                                y: .value("Bytes", bar.upBytes)
                            )
                            .foregroundStyle(upColor)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { val in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.secondary.opacity(0.15))
                            AxisValueLabel {
                                if let bytes = val.as(Double.self) {
                                    Text(ReportUIHelper.formatBytes(bytes))
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

    // MARK: - 4. 沙盒渠道限制提示

    private var sandboxNoticeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: 0x0EA5E9))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "stats.r.sandboxNetTitle", defaultValue: "系统沙盒环境提示"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "stats.r.sandboxNetDesc", defaultValue: "当前版本受系统沙盒保护，网络流量统计仅包含全局网络接口总量，进程级网络归属需 Direct 版本支持。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
