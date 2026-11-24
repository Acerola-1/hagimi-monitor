import AppKit
import Charts
import SwiftUI

/// 热状态与风扇模块报表视图：包含热状态档位（0~3 档）、CPU 核心温度趋势、风扇转速及事件时间窗高亮。
struct ReportThermalView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    private var highlightWindows: [ReportChartHighlightWindow] {
        var windows: [ReportChartHighlightWindow] = (viewModel.rangeModel?.events ?? [])
            .filter { $0.kind == .thermal }
            .map { event in
                ReportChartHighlightWindow(
                    id: event.id,
                    start: event.start,
                    end: event.end,
                    tone: event.worstLevel >= 3 ? .critical : .warning,
                    label: event.kind.title
                )
            }
        if let focused = viewModel.focusedTimeWindow, focused.kind == .thermal || focused.kind == nil {
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
        VStack(spacing: 16) {
            if let focused = viewModel.focusedTimeWindow, focused.kind == .thermal || focused.kind == nil {
                ReportFocusedWindowBanner(window: focused) {
                    viewModel.clearFocusedTimeWindow()
                }
            }

            kpiSummaryRow
            cpuTempTrendCard
            thermalStateTrendCard
            fanSectionView
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 1. KPI 指标行

    private var kpiSummaryRow: some View {
        let th = viewModel.rangeModel?.thermal
        let fanReadout = ReportFanReadoutState.resolve(
            hasFans: th?.hasFans ?? false,
            sensorAvailable: th?.fanSensorAvailable ?? false,
            averageRPM: th?.fanAvgRPM,
            peakRPM: th?.fanMaxRPM
        )
        let thermalIndex = StatisticsDisplayFormat.thermalLevelIndex(th?.cpuThermalAvg)

        return HStack(spacing: 12) {
            ReportKpiCard(
                title: String(localized: "stats.r.secThermal", defaultValue: "系统热状态"),
                value: StatisticsDisplayFormat.thermalStateLabel(th?.cpuThermalAvg),
                caption: th?.cpuThermalAvg.map { level in
                    String(localized: "stats.r.thermalAverage \(String(format: "%.1f", level))")
                },
                color: palette.thermalLevelTint(thermalIndex)
            )
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgCpuTemp", defaultValue: "CPU 平均温度"),
                value: th?.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? "—",
                caption: nil,
                color: palette.thermal
            )
            fanKpiCard(for: fanReadout)
        }
    }

    @ViewBuilder
    private func fanKpiCard(for state: ReportFanReadoutState) -> some View {
        switch state {
        case .fanless:
            ReportKpiCard(
                title: String(localized: "stats.r.fanStatus"),
                value: String(localized: "stats.r.fanlessTitle"),
                caption: String(localized: "stats.r.fanlessSubtitle"),
                color: .secondary
            )
        case .unavailable:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: String(localized: "stats.r.fanUnavailableValue"),
                caption: String(localized: "stats.r.fanUnavailableCaption"),
                color: .secondary
            )
        case .noHistory:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: String(localized: "stats.r.fanNoHistoryValue"),
                caption: String(localized: "stats.r.fanNoHistoryCaption"),
                color: .secondary
            )
        case .stopped:
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: "0 RPM",
                caption: String(localized: "stats.r.fanStoppedCaption"),
                color: palette.base.severityTint(for: .calm)
            )
        case let .measured(averageRPM, peakRPM):
            ReportKpiCard(
                title: String(localized: "stats.r.sAvgFan"),
                value: averageRPM.map { String(format: "%.0f RPM", $0) } ?? "—",
                caption: peakRPM.map { String(localized: "stats.r.fanPeak \(String(format: "%.0f", $0))") },
                color: palette.fan
            )
        }
    }

    // MARK: - 2. CPU 核心温度趋势图卡片

    private var cpuTempTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.cpuTempTitle", defaultValue: "CPU 核心温度趋势"),
            icon: "thermometer.medium"
        ) {
            if cache.cpuTemp.isEmpty {
                ReportEmptyPlaceholder(
                    text: !ReportEnvironment.isDirect
                        ? String(localized: "stats.r.tempSandboxNotice", defaultValue: "受当前沙盒运行环境权限限制，无法读取核心温度传感器，请参考下方系统热状态")
                        : String(localized: "stats.r.emptySection", defaultValue: "所选范围内无温度传感器记录")
                )
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "temp",
                            title: String(localized: "stats.r.cpuTemp", defaultValue: "CPU 温度 (°C)"),
                            series: cache.cpuTemp,
                            color: palette.thermal,
                            lineWidth: 1.7
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .celsius,
                    highlightWindows: highlightWindows,
                    height: 185
                )
            }
        }
    }

    // MARK: - 3. 系统热状态历史档位图 (0~3 档阶梯插值)

    private var thermalStateTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.secThermal", defaultValue: "系统热状态档位"),
            icon: "flame"
        ) {
            if cache.thermalState.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无热状态记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "thermalState",
                            title: String(localized: "stats.r.secThermal", defaultValue: "系统热状态"),
                            series: cache.thermalState,
                            color: palette.base.severityTint(for: .warning),
                            lineWidth: 1.6,
                            showAreaFill: true,
                            interpolation: .stepEnd
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .thermalLevel,
                    yDomain: 0...3,
                    yAxisValues: [0, 1, 2, 3],
                    highlightWindows: highlightWindows,
                    height: 170
                )
            }
        }
    }

    // MARK: - 4. 风扇趋势或说明区域

    @ViewBuilder
    private var fanSectionView: some View {
        let th = viewModel.rangeModel?.thermal
        if th?.hasFans == true {
            if th?.fanSensorAvailable == false {
                fanSandboxNoticeCard
            } else {
                fanTrendCard
            }
        } else {
            fanlessNoticeCard
        }
    }

    private var fanTrendCard: some View {
        let cache = viewModel.rangeModel?.chartCache ?? .empty

        return ReportCardView(
            title: String(localized: "stats.r.fanTrendTitle", defaultValue: "风扇转速趋势"),
            icon: "fan.fill"
        ) {
            if cache.fanRPM.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.fanNoTrend"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: [
                        ReportChartSeriesDescriptor(
                            id: "fan",
                            title: String(localized: "stats.r.sAvgFan", defaultValue: "风扇转速 (RPM)"),
                            series: cache.fanRPM,
                            color: palette.fan,
                            lineWidth: 1.6
                        )
                    ],
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .rpm,
                    highlightWindows: highlightWindows,
                    height: 180
                )
            }
        }
    }

    private var fanSandboxNoticeCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.fanStatus", defaultValue: "风扇模组状态"),
            icon: "fan.fill"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text(String(localized: "stats.r.fanUnavailableDescription"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var fanlessNoticeCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.fanlessTitle", defaultValue: "被动散热设计"),
            icon: "wind"
        ) {
            HStack(spacing: 14) {
                Image(systemName: "fan.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text(String(localized: "stats.r.fanlessDesc", defaultValue: "当前设备采用全被动静音散热架构（如 MacBook Air），机身内部未搭载机械主动散热风扇。系统热状态由能效核与调度器智能管控。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

/// 将设备能力和所选时段的实测结果分开映射，缺失记录不再解释成零转速。
enum ReportFanReadoutState: Equatable {
    case fanless
    case unavailable
    case noHistory
    case stopped
    case measured(averageRPM: Double?, peakRPM: Double?)

    static func resolve(
        hasFans: Bool,
        sensorAvailable: Bool,
        averageRPM: Double?,
        peakRPM: Double?
    ) -> Self {
        guard hasFans else { return .fanless }
        guard sensorAvailable else { return .unavailable }
        guard averageRPM != nil || peakRPM != nil else { return .noHistory }
        if peakRPM == 0, averageRPM == nil || averageRPM == 0 { return .stopped }
        return .measured(averageRPM: averageRPM, peakRPM: peakRPM)
    }
}
