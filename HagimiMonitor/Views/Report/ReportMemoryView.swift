import AppKit
import SwiftUI

/// 内存模块报表视图：包含内存构成趋势、系统内存压力变化（含事件区间高亮）、交换文件使用与右栏硬件规格。
struct ReportMemoryView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    private var highlightWindows: [ReportChartHighlightWindow] {
        var windows: [ReportChartHighlightWindow] = (viewModel.rangeModel?.events ?? [])
            .filter { $0.kind == .memory }
            .map { event in
                ReportChartHighlightWindow(
                    id: event.id,
                    start: event.start,
                    end: event.end,
                    tone: event.worstLevel >= 2 ? .critical : .warning,
                    label: event.kind.title
                )
            }
        if let focused = viewModel.focusedTimeWindow, focused.kind == .memory || focused.kind == nil {
            windows.append(ReportChartHighlightWindow(
                id: "focus",
                start: focused.start,
                end: focused.end,
                tone: .focus,
                label: focused.title
            ))
        }
        return windows
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 16) {
                if let focused = viewModel.focusedTimeWindow, focused.kind == .memory || focused.kind == nil {
                    ReportFocusedWindowBanner(window: focused) {
                        viewModel.clearFocusedTimeWindow()
                    }
                }

                kpiSummaryRow
                memoryUsageTrendCard
                memoryPressureTrendCard
                swapTrendCard
            }
            .frame(maxWidth: .infinity)

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
                color: palette.memory
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sPeakUsed", defaultValue: "峰值占比"),
                value: mem?.usedPeakPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: palette.cpuPeak
            )
            ReportKpiCard(
                title: String(localized: "stats.r.kMemPressure", defaultValue: "内存压力均值"),
                value: mem?.pressureAvgPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                caption: nil,
                color: (mem?.pressureAvgPercent ?? 0) > 60 ? palette.memoryPressure : palette.memory
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sSwap", defaultValue: "交换文件 (Swap)"),
                value: mem?.swapAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—",
                caption: nil,
                color: (mem?.swapAvgBytes ?? 0) > 1024 * 1024 * 1024 ? palette.base.severityTint(for: .warning) : .secondary
            )
        }
    }

    // MARK: - 2. 内存使用构成趋势

    private var memoryUsageTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.kMem", defaultValue: "内存空间构成趋势"),
            icon: "memorychip"
        ) {
            if cache.memUsedGB.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无内存采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "used",
                            title: String(localized: "stats.r.sAvgUsed", defaultValue: "已用内存"),
                            series: cache.memUsedGB,
                            color: palette.memory,
                            lineWidth: 1.8
                        ),
                        ReportChartSeriesDescriptor(
                            id: "comp",
                            title: String(localized: "stats.r.memCompressed", defaultValue: "已压缩"),
                            series: cache.memCompressedGB,
                            color: palette.memoryCompressed,
                            lineWidth: 1.5
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .binaryGiB,
                    highlightWindows: highlightWindows,
                    height: 200
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 系统内存压力趋势 (0~100%)

    private var memoryPressureTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.dimPressure", defaultValue: "系统内存压力趋势"),
            icon: "speedometer"
        ) {
            if cache.memPressure.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无内存压力记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "pressure",
                            title: String(localized: "stats.r.dimPressure", defaultValue: "内存压力"),
                            series: cache.memPressure,
                            color: palette.memoryPressure,
                            lineWidth: 1.6,
                            showAreaFill: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .percent,
                    yDomain: 0...100,
                    yAxisValues: [0, 25, 50, 75, 100],
                    highlightWindows: highlightWindows,
                    referenceLine: (value: 60.0, color: palette.base.severityTint(for: .warning)),
                    height: 180
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 交换文件趋势 (区分 0 与 nil)

    private var swapTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty
        let hasSwapData = viewModel.rangeModel?.memory.hasSwapData ?? false
        let swapAvg = viewModel.rangeModel?.memory.swapAvgBytes ?? 0.0
        let allZero = cache.memSwapMB.segments.allSatisfy { seg in seg.allSatisfy { ($0.value ?? 0) == 0 } }

        return ReportCardView(
            title: String(localized: "stats.r.sSwap", defaultValue: "交换分区 (Swap) 趋势"),
            icon: "arrow.triangle.2.circlepath"
        ) {
            if !hasSwapData || cache.memSwapMB.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.noSwapData", defaultValue: "所选范围内无交换分区采样数据"))
            } else if swapAvg == 0.0 && allZero {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(palette.base.severityTint(for: .calm))
                        Text(String(localized: "stats.r.swapZero", defaultValue: "所选范围内未产生交换分区（0 MB）"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(minHeight: 120)
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "swap",
                            title: String(localized: "stats.r.sSwap", defaultValue: "Swap 占用"),
                            series: cache.memSwapMB,
                            color: palette.memorySwap,
                            lineWidth: 1.6,
                            showAreaFill: true
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .binaryMiB,
                    highlightWindows: highlightWindows,
                    height: 180
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}
