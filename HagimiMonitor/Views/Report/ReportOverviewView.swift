import AppKit
import Charts
import SwiftUI

/// 报表概览视图：包含异常告警提示条、系统健康评估与核心用量总览、多维综合负载趋势以及 7×24 小时活跃热力图。
struct ReportOverviewView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedDate: Date?

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
            if hasAlerts { alertBanner }
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

    // MARK: - 0. 异常告警与高负载提醒条

    private var hasAlerts: Bool {
        let events = viewModel.rangeModel?.events ?? []
        let appAlerts = viewModel.rangeModel?.apps.highLoadAlerts ?? []
        return !events.isEmpty || !appAlerts.isEmpty
    }

    private var alertBanner: some View {
        let events = viewModel.rangeModel?.events ?? []
        let appAlerts = viewModel.rangeModel?.apps.highLoadAlerts ?? []

        let ongoingEvents = events.filter { $0.state == .ongoing }
        let ongoingApps = appAlerts.filter { $0.isOngoing }
        let isCritical = !ongoingEvents.isEmpty || !ongoingApps.isEmpty

        let tintColor = isCritical ? palette.severityTint(for: .critical) : palette.severityTint(for: .warning)

        return HStack(spacing: 12) {
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tintColor)

            VStack(alignment: .leading, spacing: 2) {
                if !events.isEmpty {
                    let first = events[0]
                    let levelStr: String? = {
                        switch (first.kind, first.worstLevel) {
                        case (.memory, 2): return String(localized: "report.ui.severe")
                        case (.memory, 1): return String(localized: "report.ui.warning")
                        case (.thermal, 3): return String(localized: "report.ui.critical")
                        case (.thermal, 2): return String(localized: "report.ui.severe")
                        case (.thermal, 1): return String(localized: "report.ui.mild")
                        default: return nil
                        }
                    }()

                    HStack(spacing: 6) {
                        Text(first.kind.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)

                        if let levelStr {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(levelStr)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(first.worstLevel >= 2 ? palette.severityTint(for: .critical) : palette.severityTint(for: .warning))
                        }

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(String(localized: "report.ui.duration") + StatisticsDisplayFormat.duration(first.pressureSeconds))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(first.state.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(first.state == .ongoing ? tintColor : (first.state == .recovered ? palette.severityTint(for: .calm) : Color.secondary))

                        if events.count > 1 {
                            Text(String(format: String(localized: "report.ui.eventCount"), events.count))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !appAlerts.isEmpty {
                    let firstApp = appAlerts[0]
                    HStack(spacing: 6) {
                        Text(firstApp.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(String(format: String(localized: "report.ui.highMinutes"), firstApp.maxDurationMinutes))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)

                        if appAlerts.count > 1 {
                            Text(String(format: String(localized: "report.ui.appCount"), appAlerts.count))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button {
                if !events.isEmpty {
                    switch events[0].kind {
                    case .memory: navigateTo(.memory)
                    case .thermal: navigateTo(.thermal)
                    }
                } else {
                    navigateTo(.apps)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tintColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tintColor.opacity(0.2), lineWidth: 1)
        )
    }

    /// 概览首屏的紧凑评分摘要。它只描述选定范围内的压力记录，不暗示硬件健康诊断。
    private var healthScoreSummary: some View {
        let result = viewModel.rangeModel?.healthScore
        return ReportCardView(
            title: String(localized: "stats.r.healthScoreTitle"),
            icon: "gauge.medium",
            showsHeader: false
        ) {
            HStack(alignment: .center, spacing: 16) {
                scoreSummary(result: result)
                    .frame(minWidth: 170, alignment: .leading)

                Divider()
                    .frame(height: 42)

                coverageSummary
                    .frame(minWidth: 190, maxWidth: 250, alignment: .leading)

                Divider()
                    .frame(height: 42)

                scoreBasis(result: result)
                    .frame(minWidth: 270, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 60, alignment: .leading)
        }
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
                }

                if let result {
                    Text(result.level.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(viewModel.rangeModel?.healthScoreNilReason
                         ?? String(localized: "stats.r.healthScoreInsufficient"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

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
                Text(String(localized: "stats.r.coverageHint", defaultValue: "所选时段有效采样覆盖"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "stats.r.coverageUnavailable", defaultValue: "数据完整度 —"))
                    .font(.callout.weight(.medium))
                Text(String(localized: "stats.r.coverageNoData", defaultValue: "所选范围没有有效采样"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func scoreBasis(result: StatisticsHealthScore.Result?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "stats.r.scoreBasis", defaultValue: "评分依据"))
                .font(.caption.weight(.semibold))

            if let result,
               result.dimensions.count == 2,
               let memory = result.dimensions.first(where: { $0.kind == .memory }),
               let thermal = result.dimensions.first(where: { $0.kind == .thermal }) {
                HStack(spacing: 10) {
                    scoreBasisValue(
                        label: String(localized: "stats.r.scoreBasisMemory", defaultValue: "内存压力"),
                        value: memory.rawText,
                        weight: "60%"
                    )
                    scoreBasisValue(
                        label: String(localized: "stats.r.scoreBasisThermal", defaultValue: "热压力"),
                        value: thermal.rawText,
                        weight: "40%"
                    )
                }

                Label {
                    Text(String(localized: "stats.r.scoreFormula", defaultValue: "100 −（内存压力负担 × 60% + 热压力负担 × 40%）× 100"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .help(String(localized: "stats.r.scoreFormula", defaultValue: "100 −（内存压力负担 × 60% + 热压力负担 × 40%）× 100"))
            } else if let result, !result.dimensions.isEmpty {
                Text(String(localized: "stats.r.historicalScoreBasis", defaultValue: "历史评分口径"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.dimensions.map { "\($0.name) \($0.rawText)" }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(result.dimensions.map { "\($0.name) \($0.rawText)" }.joined(separator: " · "))
            } else {
                Text(String(localized: "stats.r.scoreBasisUnavailable", defaultValue: "暂无可用评分依据"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func scoreBasisValue(label: String, value: String, weight: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value)
                .monospacedDigit()
            Text("× \(weight)")
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .lineLimit(1)
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
