import SwiftUI

/// 原生打印与 PDF 导出专用分页友好排版视图（纯原生 SwiftUI 渲染，浅底高对比，不依赖 WKWebView）。
struct ReportPrintableView: View {
    let model: ReportActiveRangeModel
    let meta: ReportMeta
    let hardware: HardwareInventory?

    private var conclusion: ReportPeriodConclusion.Summary {
        ReportPeriodConclusion.summary(
            events: model.events,
            appAlertCount: model.apps.highLoadAlerts.count,
            coveredSeconds: model.coveredSeconds,
            quality: model.quality
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            Divider()
            conclusionSection
            coreMetricsSection

            if !model.events.isEmpty {
                eventsSection
            }

            if !model.insights.isEmpty {
                insightsSection
            }

            if hasAnyAppRanking {
                topAppsSection
            }

            if let hardware {
                hardwareIdentitySection(hardware: hardware)
            }

            footerScopeSection
        }
        .padding(24)
        .frame(width: 540, alignment: .leading)
        .foregroundStyle(Color.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - 1. 页眉

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "report.print.title", defaultValue: "HagimiMonitor 系统统计报表"))
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text(model.range.label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.08)))
            }

            Text("\(meta.deviceName) · \(meta.modelName) · \(meta.osVersion)")
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.72))

            HStack {
                Text("\(model.from.formatted(date: .abbreviated, time: .shortened)) – \(model.to.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.65))
                Spacer()
                if let updatedAt = model.updatedAt {
                    Text(String(format: String(localized: "stats.report.snapshotAt"), updatedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
        }
    }

    // MARK: - 2. 综合结论与状态评分

    private var conclusionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conclusion.headline)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = conclusion.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.75))
                }
                Text(String(localized: "stats.report.conclusion.scope"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.04)))

            HStack(spacing: 16) {
                if let result = model.healthScore {
                    let display = StatisticsHealthScore.displayScore(result.score, hasPressureEvents: !model.events.isEmpty)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(display) \(String(localized: "stats.r.pts", defaultValue: "分")) · \(result.level.title)")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                        let dimText = result.dimensions.map { "\($0.name): \($0.rawText)" }.joined(separator: "  ")
                        if !dimText.isEmpty {
                            Text(dimText)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.black.opacity(0.65))
                        }
                    }
                } else {
                    Text(model.healthScoreNilReason ?? String(localized: "stats.r.healthScoreInsufficient"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.65))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let cov = model.coveragePercent {
                        Text(String(format: String(localized: "stats.r.coverageSummary", defaultValue: "数据完整度 %.1f%%"), cov))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                    }
                    if let notice = model.systemQualityNotice {
                        Text(notice)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - 3. 核心资源指标网格

    private var coreMetricsSection: some View {
        let items: [(title: String, value: String, sub: String?)] = [
            (
                String(localized: "stats.metrics.cpu", defaultValue: "CPU"),
                model.cpu.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                model.cpu.peakUsage.map { String(format: String(localized: "report.ui.peakUsage"), $0) }
            ),
            (
                String(localized: "stats.metrics.gpu", defaultValue: "GPU"),
                model.gpu.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—",
                model.gpu.peakUsage.map { String(format: String(localized: "report.ui.peakUsage"), $0) }
            ),
            (
                String(localized: "stats.metrics.memoryUsage", defaultValue: "内存"),
                model.memory.memPctAvg.map { String(format: "%.1f%%", $0) } ?? (model.memory.usedAvgBytes.map { ReportUIHelper.formatBytes($0) } ?? "—"),
                model.memory.pressureAvgPercent.map { String(format: String(localized: "report.ui.avgPressure"), $0) }
            ),
            (
                String(localized: "stats.metrics.power", defaultValue: "功耗"),
                model.power.avgPowerWatts.map { String(format: "%.1f W", $0) } ?? "—",
                model.power.peakPowerWatts.map { String(format: String(localized: "report.ui.peakPower"), $0) }
            ),
            (
                String(localized: "overview.resources.network", defaultValue: "网络"),
                "↓ \(model.network.totalDownBytes.map(ReportUIHelper.formatVolume) ?? "—") / ↑ \(model.network.totalUpBytes.map(ReportUIHelper.formatVolume) ?? "—")",
                model.network.peakDownRate.map { String(localized: "report.ui.peakDownload") + ReportUIHelper.formatBytesRate($0) }
            ),
            (
                String(localized: "stats.metrics.disk", defaultValue: "磁盘"),
                "\(model.disk.totalReadBytes.map(ReportUIHelper.formatVolume) ?? "—") / \(model.disk.totalWriteBytes.map(ReportUIHelper.formatVolume) ?? "—")",
                model.disk.peakReadRate.map { String(localized: "report.ui.peakRead") + ReportUIHelper.formatBytesRate($0) }
            ),
            (
                String(localized: "stats.r.secThermal", defaultValue: "热压力"),
                model.thermal.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? StatisticsDisplayFormat.thermalStateLabel(model.thermal.cpuThermalAvg),
                model.thermal.fanAvgRPM.map { String(format: String(localized: "report.ui.fanSpeed"), $0) } ?? (model.thermal.hasFans ? nil : String(localized: "report.ui.fanless"))
            ),
            (
                String(localized: "stats.r.secAppsTitle", defaultValue: "应用排行"),
                model.apps.cpuList.first?.name ?? "—",
                model.apps.cpuList.first.map { String(localized: "report.ui.topCPU") + $0.valueText }
            )
        ]

        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "report.print.coreMetrics", defaultValue: "核心指标汇总"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                        Text(item.value)
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(2)
                        if let sub = item.sub {
                            Text(sub)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.black.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.14), lineWidth: 0.75))
                }
            }
        }
    }

    // MARK: - 4. 系统压力事件

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(String(localized: "stats.r.secEvents", defaultValue: "压力警告"))
            VStack(spacing: 4) {
                ForEach(model.events.prefix(20)) { event in
                    HStack(spacing: 8) {
                        Text(event.kind.title)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 68, alignment: .leading)
                        Text(event.state.label)
                            .font(.system(size: 9))
                            .frame(width: 52, alignment: .leading)
                        Text("\(ReportUIHelper.formatDateTime(event.start)) – \(ReportUIHelper.formatDateTime(event.end))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.7))
                        Spacer()
                        Text(StatisticsDisplayFormat.duration(event.pressureSeconds))
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.35)
                }
            }
        }
    }

    // MARK: - 5. 智能洞察

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(String(localized: "stats.r.secInsights", defaultValue: "智能洞察"))
            ForEach(model.insights) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(item.title)")
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .padding(.leading, 10)
                }
            }
        }
    }

    // MARK: - 6. 应用排行摘要

    private var hasAnyAppRanking: Bool {
        !model.apps.cpuList.isEmpty || !model.apps.memList.isEmpty || !model.apps.gpuList.isEmpty
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(String(localized: "stats.r.secAppsTitle", defaultValue: "应用排行"))
            HStack(alignment: .top, spacing: 12) {
                if !model.apps.cpuList.isEmpty {
                    appColumn(title: String(localized: "stats.r.kCpu", defaultValue: "CPU 消耗"), items: Array(model.apps.cpuList.prefix(8)))
                }
                if !model.apps.memList.isEmpty {
                    appColumn(title: String(localized: "stats.r.kMem", defaultValue: "内存占用"), items: Array(model.apps.memList.prefix(8)))
                }
            }
        }
    }

    private func appColumn(title: String, items: [ReportAppRankingItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HStack {
                    Text("\(idx + 1). \(item.name)")
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                    Spacer()
                    Text(item.valueText)
                        .font(.system(size: 9.5, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 7. 硬件概况

    private func hardwareIdentitySection(hardware: HardwareInventory) -> some View {
        let facts = hardware.categories
            .first(where: { $0.id == "this-mac" })?
            .groups.first(where: { $0.id == "identity" })?
            .facts ?? []
        return Group {
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle(String(localized: "stats.r.kThisMac", defaultValue: "本机规格"))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                            HStack {
                                Text(fact.label.resolve(hwText))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Color.black.opacity(0.6))
                                Spacer()
                                Text(fact.value ?? "—")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 8. 口径脚注

    private var footerScopeSection: some View {
        Text(String(localized: "stats.export.scopeNote", defaultValue: "应用数值来自每分钟前列采样，属估算；含旧日汇总的时段无法还原到分钟。"))
            .font(.system(size: 9))
            .foregroundStyle(Color.black.opacity(0.55))
            .padding(.top, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .padding(.top, 2)
    }
}
