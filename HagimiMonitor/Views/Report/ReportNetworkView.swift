import AppKit
import SwiftUI

/// 网络模块报表视图：包含上下行速率趋势、每小时/每日总吞吐柱状图、沙盒渠道提示与右栏硬件规格。
struct ReportNetworkView: View {
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
                speedTrendCard
                dailyThroughputCard

                if !ReportEnvironment.isDirect {
                    sandboxNoticeCard
                }
            }
            .frame(maxWidth: .infinity)

            ReportHardwareRailView(
                moduleId: "network",
                meta: viewModel.snapshot?.meta,
                hardware: viewModel.snapshot?.hardware,
                liveSource: viewModel.liveSource
            )
        }
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let net = viewModel.rangeModel?.network
        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.kNetDown", defaultValue: "下载总流量"),
                value: net?.totalDownBytes.map { ReportUIHelper.formatVolume($0) } ?? "—",
                caption: net?.peakDownRate.map { String(localized: "report.ui.peakPrefix", defaultValue: "峰 ") + ReportUIHelper.formatBytesRate($0) },
                color: palette.networkDown
            )
            ReportKpiCard(
                title: String(localized: "stats.r.kNetUp", defaultValue: "上传总流量"),
                value: net?.totalUpBytes.map { ReportUIHelper.formatVolume($0) } ?? "—",
                caption: net?.peakUpRate.map { String(localized: "report.ui.peakPrefix", defaultValue: "峰 ") + ReportUIHelper.formatBytesRate($0) },
                color: palette.networkUp
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sDownPeak", defaultValue: "下行峰值速率"),
                value: net?.peakDownRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: palette.networkDown
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sUpPeak", defaultValue: "上行峰值速率"),
                value: net?.peakUpRate.map { ReportUIHelper.formatBytesRate($0) } ?? "—",
                caption: nil,
                color: palette.networkUp
            )
        }
    }

    // MARK: - 2. 主网络速率趋势卡片

    private var speedTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.railNet", defaultValue: "网络流量速率趋势"),
            icon: "network"
        ) {
            if cache.netDownMBps.isEmpty && cache.netUpMBps.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无网络采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "down",
                            title: String(localized: "stats.r.sDownRate", defaultValue: "下载速率"),
                            series: cache.netDownMBps,
                            color: palette.networkDown,
                            lineWidth: 1.8,
                            showAreaFill: true
                        ),
                        ReportChartSeriesDescriptor(
                            id: "up",
                            title: String(localized: "stats.r.sUpRate", defaultValue: "上传速率"),
                            series: cache.netUpMBps,
                            color: palette.networkUp,
                            lineWidth: 1.4
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

    // MARK: - 3. 流量吞吐柱状图

    private var dailyThroughputCard: some View {
        let bars = viewModel.rangeModel?.network.dailyBars ?? []
        let isHourly = viewModel.rangeModel?.network.isHourly ?? viewModel.isSingleDaySelected
        let cardTitle = isHourly
            ? String(localized: "stats.r.sHourlyNet", defaultValue: "每小时流量吞吐")
            : String(localized: "stats.r.sDailyNet", defaultValue: "每日流量吞吐")

        return ReportCardView(
            title: cardTitle,
            icon: "chart.bar.fill"
        ) {
            if bars.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.noThroughputData", defaultValue: "所选范围内暂无流量吞吐数据"))
            } else {
                ReportVolumeBarChart(
                    items: bars.map {
                        ReportVolumeBarChart.BarItem(
                            id: $0.id,
                            label: $0.dateText,
                            primaryBytes: $0.downBytes,
                            secondaryBytes: $0.upBytes
                        )
                    },
                    primaryLabel: String(localized: "stats.r.sDownVol", defaultValue: "下载量"),
                    secondaryLabel: String(localized: "stats.r.sUpVol", defaultValue: "上传量"),
                    primaryColor: palette.networkDown,
                    secondaryColor: palette.networkUp,
                    height: 180
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 沙盒运行环境说明

    private var sandboxNoticeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 16))
                .foregroundStyle(palette.networkDown)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "stats.r.sandboxNetTitle", defaultValue: "系统沙盒环境提示"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "stats.r.sandboxNetDesc", defaultValue: "受当前沙盒运行环境权限限制，网络统计仅记录全局网络接口总流量，未细分单个应用的网络归属。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 0.75)
        }
    }
}
