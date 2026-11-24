import Charts
import SwiftUI

/// 原生打印与 PDF 导出专用分页友好排版视图（纯原生 SwiftUI + Swift Charts 渲染，浅底高对比，不依赖 WKWebView）。
enum ReportPrintableView {
    /// 打印或导出时的原子排版块（保证分页断页落在块间，不截断正文文字或图表）。
    struct PrintableBlock: Identifiable {
        let id: String
        let view: AnyView
        /// 若为 true，分页打包时尽量避免将该标题块孤立留在页底。
        let keepWithNext: Bool

        init(id: String, keepWithNext: Bool = false, @ViewBuilder content: () -> some View) {
            self.id = id
            self.keepWithNext = keepWithNext
            self.view = AnyView(content())
        }
    }

    private static func makeConclusion(model: ReportActiveRangeModel) -> ReportPeriodConclusion.Summary {
        ReportPeriodConclusion.summary(
            events: model.events,
            appAlertCount: model.apps.highLoadAlerts.count,
            coveredSeconds: model.coveredSeconds,
            quality: model.quality
        )
    }

    /// 按标题、图表和事件行构造可独立分页的排版块。
    @MainActor
    static func printableBlocks(
        model: ReportActiveRangeModel,
        meta: ReportMeta,
        hardware: HardwareInventory?
    ) -> [PrintableBlock] {
        var blocks: [PrintableBlock] = []
        let conclusion = makeConclusion(model: model)

        blocks.append(PrintableBlock(id: "header-conclusion") {
            VStack(alignment: .leading, spacing: 14) {
                headerSection(model: model, meta: meta)
                Divider()
                conclusionSection(model: model, conclusion: conclusion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.black)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        })

        blocks.append(PrintableBlock(id: "core-metrics") {
            coreMetricsSection(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.black)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        })

        let sourceCount = model.rows.count
        let cpuLoad = model.chartCache.cpuAvg.smoothed(targetMaxPoints: 180, referencePointCount: sourceCount)
        let gpuLoad = model.chartCache.gpuAvg.smoothed(targetMaxPoints: 180, referencePointCount: sourceCount)
        let memPressure = model.chartCache.memPressure.smoothed(targetMaxPoints: 180, referencePointCount: sourceCount)
        let memUsage = model.chartCache.memUsagePct.smoothed(targetMaxPoints: 180, referencePointCount: sourceCount)
        if !cpuLoad.isEmpty || !gpuLoad.isEmpty || !memPressure.isEmpty || !memUsage.isEmpty {
            blocks.append(PrintableBlock(id: "trends") {
                trendsSection(
                    model: model,
                    cpuLoad: cpuLoad,
                    gpuLoad: gpuLoad,
                    memPressure: memPressure,
                    memUsage: memUsage
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.black)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            })
        }

        if !model.events.isEmpty {
            blocks.append(PrintableBlock(id: "events-header", keepWithNext: true) {
                sectionTitle(String(format: "%@ (%d)", String(localized: "stats.r.secEvents", defaultValue: "压力警告"), model.events.count))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.black)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            })
            for (index, event) in model.events.enumerated() {
                blocks.append(PrintableBlock(id: "event-\(index)-\(event.id)") {
                    eventRow(event: event, index: index + 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.black)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                })
            }
        }

        if !model.insights.isEmpty {
            blocks.append(PrintableBlock(id: "insights-header", keepWithNext: true) {
                sectionTitle(String(localized: "stats.r.secInsights", defaultValue: "智能洞察"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.black)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            })
            for (index, item) in model.insights.enumerated() {
                blocks.append(PrintableBlock(id: "insight-\(index)-\(item.id)") {
                    insightRow(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.black)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                })
            }
        }

        if !model.apps.cpuList.isEmpty || !model.apps.memList.isEmpty || !model.apps.gpuList.isEmpty {
            blocks.append(PrintableBlock(id: "apps") {
                topAppsSection(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.black)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            })
        }

        if let hardware, hasHardwareIdentity(hardware) {
            blocks.append(PrintableBlock(id: "hardware") {
                hardwareIdentitySection(hardware: hardware)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color.black)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            })
        }

        blocks.append(PrintableBlock(id: "footer") {
            footerScopeSection
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.black)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        })

