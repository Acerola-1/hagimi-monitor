import AppKit
import SwiftUI

/// GPU 模块报表视图：包含 GPU 使用率趋势（均值与逐桶峰值）、显存使用历史、负载分布与右栏硬件规格。
struct ReportGpuView: View {
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
                usageTrendCard
                vramHistoryCard
                distributionCard
            }
            .frame(maxWidth: .infinity)

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
                color: palette.gpu
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeak", defaultValue: "峰值使用率"),
                value: gpu?.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: palette.cpuPeak
            )
            ReportKpiCard(
                title: String(localized: "stats.r.gpuMem", defaultValue: "动态显存均值"),
                value: gpu?.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: palette.gpuVram
            )
        }
    }

    // MARK: - 2. 主使用率趋势卡片

    private var usageTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.kGpu", defaultValue: "GPU 使用率趋势"),
            icon: "display"
        ) {
            if cache.gpuAvg.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无 GPU 采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "avg",
                            title: String(localized: "stats.r.sAvg", defaultValue: "平均"),
                            series: cache.gpuAvg,
                            color: palette.gpu,
                            lineWidth: 1.8,
                            showAreaFill: true
                        ),
                        ReportChartSeriesDescriptor(
                            id: "peak",
                            title: String(localized: "stats.r.sPeak", defaultValue: "峰值"),
                            series: cache.gpuPeak,
                            color: palette.cpuPeak,
                            lineWidth: 1.2,
                            isDashed: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .percent,
                    yDomain: 0...100,
                    yAxisValues: [0, 25, 50, 75, 100],
                    height: 220
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 显存使用历史趋势图

    private var vramHistoryCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.sGpuMem", defaultValue: "显存占用趋势"),
            icon: "memorychip"
        ) {
            if cache.gpuVramMB.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无动态显存历史记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "vram",
                            title: String(localized: "stats.r.gpuMem", defaultValue: "动态显存"),
                            series: cache.gpuVramMB,
                            color: palette.gpuVram,
                            lineWidth: 1.6,
                            showAreaFill: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .binaryMiB,
                    height: 180
                )
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
