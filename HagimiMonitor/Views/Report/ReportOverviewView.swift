import AppKit
import Charts
import SwiftUI

/// 报表概览视图：包含时段结论、状态评分与完整度、核心用量总览、综合趋势图及 7×24 活动热力图。
struct ReportOverviewView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var showScoreBasis = false
    /// 趋势视图模式：默认只看 CPU/GPU 两条负载曲线，内存单独切换查看。
    @State private var trendMode: TrendMode = .load
    /// 高密度分钟曲线是否启用平滑降噪（默认开启以消除 1440 点高频锯齿）。
    @State private var smoothDenseTrend = true

    enum TrendMode: String, CaseIterable, Identifiable {
        case load
        case memory

        var id: String { rawValue }

        var label: String {
            switch self {
            case .load: return String(localized: "stats.report.trend.load", defaultValue: "负载")
            case .memory: return String(localized: "stats.report.trend.memory", defaultValue: "内存")
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            overviewHeading
            ongoingPressureBanner
            healthScoreSummary
            resourceGrid(primary: true)
            compositeTrendCard
            resourceGrid(primary: false)
            if let heatmap = viewModel.rangeModel?.heatmap,
               !heatmap.cells.isEmpty, viewModel.rangeModel?.range != .today {
                heatmapCard(heatmap: heatmap)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 头部与结论横幅

    private var overviewHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("report.ui.overview")
                    .font(.largeTitle.weight(.bold))
                if let model = viewModel.rangeModel {
                    Text(model.from.formatted(date: .abbreviated, time: .shortened)
                         + " – " + model.to.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.isAggregating {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(Text("report.ui.updating"))
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("report.ui.historical")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let capturedAt = viewModel.rangeModel?.updatedAt {
                    Text(String(
                        format: String(localized: "stats.report.snapshotAt"),
                        capturedAt.formatted(date: .abbreviated, time: .shortened)
                    ))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// 仅当此刻存在尚未恢复的持续压力（`state == .ongoing`）时展示紧凑提醒条；
    /// 历史已恢复事件与常规统计不再在页顶挂常驻警告横幅，避免制造持续焦虑。
    @ViewBuilder
    private var ongoingPressureBanner: some View {
        let ongoingEvents = (viewModel.rangeModel?.events ?? []).filter { $0.state == .ongoing }
        if let primary = ongoingEvents.sorted(by: { $0.worstLevel > $1.worstLevel }).first {
            let severity: MonitorSeverity = primary.worstLevel >= 2 ? .critical : .warning
            let tint = palette.base.severityTint(for: severity)
            let kindLabel = primary.kind == .memory
                ? String(localized: "stats.r.alertMem", defaultValue: "内存压力")
                : String(localized: "stats.r.alertThermal", defaultValue: "热压力")
            let durationText = StatisticsDisplayFormat.duration(primary.pressureSeconds)

            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                Text(String(
                    format: String(localized: "stats.r.overview.ongoingBanner", defaultValue: "当前%@持续中 · 已持续 %@"),
                    kindLabel,
                    durationText
                ))
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

                if let topApp = primaryConsumerApp(preferMemory: primary.kind == .memory) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(
                        format: String(localized: "stats.r.overview.topConsumer", defaultValue: "主要占用 %@"),
                        topApp.name
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    viewModel.focusOnEvent(primary)
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "stats.r.overview.locateEvent", defaultValue: "定位查看"))
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                palette.bannerFill(isElevated: true),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(palette.bannerBorder(isElevated: true), lineWidth: 1)
            )
        }
    }

    // MARK: - 压力告警分类计数

    private struct AlertTally {
        var memoryCount = 0
        var memoryWorstLevel = 0
        var memoryOngoing = false
        var thermalCount = 0
        var thermalWorstLevel = 0
        var thermalOngoing = false
        var appCount = 0

        var pressureCount: Int { memoryCount + thermalCount }
        var isClear: Bool { memoryCount == 0 && thermalCount == 0 && appCount == 0 }
    }

    private var alertTally: AlertTally {
        var tally = AlertTally()
        for event in viewModel.rangeModel?.events ?? [] {
            let ongoing = event.state == .ongoing
            switch event.kind {
            case .memory:
                tally.memoryCount += 1
                tally.memoryWorstLevel = max(tally.memoryWorstLevel, event.worstLevel)
                tally.memoryOngoing = tally.memoryOngoing || ongoing
            case .thermal:
                tally.thermalCount += 1
                tally.thermalWorstLevel = max(tally.thermalWorstLevel, event.worstLevel)
                tally.thermalOngoing = tally.thermalOngoing || ongoing
            }
        }
        tally.appCount = viewModel.rangeModel?.apps.highLoadAlerts.count ?? 0
        return tally
    }

    private func alertChip(
        icon: String,
        label: String,
        count: Int,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.11)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
    }

    /// 优先归因最相关的头号占用应用：存在内存压力时指向内存排行首位，否则指向高负载或 CPU 首位。
    private func primaryConsumerApp(preferMemory: Bool) -> (name: String, appKey: String)? {
        guard let apps = viewModel.rangeModel?.apps else { return nil }
        if preferMemory, let topMem = apps.memList.first {
            return (topMem.name, topMem.appKey)
        }
        if let firstAlert = apps.highLoadAlerts.first {
            return (firstAlert.name, firstAlert.appKey)
        }
        if let topCPU = apps.cpuList.first {
            return (topCPU.name, topCPU.appKey)
        }
        return nil
    }

    @ViewBuilder
    private func alertChips(_ tally: AlertTally) -> some View {
        HStack(spacing: 6) {
            if tally.memoryCount > 0 {
                alertChip(
                    icon: "memorychip",
                    label: String(localized: "stats.r.kMem", defaultValue: "内存"),
                    count: tally.memoryCount,
                    tint: palette.pressureEventChipTint(worstLevel: tally.memoryWorstLevel, isOngoing: tally.memoryOngoing),
                    action: { viewModel.openEvents(filter: .memory) }
                )
            }
            if tally.thermalCount > 0 {
                alertChip(
                    icon: "flame.fill",
                    label: String(localized: "stats.r.alertThermal", defaultValue: "热压力"),
                    count: tally.thermalCount,
                    tint: palette.pressureEventChipTint(worstLevel: tally.thermalWorstLevel, isOngoing: tally.thermalOngoing),
                    action: { viewModel.openEvents(filter: .thermal) }
                )
            }
            if let topConsumer = primaryConsumerApp(preferMemory: tally.memoryCount > 0),
               (tally.pressureCount > 0 || tally.appCount > 0) {
                topConsumerChip(appName: topConsumer.name, alertCount: tally.appCount)
            }
        }
    }

    private func topConsumerChip(appName: String, alertCount: Int) -> some View {
        let label: String
        if alertCount > 1 {
            label = String(
                format: String(localized: "stats.r.overview.topConsumerMulti", defaultValue: "主要占用 %@ 等 %d 项"),
                appName,
                alertCount
            )
        } else {
            label = String(
                format: String(localized: "stats.r.overview.topConsumer", defaultValue: "主要占用 %@"),
                appName
            )
        }

        return Button {
            if alertCount > 0 {
                viewModel.openAppAlerts()
            } else {
                viewModel.selectedModule = .apps
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 210, alignment: .leading)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help("\(label) · \(String(localized: "stats.r.overview.topConsumerHelp", defaultValue: "点击查看应用资源占用排行与明细"))")
    }

    // MARK: - 紧凑评分摘要卡

    private var healthScoreSummary: some View {
        let model = viewModel.rangeModel
        let result = model?.healthScore
        let hasPressureEvents = !(model?.events.isEmpty ?? true)
        let tally = alertTally

        return ReportCardView(
            title: String(localized: "stats.r.healthScoreTitle"),
            icon: "gauge.medium",
            showsHeader: false
        ) {
            HStack(alignment: .center, spacing: 16) {
                scoreSummary(result: result, hasPressureEvents: hasPressureEvents)

                Divider()
                    .frame(height: 42)

                coverageSummary

                Divider()
                    .frame(height: 42)

                eventsBlockLabel

                if tally.isClear {
                    Text(String(localized: "stats.r.overview.noPressureEvents", defaultValue: "无压力事件"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    alertChips(tally)
                }

                Spacer(minLength: 12)

                if tally.pressureCount > 0 {
                    viewDetailsButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 54)
        }
    }

    private var eventsBlockLabel: some View {
        Text(String(localized: "stats.r.eventsBlockLabel", defaultValue: "事件"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minWidth: 28, alignment: .leading)
    }

    private var viewDetailsButton: some View {
        Button { viewModel.openEvents(filter: .all) } label: {
            HStack(spacing: 4) {
                Text(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(String(localized: "stats.r.secEvents", defaultValue: "压力警告"))
    }

    private func scoreSummary(result: StatisticsHealthScore.Result?, hasPressureEvents: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.scoreTint(for: result?.level))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    let scoreText = result.map {
                        "\(StatisticsHealthScore.displayScore($0.score, hasPressureEvents: hasPressureEvents))"
                    } ?? "—"
                    Text(scoreText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(localized: "stats.r.pts", defaultValue: "分"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    scoreBasisButton(result: result)
                }

                if let result {
                    Text(result.level.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(nilReasonText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(nilReasonText)
                }
            }
        }
    }

    /// 系统数据完整度：只呈现系统级覆盖率与系统级质量警告，不再被全库应用采样估算说明覆盖。
    private var coverageSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let coverage = viewModel.rangeModel?.coveragePercent {
                Text(String(format: String(localized: "stats.r.coverageSummary", defaultValue: "数据完整度 %.1f%%"), coverage))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                ProgressView(value: coverage / 100)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(.secondary)
                    .frame(width: 80)
            } else {
                Text(String(localized: "stats.r.coverageUnavailable", defaultValue: "数据完整度 —"))
                    .font(.callout.weight(.medium))
                Text(String(localized: "stats.r.coverageNoData", defaultValue: "所选范围没有有效采样"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let notice = viewModel.rangeModel?.systemQualityNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(notice)
            }
        }
        .help(String(localized: "stats.r.coverageHelp", defaultValue: "有效采样时长占清醒时间的比例；系统确认的整机休眠不计入清醒时间。"))
    }

    private var nilReasonText: String {
        viewModel.rangeModel?.healthScoreNilReason
            ?? String(localized: "stats.r.healthScoreInsufficient")
    }

    // MARK: - 评分依据与实测分项弹出窗

    private func scoreBasisButton(result: StatisticsHealthScore.Result?) -> some View {
        Button { showScoreBasis.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据"))
        .accessibilityLabel(Text(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据")))
        .popover(isPresented: $showScoreBasis, arrowEdge: .bottom) {
            scoreBasisPopover(result: result)
        }
    }

    private func scoreBasisPopover(result: StatisticsHealthScore.Result?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据"))
                .font(.system(size: 12, weight: .semibold))

            Text(String(localized: "stats.r.scoreFormula", defaultValue: "100 −（内存压力负担 × 60% + 热压力负担 × 40%）× 100"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let result, !result.dimensions.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.dimensions) { dim in
                        HStack {
                            Text(dim.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(dim.rawText) · \(dim.level.title)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Divider()
            Text(String(localized: "stats.report.conclusion.scope"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 275, alignment: .leading)
    }

    // MARK: - 核心用量与传输总览卡片

    private func resourceGrid(primary: Bool) -> some View {
        let cpu = viewModel.rangeModel?.cpu
        let gpu = viewModel.rangeModel?.gpu
        let mem = viewModel.rangeModel?.memory
        let power = viewModel.rangeModel?.power
        let net = viewModel.rangeModel?.network
        let disk = viewModel.rangeModel?.disk
        let thermal = viewModel.rangeModel?.thermal
        let topApp = viewModel.rangeModel?.apps.cpuList.first

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            if primary {
                ReportOverviewMetricRow(
                    icon: MonitorKind.cpu.symbol,
                    tint: palette.cpu,
                    title: String(localized: "stats.metrics.cpu", defaultValue: "CPU"),
                    value: cpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                    caption: formatUsageCaption(highSeconds: cpu?.highSeconds, peak: cpu?.peakUsage),
                    destination: .cpu,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.gpu.symbol,
                    tint: palette.gpu,
                    title: String(localized: "stats.metrics.gpu", defaultValue: "GPU"),
                    value: gpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                    caption: formatUsageCaption(highSeconds: gpu?.highSeconds, peak: gpu?.peakUsage),
                    destination: .gpu,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.memory.symbol,
                    tint: palette.memory,
                    title: String(localized: "stats.metrics.memoryUsage", defaultValue: "内存"),
                    value: mem?.memPctAvg.map { String(format: "%.1f%%", $0) } ?? (mem?.usedAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—"),
                    caption: formatMemoryCaption(pressure: mem?.pressureAvgPercent, peak: mem?.usedPeakPercent),
                    destination: .memory,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.battery.symbol,
                    tint: palette.power,
                    title: String(localized: "stats.metrics.power", defaultValue: "功耗"),
                    value: power?.avgPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                    caption: power?.peakPowerWatts.map { String(format: String(localized: "report.ui.peakPower"), $0) },
                    destination: .power,
                    onNavigate: { navigateTo($0) }
                )
            } else {
                ReportOverviewMetricRow(
                    icon: MonitorKind.network.symbol,
                    tint: palette.networkDown,
                    title: String(localized: "overview.resources.network", defaultValue: "网络"),
                    value: formatNetworkValue(net),
                    caption: net?.peakDownRate.map { String(localized: "report.ui.peakDownload") + ReportUIHelper.formatBytesRate($0) },
                    destination: .network,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.storage.symbol,
                    tint: palette.diskRead,
                    title: String(localized: "stats.metrics.disk", defaultValue: "磁盘"),
                    value: formatDiskValue(disk),
                    caption: disk?.peakReadRate.map { String(localized: "report.ui.peakRead") + ReportUIHelper.formatBytesRate($0) },
                    destination: .disk,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: "flame",
                    tint: palette.thermal,
                    title: String(localized: "stats.r.secThermal", defaultValue: "热压力"),
                    value: thermal?.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? StatisticsDisplayFormat.thermalStateLabel(thermal?.cpuThermalAvg),
                    caption: thermal?.fanAvgRPM.map { String(format: String(localized: "report.ui.fanSpeed"), $0) } ?? (thermal?.hasFans == false ? String(localized: "report.ui.fanless") : nil),
                    destination: .thermal,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: "app.badge.checkmark",
                    tint: Color.accentColor,
                    title: String(localized: "stats.r.secAppsTitle", defaultValue: "应用排行"),
                    value: topApp?.name ?? "—",
                    caption: topApp != nil ? String(localized: "report.ui.topCPU") + topApp!.valueText : String(localized: "report.ui.rankDetails"),
                    destination: .apps,
                    onNavigate: { navigateTo($0) }
                )
            }
        }
    }

    private func formatUsageCaption(highSeconds: Double?, peak: Double?) -> String? {
        if let highSeconds, highSeconds > 0 {
            return String(localized: "report.ui.highLoad") + StatisticsDisplayFormat.duration(highSeconds)
        }
        if let peak {
            return String(format: String(localized: "report.ui.peakUsage"), peak)
        }
        return nil
    }

    private func formatMemoryCaption(pressure: Double?, peak: Double?) -> String? {
        if let pressure, pressure > 0 {
            return String(format: String(localized: "report.ui.avgPressure"), pressure)
        }
        if let peak {
            return String(format: String(localized: "report.ui.peakMemory"), peak)
        }
        return nil
    }

    private func formatNetworkValue(_ net: ReportNetworkMetrics?) -> String {
        guard let net else { return "—" }
        guard net.totalDownBytes != nil || net.totalUpBytes != nil else { return "—" }
        return "↓ \(net.totalDownBytes.map(ReportUIHelper.formatVolume) ?? "—")  ↑ \(net.totalUpBytes.map(ReportUIHelper.formatVolume) ?? "—")"
    }

    private func formatDiskValue(_ disk: ReportDiskMetrics?) -> String {
        guard let disk else { return "—" }
        guard disk.totalReadBytes != nil || disk.totalWriteBytes != nil else { return "—" }
        return String(format: String(localized: "report.ui.diskTotal"), disk.totalReadBytes.map(ReportUIHelper.formatVolume) ?? "—", disk.totalWriteBytes.map(ReportUIHelper.formatVolume) ?? "—")
    }

    private func navigateTo(_ module: ReportNavigationModule) {
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.selectedModule = module
        }
    }

    // MARK: - 综合负载与压力趋势（带事件色带叠加、Hover 浮窗与高频降噪切换）

    private var compositeTrendCard: some View {
        let model = viewModel.rangeModel
        let cache = model?.chartCache ?? .empty
        let isDense = cache.cpuAvg.pointCount > 300

        func maybeSmooth(_ s: ReportChartSeries) -> ReportChartSeries {
            (isDense && smoothDenseTrend) ? s.smoothed(targetMaxPoints: 240) : s
        }

        let descriptors: [ReportChartSeriesDescriptor] = {
            switch trendMode {
            case .load:
                return [
                    ReportChartSeriesDescriptor(
                        id: "cpu",
                        title: String(localized: "stats.r.sCpu", defaultValue: "CPU"),
                        series: maybeSmooth(cache.cpuAvg),
                        color: palette.cpu
                    ),
                    ReportChartSeriesDescriptor(
                        id: "gpu",
                        title: String(localized: "stats.r.sGpu", defaultValue: "GPU"),
                        series: maybeSmooth(cache.gpuAvg),
                        color: palette.gpu
                    )
                ]
            case .memory:
                return [
                    ReportChartSeriesDescriptor(
                        id: "memPressure",
                        title: String(localized: "stats.r.sMemPressure", defaultValue: "内存压力"),
                        series: maybeSmooth(cache.memPressure),
                        color: palette.memory
                    ),
                    ReportChartSeriesDescriptor(
                        id: "memUsage",
                        title: String(localized: "stats.r.sMemUsage", defaultValue: "内存占比"),
                        series: maybeSmooth(cache.memUsagePct),
                        color: palette.memoryUsageLine,
                        lineWidth: 1.4,
                        isDashed: true
                    )
                ]
            }
        }()

        let eventHighlights: [ReportChartHighlightWindow] = (model?.events ?? []).map { event in
            let tone: ReportChartHighlightWindow.Tone = (event.worstLevel >= 2) ? .critical : .warning
            return ReportChartHighlightWindow(
                id: event.id,
                start: event.start,
                end: event.end,
                tone: tone,
                label: event.kind.title
            )
        }

        return ReportCardView(
            title: String(localized: "stats.r.overviewTrendTitle", defaultValue: "综合负载与压力趋势"),
            icon: "chart.xyaxis.line",
            trailing: {
                HStack(spacing: 10) {
                    if isDense {
                        Toggle(isOn: $smoothDenseTrend) {
                            Text(String(localized: "stats.report.trend.smooth", defaultValue: "降噪平滑"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }

                    ReportNavigationPicker(
                        title: "",
                        selection: $trendMode,
                        options: TrendMode.allCases.map { ReportSegmentOption(value: $0, label: $0.label) },
                        size: .compact
                    )
                    .fixedSize()
                }
            }
        ) {
            if model?.rows.isEmpty ?? true {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无采样记录"))
            } else {
                ReportTimeSeriesChart(
                    descriptors: descriptors,
                    isSingleDay: viewModel.isSingleDaySelected,
                    yAxisFormat: .percent,
                    yDomain: 0...100,
                    yAxisValues: [0, 25, 50, 75, 100],
                    highlightWindows: eventHighlights,
                    height: 256
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 7×24 小时活跃热力图

    private func heatmapCard(heatmap: ReportHeatmapData) -> some View {
        let weekdayNames = [
            String(localized: "stats.r.wd1", defaultValue: "周一"),
            String(localized: "stats.r.wd2", defaultValue: "周二"),
            String(localized: "stats.r.wd3", defaultValue: "周三"),
            String(localized: "stats.r.wd4", defaultValue: "周四"),
            String(localized: "stats.r.wd5", defaultValue: "周五"),
            String(localized: "stats.r.wd6", defaultValue: "周六"),
            String(localized: "stats.r.wd0", defaultValue: "周日")
        ]
        let displayRowOrder = [1, 2, 3, 4, 5, 6, 0]

        return ReportCardView(
            title: String(localized: "stats.r.heatmapTitle", defaultValue: "7×24 小时活动节律"),
            icon: "calendar.day.timeline.leading"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 3) {
                    Text("")
                        .frame(width: 32)
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 3 == 0 ? "\(h)" : "")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                VStack(spacing: 3) {
                    ForEach(Array(displayRowOrder.enumerated()), id: \.offset) { idx, wd in
                        HStack(spacing: 3) {
                            Text(weekdayNames[idx])
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)

                            ForEach(0..<24, id: \.self) { hr in
                                let cell = heatmap.cells.first { $0.weekday == wd && $0.hour == hr }
                                cellView(cell: cell)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text(String(localized: "stats.r.low", defaultValue: "低"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 2) {
                        ForEach([0.15, 0.35, 0.60, 0.85, 1.0], id: \.self) { op in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.cpu.opacity(op))
                                .frame(width: 12, height: 10)
                        }
                    }
                    Text(String(localized: "stats.r.high", defaultValue: "高"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func cellView(cell: ReportHeatmapCell?) -> some View {
        let opacity = cell.map { max(0.12, min(1.0, $0.intensity)) } ?? 0.04

        return RoundedRectangle(cornerRadius: 2)
            .fill(cell != nil ? palette.cpu.opacity(opacity) : Color.secondary.opacity(0.06))
            .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 18)
            .help(cell?.avgBusy.map { String(format: "%.1f%%", $0) } ?? String(localized: "stats.r.noData", defaultValue: "无数据"))
    }
}

// MARK: - 核心总览指标交互行组件

struct ReportOverviewMetricRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let caption: String?
    let destination: ReportNavigationModule
    let onNavigate: (ReportNavigationModule) -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        let isMissing = value == "—"
        Button {
            onNavigate(destination)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.body.weight(.semibold))
                    Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(destination == .apps || destination == .network || destination == .disk ? .title3 : .title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isMissing ? Color.secondary.opacity(0.6) : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption ?? " ")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? palette.cardHoverFill : palette.cardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHovered ? tint.opacity(0.42) : palette.cardBorder, lineWidth: 0.75)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