        return blocks
    }

    // MARK: - 1. 页眉

    private static func headerSection(model: ReportActiveRangeModel, meta: ReportMeta) -> some View {
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

    private static func conclusionSection(model: ReportActiveRangeModel, conclusion: ReportPeriodConclusion.Summary) -> some View {
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

    private static func coreMetricsSection(model: ReportActiveRangeModel) -> some View {
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

    // MARK: - 4. 核心负载与内存趋势图（高对比静默矢量渲染）

    private static func trendsSection(
        model: ReportActiveRangeModel,
        cpuLoad: ReportChartSeries,
        gpuLoad: ReportChartSeries,
        memPressure: ReportChartSeries,
        memUsage: ReportChartSeries
    ) -> some View {
        let cpuColor = Color(red: 0.12, green: 0.45, blue: 0.85)
        let gpuColor = Color(red: 0.56, green: 0.30, blue: 0.80)
        let memColor = Color(red: 0.09, green: 0.60, blue: 0.46)
        let pressureColor = Color(red: 0.85, green: 0.42, blue: 0.08)

        let loadDescriptors: [(title: String, color: Color, series: ReportChartSeries)] = [
            (String(localized: "stats.metrics.cpu", defaultValue: "CPU"), cpuColor, cpuLoad),
            (String(localized: "stats.metrics.gpu", defaultValue: "GPU"), gpuColor, gpuLoad)
        ].filter { !$0.series.isEmpty }

        let memDescriptors: [(title: String, color: Color, series: ReportChartSeries)] = [
            (String(localized: "stats.metrics.memoryUsage", defaultValue: "内存"), memColor, memUsage),
            (String(localized: "stats.r.kMemPressure", defaultValue: "内存压力"), pressureColor, memPressure)
        ].filter { !$0.series.isEmpty }

        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(String(localized: "report.print.trends", defaultValue: "负载与压力趋势"))

            if !loadDescriptors.isEmpty {
                printableTrendChart(
                    descriptors: loadDescriptors,
                    isSingleDay: model.isSingleDay
                )
            }

            if !memDescriptors.isEmpty {
                printableTrendChart(
                    descriptors: memDescriptors,
                    isSingleDay: model.isSingleDay
                )
            }
        }
        .padding(.top, 2)
    }

    private static func printableTrendChart(
        descriptors: [(title: String, color: Color, series: ReportChartSeries)],
        isSingleDay: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ForEach(descriptors, id: \.title) { desc in
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(desc.color)
                            .frame(width: 10, height: 3)
                        Text(desc.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.75))
                    }
                }
            }

            Chart {
                ForEach(descriptors, id: \.title) { desc in
                    ForEach(Array(desc.series.segments.enumerated()), id: \.offset) { segIdx, segment in
                        let seriesKey = "\(desc.title)-seg-\(segIdx)"
                        ForEach(segment) { pt in
                            if let val = pt.value {
                                if segment.count == 1 {
                                    PointMark(x: .value("Time", pt.date), y: .value("Value", val))
                                        .foregroundStyle(desc.color)
                                        .symbolSize(12)
                                } else {
                                    LineMark(
                                        x: .value("Time", pt.date),
                                        y: .value("Value", val),
                                        series: .value("Series", seriesKey)
                                    )
                                    .foregroundStyle(desc.color)
                                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                                }
                            }
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { val in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.12))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(Int(v))%")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: isSingleDay ? 6 : 7)) { val in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.08))
                    AxisValueLabel {
                        if let date = val.as(Date.self) {
                            Text(isSingleDay ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.month().day()))
                                .font(.system(size: 8))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                    }
                }
            }
            .frame(height: 112)
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.14), lineWidth: 0.75))
    }

    // MARK: - 5. 完整压力事件行（不静默截断）

    private static func eventRow(event: ReportEventItem, index: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(index)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.5))
                    .frame(width: 24, alignment: .leading)
                Text(event.kind.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .frame(width: 64, alignment: .leading)
                Text(event.state.label)
                    .font(.system(size: 9))
                    .frame(width: 48, alignment: .leading)
                Text("\(ReportUIHelper.formatDateTime(event.start)) – \(ReportUIHelper.formatDateTime(event.end))")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.72))
                Spacer()
                Text(StatisticsDisplayFormat.duration(event.pressureSeconds))
                    .font(.system(size: 9, design: .monospaced))
            }
            Divider().opacity(0.35)
        }
    }

    // MARK: - 6. 智能洞察

    private static func insightRow(item: ReportInsightItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("• \(item.title)")
                .font(.system(size: 10, weight: .semibold))
            Text(item.detail)
                .font(.system(size: 9.5))
                .foregroundStyle(Color.black.opacity(0.72))
                .padding(.leading, 10)
        }
    }

    // MARK: - 7. 应用排行摘要

    private static func topAppsSection(model: ReportActiveRangeModel) -> some View {
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

    private static func appColumn(title: String, items: [ReportAppRankingItem]) -> some View {
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

    // MARK: - 8. 硬件概况

    private static func hasHardwareIdentity(_ hardware: HardwareInventory) -> Bool {
        let facts = hardware.categories
            .first(where: { $0.id == "this-mac" })?
            .groups.first(where: { $0.id == "identity" })?
            .facts ?? []
        return !facts.isEmpty
    }

    private static func hardwareIdentitySection(hardware: HardwareInventory) -> some View {
        let facts = hardware.categories
            .first(where: { $0.id == "this-mac" })?
            .groups.first(where: { $0.id == "identity" })?
            .facts ?? []
        return VStack(alignment: .leading, spacing: 6) {
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

    // MARK: - 9. 口径脚注

    private static var footerScopeSection: some View {
        Text(String(localized: "stats.export.scopeNote", defaultValue: "应用数值来自每分钟前列采样，属估算；含旧日汇总的时段无法还原到分钟。"))
            .font(.system(size: 9))
            .foregroundStyle(Color.black.opacity(0.55))
            .padding(.top, 4)
    }

    private static func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .padding(.top, 4)
    }
}
