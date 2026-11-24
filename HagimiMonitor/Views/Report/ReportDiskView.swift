import AppKit
import SwiftUI

/// 磁盘模块报表视图：包含读写速率趋势图、每日/每小时 I/O 读写量柱状图与右栏存储硬件规格。
struct ReportDiskView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 16) {
                kpiSummaryRow
                rateTrendCard

                if let daily = viewModel.rangeModel?.disk.dailyBars, !daily.isEmpty {
                    dailyThroughputCard(daily: daily)
                }
            }
            .frame(maxWidth: .infinity)

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
                color: palette.diskRead
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sWriteRate", defaultValue: "写入峰值"),
                value: disk?.peakWriteRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: palette.diskWrite
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sTotalRead", defaultValue: "读取总量"),
                value: disk?.totalReadBytes.map { ReportUIHelper.formatVolume($0) } ?? "—",
                caption: nil,
                color: palette.diskRead
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sTotalWrite", defaultValue: "写入总量"),
                value: disk?.totalWriteBytes.map { ReportUIHelper.formatVolume($0) } ?? "—",
                caption: nil,
                color: palette.diskWrite
            )
        }
    }

    // MARK: - 2. 速率趋势图卡片

    private var rateTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.railDisk", defaultValue: "磁盘 I/O 速率趋势"),
            icon: "internaldrive"
        ) {
            if cache.diskReadMBps.isEmpty && cache.diskWriteMBps.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无磁盘采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "read",
                            title: String(localized: "stats.r.sReadRate", defaultValue: "读取速率"),
                            series: cache.diskReadMBps,
                            color: palette.diskRead,
                            lineWidth: 1.7
                        ),
                        ReportChartSeriesDescriptor(
                            id: "write",
                            title: String(localized: "stats.r.sWriteRate", defaultValue: "写入速率"),
                            series: cache.diskWriteMBps,
                            color: palette.diskWrite,
                            lineWidth: 1.5
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .decimalMBps,
                    height: 220
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. I/O 吞吐柱状图

    private func dailyThroughputCard(daily: [ReportDiskMetrics.DailyBar]) -> some View {
        let isHourly = viewModel.rangeModel?.disk.isHourly ?? viewModel.isSingleDaySelected
        let title = isHourly
            ? String(localized: "stats.r.hourlyDiskTitle", defaultValue: "每小时 I/O 读写量")
            : String(localized: "stats.r.dailyDiskTitle", defaultValue: "每日 I/O 读写量")

        return ReportCardView(
            title: title,
            icon: "chart.bar.xaxis"
        ) {
            ReportVolumeBarChart(
                items: daily.map {
                    ReportVolumeBarChart.BarItem(
                        id: $0.id,
                        label: $0.dateText,
                        primaryBytes: $0.readBytes,
                        secondaryBytes: $0.writeBytes
                    )
                },
                primaryLabel: String(localized: "stats.r.sTotalRead", defaultValue: "读取总量"),
                secondaryLabel: String(localized: "stats.r.sTotalWrite", defaultValue: "写入总量"),
                primaryColor: palette.diskRead,
                secondaryColor: palette.diskWrite,
                height: 180
            )
        }
        .frame(maxWidth: .infinity)
    }
}
