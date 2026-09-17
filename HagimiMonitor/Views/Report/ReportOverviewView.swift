import AppKit
import Charts
import SwiftUI

/// 报表概览视图：包含异常告警提示条、系统健康评估与核心用量总览、多维综合负载趋势以及 7×24 小时活跃热力图。
struct ReportOverviewView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?
    @State private var showScoreBasis = false

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: MonitorPalette {
        MonitorPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }
    private var cpuColor: Color { palette.moduleTint(for: .cpu) }
    private var gpuColor: Color { palette.moduleTint(for: .gpu) }
    private var memPressureColor: Color { palette.moduleTint(for: .memory) }
    private var memUsageColor: Color { palette.moduleTint(for: .memory).opacity(0.6) }
    private var powerColor: Color { palette.moduleTint(for: .battery) }
    private var netColor: Color { palette.moduleTint(for: .network) }
    private var diskColor: Color { palette.moduleTint(for: .storage) }
    private var thermalColor: Color { palette.moduleTint(for: .fan) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            overviewHeading
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
            Text("report.ui.historical")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 0. 压力告警分类计数

    /// 概览只做分类计数,不铺开具体事件:事件按「连续压力片段」逐条生成,长范围动辄几十条,
    /// 铺开会把首屏撑成流水账。计数胶囊各自带跳转,单条事件的细节留在压力警告模块。
    private struct AlertTally {
        var memoryCount = 0
        var memoryWorstLevel = 0
        var memoryOngoing = false
        var thermalCount = 0
        var thermalWorstLevel = 0
        var thermalOngoing = false
        var appCount = 0
        var appOngoing = false

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
        let appAlerts = viewModel.rangeModel?.apps.highLoadAlerts ?? []
        tally.appCount = appAlerts.count
        tally.appOngoing = appAlerts.contains { $0.isOngoing }
        return tally
    }

    /// 单类告警配色:进行中的越级告警用严重色,其余进行中用警告色,已恢复一律中性色。
    private func alertTint(worstLevel: Int, isOngoing: Bool) -> Color {
        guard isOngoing else { return palette.severityTint(for: .calm) }
        return palette.severityTint(for: worstLevel >= 2 ? .critical : .warning)
    }

    private func alertChip(
        icon: String,
        label: String,
        count: Int,
        tint: Color,
        destination: ReportNavigationModule
    ) -> some View {
        Button { navigateTo(destination) } label: {
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
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
    }

    @ViewBuilder
    private func alertChips(_ tally: AlertTally) -> some View {
        HStack(spacing: 6) {
            if tally.memoryCount > 0 {
                alertChip(
                    icon: "memorychip",
                    label: String(localized: "stats.r.kMem", defaultValue: "内存"),
                    count: tally.memoryCount,
                    tint: alertTint(worstLevel: tally.memoryWorstLevel, isOngoing: tally.memoryOngoing),
                    destination: .memory
                )
            }
            if tally.thermalCount > 0 {
                alertChip(
                    icon: "flame.fill",
                    label: String(localized: "stats.r.alertThermal", defaultValue: "热压力"),
                    count: tally.thermalCount,
                    tint: alertTint(worstLevel: tally.thermalWorstLevel, isOngoing: tally.thermalOngoing),
                    destination: .thermal
                )
            }
            if tally.appCount > 0 {
                alertChip(
                    icon: "app.badge.checkmark",
                    label: String(localized: "stats.r.kApps", defaultValue: "应用"),
                    count: tally.appCount,
                    tint: alertTint(worstLevel: 1, isOngoing: tally.appOngoing),
                    destination: .apps
                )
            }
        }
    }

    /// 概览首屏的紧凑评分摘要：左侧分数与数据完整度，右侧压力告警分类计数。
    /// 它只描述选定范围内的压力记录，不暗示硬件健康诊断。整行固定高度——告警计数与
    /// 分数可用性都不参与高度计算，切换时间范围不会推动下方内容。
    private var healthScoreSummary: some View {
        let result = viewModel.rangeModel?.healthScore
        let tally = alertTally

        return ReportCardView(
            title: String(localized: "stats.r.healthScoreTitle"),
            icon: "gauge.medium",
            showsHeader: false
        ) {
            HStack(alignment: .center, spacing: 16) {
                scoreSummary(result: result)

                Divider()
                    .frame(height: 42)

                coverageSummary

                Divider()
                    .frame(height: 42)

                // 第三块:标签锚在左侧(紧接数据完整度),明细按钮锚在右边缘,两者位置都不随
                // 范围切换移动;胶囊在中间生长,由后面的空隙吸收——既不留常驻空白,
                // 也不会出现「胶囊一变多标签就乱跑」。
                eventsBlockLabel

                if tally.isClear {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    alertChips(tally)
                }

                Spacer(minLength: 12)

                if tally.pressureCount > 0 {
                    viewDetailsButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
        }
    }

    private var eventsBlockLabel: some View {
        Text(String(localized: "stats.r.eventsBlockLabel", defaultValue: "事件"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minWidth: 28, alignment: .leading)
    }

    private var viewDetailsButton: some View {
        Button { navigateTo(.events) } label: {
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

    private func scoreSummary(result: StatisticsHealthScore.Result?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.moduleTint(for: .memory))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(result.map { String(format: "%.0f", $0.score) } ?? "—")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(localized: "stats.r.pts", defaultValue: "分"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    scoreBasisButton
                }

                if let result {
                    Text(result.level.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    // 固定行高容不下两行原因,溢出的部分交给悬停提示。
                    Text(nilReasonText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(nilReasonText)
                }
            }
        }
    }

    /// 数据完整度:进度条定宽,不再跟着标签文字一路拉长——这一块的宽度由文字决定,
    /// 所以真正省宽度的是短标签(见 stats.r.coverageSummary),进度条只负责视觉比例。
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
                    .frame(width: 64)
            } else {
                Text(String(localized: "stats.r.coverageUnavailable", defaultValue: "数据完整度 —"))
                    .font(.callout.weight(.medium))
                Text(String(localized: "stats.r.coverageNoData", defaultValue: "所选范围没有有效采样"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var nilReasonText: String {
        viewModel.rangeModel?.healthScoreNilReason
            ?? String(localized: "stats.r.healthScoreInsufficient")
    }

    // MARK: - 评分依据按需弹出

    /// 评分依据按需弹出:公式与权重是解释性内容,常驻会占用横向排版预算并与分数抢宽度,
    /// 其换行还会把这一行撑高。
    private var scoreBasisButton: some View {
        Button { showScoreBasis.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据"))
        .accessibilityLabel(Text(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据")))
        .popover(isPresented: $showScoreBasis, arrowEdge: .bottom) {
            scoreBasisPopover
        }
    }

    private var scoreBasisPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据"))
                .font(.system(size: 12, weight: .semibold))

            Text(String(localized: "stats.r.scoreFormula", defaultValue: "100 −（内存压力负担 × 60% + 热压力负担 × 40%）× 100"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    // MARK: - 1.2 核心用量与传输总览卡片 (直达各模块明细)

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
                    tint: cpuColor,
                    title: String(localized: "stats.metrics.cpu", defaultValue: "CPU"),
                    value: cpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                    caption: formatUsageCaption(highSeconds: cpu?.highSeconds, peak: cpu?.peakUsage),
                    destination: .cpu,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.gpu.symbol,
                    tint: gpuColor,
                    title: String(localized: "stats.metrics.gpu", defaultValue: "GPU"),
                    value: gpu?.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                    caption: formatUsageCaption(highSeconds: gpu?.highSeconds, peak: gpu?.peakUsage),
                    destination: .gpu,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.memory.symbol,
                    tint: memPressureColor,
                    title: String(localized: "stats.metrics.memoryUsage", defaultValue: "内存"),
                    value: mem?.memPctAvg.map { String(format: "%.1f%%", $0) } ?? (mem?.usedAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—"),
                    caption: formatMemoryCaption(pressure: mem?.pressureAvgPercent, peak: mem?.usedPeakPercent),
                    destination: .memory,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.battery.symbol,
                    tint: powerColor,
                    title: String(localized: "stats.metrics.power", defaultValue: "功耗"),
                    value: power?.avgPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                    caption: power?.peakPowerWatts.map { String(format: String(localized: "report.ui.peakPower"), $0) },
                    destination: .power,
                    onNavigate: { navigateTo($0) }
                )
            } else {
                ReportOverviewMetricRow(
                    icon: MonitorKind.network.symbol,
                    tint: netColor,
                    title: String(localized: "overview.resources.network", defaultValue: "网络"),
                    value: formatNetworkValue(net),
                    caption: net?.peakDownRate.map { String(localized: "report.ui.peakDownload") + ReportUIHelper.formatBytesRate($0) },
                    destination: .network,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: MonitorKind.storage.symbol,
                    tint: diskColor,
                    title: String(localized: "stats.metrics.disk", defaultValue: "磁盘"),
                    value: formatDiskValue(disk),
                    caption: disk?.peakReadRate.map { String(localized: "report.ui.peakRead") + ReportUIHelper.formatBytesRate($0) },
                    destination: .disk,
                    onNavigate: { navigateTo($0) }
                )
                ReportOverviewMetricRow(
                    icon: "flame",
                    tint: thermalColor,
                    title: String(localized: "stats.r.secThermal", defaultValue: "热压力"),
                    value: thermal?.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? "—",
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
        return "↓ \(net.totalDownBytes.map(ReportUIHelper.formatBytes) ?? "—")  ↑ \(net.totalUpBytes.map(ReportUIHelper.formatBytes) ?? "—")"
    }

    private func formatDiskValue(_ disk: ReportDiskMetrics?) -> String {
        guard let disk else { return "—" }
        guard disk.totalReadBytes != nil || disk.totalWriteBytes != nil else { return "—" }
        return String(format: String(localized: "report.ui.diskTotal"), disk.totalReadBytes.map(ReportUIHelper.formatBytes) ?? "—", disk.totalWriteBytes.map(ReportUIHelper.formatBytes) ?? "—")
    }

    private func navigateTo(_ module: ReportNavigationModule) {
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.selectedModule = module
        }
    }

    // MARK: - 2. 多维综合负载趋势折线图 (R16: 恢复四维趋势，R07: 缺口断开)

    private var compositeTrendCard: some View {
        let rows = viewModel.rangeModel?.rows ?? []
        let granularity = viewModel.rangeModel?.granularity.bucketSeconds ?? 60

        let cpuPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuAvg,
            seriesID: "cpu",
            granularitySeconds: granularity
        )
        let gpuPoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.gpuAvg,
            seriesID: "gpu",
            granularitySeconds: granularity
        )
        let pressurePoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memPressureAvg,
            seriesID: "memPressure",
            granularitySeconds: granularity
        )
        let memUsagePoints = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.memPctAvg,
            seriesID: "memUsage",
            granularitySeconds: granularity
        )

        let cpuSegments = Dictionary(grouping: cpuPoints, by: \.segmentID)
        let gpuSegments = Dictionary(grouping: gpuPoints, by: \.segmentID)
        let pressureSegments = Dictionary(grouping: pressurePoints, by: \.segmentID)
        let memUsageSegments = Dictionary(grouping: memUsagePoints, by: \.segmentID)

        return ReportCardView(
            title: String(localized: "stats.r.overviewTrendTitle", defaultValue: "综合负载与压力趋势"),
            icon: "chart.xyaxis.line"
        ) {
            if rows.isEmpty {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无采样记录"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        ReportLegendItem(title: String(localized: "stats.r.sCpu", defaultValue: "CPU"), color: cpuColor)
                        ReportLegendItem(title: String(localized: "stats.r.sGpu", defaultValue: "GPU"), color: gpuColor)
                        ReportLegendItem(title: String(localized: "stats.r.sMemPressure", defaultValue: "内存压力"), color: memPressureColor)
                        ReportLegendItem(title: String(localized: "stats.r.sMemUsage", defaultValue: "内存占比"), color: memUsageColor, isDashed: true)

                        Spacer()

                        if let selectedDate, let row = ReportUIHelper.findClosestRow(to: selectedDate, in: rows) {
                            Text("\(ReportUIHelper.formatDateTime(Date(timeIntervalSince1970: TimeInterval(row.t)))): CPU \(row.cpuAvg.map { String(format: "%.1f%%", $0) } ?? "—") | GPU \(row.gpuAvg.map { String(format: "%.1f%%", $0) } ?? "—") | 压 \(row.memPressureAvg.map { String(format: "%.0f%%", $0) } ?? "—")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        // 1. CPU 均值
                        ForEach(Array(cpuSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = cpuSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value ?? 0),
                                    series: .value("Series", "cpu-\(seg)")
                                )
                                .foregroundStyle(cpuColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 2. GPU 均值
                        ForEach(Array(gpuSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = gpuSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value ?? 0),
                                    series: .value("Series", "gpu-\(seg)")
                                )
                                .foregroundStyle(gpuColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 3. 内存压力
                        ForEach(Array(pressureSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = pressureSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value ?? 0),
                                    series: .value("Series", "memPressure-\(seg)")
                                )
                                .foregroundStyle(memPressureColor)
                                .interpolationMethod(.monotone)
                            }
                        }

                        // 4. 内存占用比 (虚线)
                        ForEach(Array(memUsageSegments.keys.sorted()), id: \.self) { seg in
                            let segPoints = memUsageSegments[seg] ?? []
                            ForEach(segPoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value ?? 0),
                                    series: .value("Series", "memUsage-\(seg)")
                                )
                                .foregroundStyle(memUsageColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                                .interpolationMethod(.monotone)
                            }
                        }

                        if let selectedDate {
                            RuleMark(x: .value("Selected", selectedDate))
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
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 260)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 7×24 小时活跃热力图 (R06: 复合忙碌度)

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
                // 顶部小时轴标头 (0..23)
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

                // 7 天行网格
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

                // 底部图例
                HStack {
                    Spacer()
                    Text(String(localized: "stats.r.low", defaultValue: "低"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 2) {
                        ForEach([0.15, 0.35, 0.60, 0.85, 1.0], id: \.self) { op in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cpuColor.opacity(op))
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
            .fill(cell != nil ? cpuColor.opacity(opacity) : Color.secondary.opacity(0.06))
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

    var body: some View {
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
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption ?? " ")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.85 : 0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? tint.opacity(0.4) : Color.primary.opacity(0.07))
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
