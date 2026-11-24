import AppKit
import SwiftUI

/// CPU 模块报表视图：包含使用率趋势（均值与峰值）、P/E 核对比图、负载分布图与右栏硬件规格。
struct ReportCpuView: View {
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

                HStack(alignment: .top, spacing: 16) {
                    peCoreCard
                    distributionCard
                }
            }
            .frame(maxWidth: .infinity)

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
                color: palette.cpu
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeak", defaultValue: "峰值使用率"),
                value: cpu?.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: cpu?.peakTime.map { ReportUIHelper.formatDateTime($0) },
                color: palette.cpuPeak
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sSys", defaultValue: "系统核心均值"),
                value: cpu?.sysAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: palette.cpuSystem
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sUser", defaultValue: "用户态均值"),
                value: cpu?.userAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: palette.cpuUser
            )
        }
    }

    // MARK: - 2. 主使用率趋势卡片

    private var usageTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.kCpu", defaultValue: "CPU 使用率趋势"),
            icon: "cpu"
        ) {
            if cache.cpuAvg.isEmpty && cache.cpuPeak.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "avg",
                            title: String(localized: "stats.r.sAvg", defaultValue: "平均"),
                            series: cache.cpuAvg,
                            color: palette.cpu,
                            lineWidth: 1.8,
                            showAreaFill: true
                        ),
                        ReportChartSeriesDescriptor(
                            id: "peak",
                            title: String(localized: "stats.r.sPeak", defaultValue: "峰值"),
                            series: cache.cpuPeak,
                            color: palette.cpuPeak,
                            lineWidth: 1.2,
                            isDashed: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .percent,
                    yDomain: 0...100,
                    yAxisValues: [0, 25, 50, 75, 100],
                    height: 240
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. P/E 核对比卡片

    private var peCoreCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.sPerfVsEff", defaultValue: "性能核与能效核"),
            icon: "square.grid.2x2"
        ) {
            if cache.cpuP.isEmpty && cache.cpuE.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.peNotSupported", defaultValue: "当前芯片或所选范围无 P/E 核心细分数据"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "pCore",
                            title: String(localized: "stats.r.sPerfCore", defaultValue: "性能核 (P)"),
                            series: cache.cpuP,
                            color: palette.pCore,
                            lineWidth: 1.6
                        ),
                        ReportChartSeriesDescriptor(
                            id: "eCore",
                            title: String(localized: "stats.r.sEffCore", defaultValue: "能效核 (E)"),
                            series: cache.cpuE,
                            color: palette.eCore,
                            lineWidth: 1.6
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .percent,
                    yDomain: 0...100,
                    yAxisValues: [0, 50, 100],
                    height: 180
                )
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
