import AppKit
import Charts
import SwiftUI

/// 应用排行与高负载告警视图：支持 CPU/内存/GPU/网络/磁盘分类排行、相对占用对比条、多维应用画像、逐日趋势与告警事件联动。
struct ReportAppsView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedTab: AppRankingTab = .cpu
    /// 当前展开详情的应用标识。
    @State private var expandedAppKey: String? = ProcessInfo.processInfo
        .environment["HAGIMI_REPORT_EXPAND_APP"]
    @State private var hoveredAppTrendDate: Date?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    private var searchText: Binding<String> { $viewModel.appSearchText }
    private var sortOrder: Binding<ReportAppRankingFilter.SortOrder> { $viewModel.appSortOrder }
    private var showsAllEntries: Binding<Bool> { $viewModel.appsShowsAll }

    enum AppRankingTab: String, CaseIterable, Identifiable {
        case cpu
        case memory
        case gpu
        #if DIRECT_DISTRIBUTION
        case disk
        case network
        #endif

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cpu: return String(localized: "stats.r.kCpu", defaultValue: "CPU 消耗")
            case .memory: return String(localized: "stats.r.kMem", defaultValue: "内存占用")
            case .gpu: return String(localized: "stats.r.kGpu", defaultValue: "GPU 消耗")
            #if DIRECT_DISTRIBUTION
            case .disk: return String(localized: "stats.r.tabDisk", defaultValue: "磁盘读写")
            case .network: return String(localized: "stats.r.railNet", defaultValue: "网络流量")
            #endif
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 16) {
                if viewModel.focusedEventIsMissing {
                    missingRecordNotice
                }

                rankingCard

                if let alerts = viewModel.rangeModel?.apps.highLoadAlerts, !alerts.isEmpty {
                    alertsCard(alerts: alerts)
                        .id("appAlertsAnchor")
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                applyFocusedContext()
                if viewModel.scrollToAppAlertsToken != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { proxy.scrollTo("appAlertsAnchor", anchor: .top) }
                    }
                }
            }
            .onChange(of: viewModel.focusedMetric) { _, _ in applyFocusedContext() }
            .onChange(of: viewModel.scrollToAppAlertsToken) { _, token in
                guard token != nil else { return }
                withAnimation { proxy.scrollTo("appAlertsAnchor", anchor: .top) }
            }
        }
    }

    private var missingRecordNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
            Text(String(localized: "stats.report.record-missing"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func applyFocusedContext() {
        if let appKey = viewModel.focusedAppKey {
            expandedAppKey = appKey
        }
        guard let metric = viewModel.focusedMetric else { return }
        let tab: AppRankingTab
        switch metric {
        case .cpu: tab = .cpu
        case .memory: tab = .memory
        case .gpu: tab = .gpu
        case .network:
            #if DIRECT_DISTRIBUTION
            tab = .network
            #else
            tab = .cpu
            #endif
        }
        if AppRankingTab.allCases.contains(tab) {
            selectedTab = tab
        }
    }

    // MARK: - 1. 应用排行卡片

    private var rankingCard: some View {
        let entries = currentEntries
        let visible = displayedEntries
        let maxMetricVal = entries.map { sortOrder.wrappedValue == .peak ? $0.peakValue : $0.value }.max() ?? 1.0

        return ReportCardView(
            title: String(localized: "stats.r.secAppsTitle", defaultValue: "应用活动排行"),
            icon: "app.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ReportNavigationPicker(
                        title: "",
                        selection: $selectedTab,
                        options: AppRankingTab.allCases.map { ReportSegmentOption(value: $0, label: $0.label) }
                    )
                    .fixedSize()

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scopeNoticeText)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        if viewModel.rangeModel?.apps.hasLegacyNameIdentities == true {
                            Text(String(localized: "stats.r.legacyIdentityNotice"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Toggle(isOn: $viewModel.includeSystemApps) {
                        Text(String(localized: "stats.report.includeSystemApps", defaultValue: "包含系统应用"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack(spacing: 12) {
                    // 规范搜索输入框容器
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField(
                            String(localized: "stats.report.search.placeholder", defaultValue: "搜索应用"),
                            text: searchText
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .accessibilityLabel(Text(String(localized: "stats.report.search.placeholder", defaultValue: "搜索应用")))

                        if !searchText.wrappedValue.isEmpty {
                            Button {
                                searchText.wrappedValue = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(String(localized: "stats.report.search.clear", defaultValue: "清除搜索")))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: 250)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.insetFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(palette.cardBorder, lineWidth: 0.75)
                    )

                    Spacer()

                    Picker("", selection: sortOrder) {
                        ForEach(ReportAppRankingFilter.SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .accessibilityLabel(Text(String(localized: "stats.report.sort.label", defaultValue: "排序方式")))

                    if !showsAllEntries.wrappedValue, searchText.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, totalEntryCount > visible.count {
                        Button {
                            showsAllEntries.wrappedValue = true
                            viewModel.appsRenderLimit = ReportAppRankingFilter.renderBatch
                        } label: {
                            Text(String(localized: "stats.report.showAllApps \(totalEntryCount)"))
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                    }
                }

                if entries.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyApps", defaultValue: "所选范围内无应用采样明细"))
                } else if visible.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.report.search.empty", defaultValue: "没有匹配的应用"))
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, app in
                            let currentVal = sortOrder.wrappedValue == .peak ? app.peakValue : app.value
                            let ratio = maxMetricVal > 0 ? min(1.0, max(0.0, currentVal / maxMetricVal)) : 0.0
                            appRow(index: index + 1, app: app, barRatio: ratio)
                            if expandedAppKey == app.appKey {
                                appDetail(for: app)
                            }
                            if index < visible.count - 1 {
                                Divider().opacity(0.25)
                            }
                        }

                        if visible.count < currentEntries.count {
                            Button {
                                viewModel.appsRenderLimit += ReportAppRankingFilter.renderBatch
                            } label: {
                                Text(String(localized: "stats.report.loadMore \(currentEntries.count - visible.count)"))
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.link)
                            .padding(.top, 6)
                        }
                    }
                }
            }
        }
    }

    private var scopeNoticeText: String {
        if viewModel.selectedRange == .year {
            return String(localized: "stats.r.appsScopeNotice", defaultValue: "注：应用历史保留最多近 60 天，按整日汇总")
        } else if viewModel.isSingleDaySelected {
            return viewModel.selectedRange == .today
                ? String(localized: "stats.r.appsSampleNoticeToday", defaultValue: "注：数据源自每分钟前列采样，实时统计")
                : String(localized: "stats.r.appsSampleNoticeSingleDay", defaultValue: "注：数据源自每分钟前列采样，单日统计")
        } else {
            return String(localized: "stats.r.appsSampleNotice", defaultValue: "注：数据源自每分钟前列采样，按日汇总")
        }
    }

    private var currentEntries: [ReportAppRankingItem] {
        guard let apps = viewModel.rangeModel?.apps else { return [] }
        let rawList: [ReportAppRankingItem] = {
            switch selectedTab {
            case .cpu: return apps.cpuList
            case .memory: return apps.memList
            case .gpu: return apps.gpuList
            #if DIRECT_DISTRIBUTION
            case .disk: return apps.diskList
            case .network: return apps.netList
            #endif
            }
        }()

        return ReportAppRankingFilter.apply(
            to: rawList,
            includeSystemApps: viewModel.includeSystemApps,
            query: searchText.wrappedValue,
            sortOrder: sortOrder.wrappedValue
        )
    }

    private var totalEntryCount: Int { currentEntries.count }

    /// 搜索时自动呈现全部匹配项（受 renderLimit 保护），无搜索时按折叠/全部模式裁剪。
    private var displayedEntries: [ReportAppRankingItem] {
        let isSearching = !searchText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ReportAppRankingFilter.visible(
            entries: currentEntries,
            showsAll: showsAllEntries.wrappedValue || isSearching,
            focusedAppKey: viewModel.focusedAppKey,
            expandedLimit: viewModel.appsRenderLimit
        )
    }

    private func appRow(index: Int, app: ReportAppRankingItem, barRatio: Double) -> some View {
        let isExpanded = expandedAppKey == app.appKey
        let tabTint = trendTint(Self.trendMetric(for: selectedTab))

        return ReportAppRankingRowView(
            index: index,
            app: app,
            barRatio: barRatio,
            tint: tabTint,
            isExpanded: isExpanded,
            iconView: AnyView(appIconView(appKey: app.appKey, data: app.iconData)),
            onToggle: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedAppKey = isExpanded ? nil : app.appKey
                }
            }
        )
    }

    // MARK: - 应用详情（多维画像、逐日趋势与事件列表）

    @ViewBuilder
    private func appDetail(for app: ReportAppRankingItem) -> some View {
        let episodes = (viewModel.rangeModel?.apps.highLoadAlerts ?? [])
            .first { $0.appKey == app.appKey }?.episodes ?? []

        VStack(alignment: .leading, spacing: 8) {
            // 该应用在本期的多维资源画像芯片
            if let rankings = viewModel.rangeModel?.apps {
                let profile = ReportDataAggregator.appCrossMetricProfile(appKey: app.appKey, in: rankings)
                if profile.hasAny {
                    appProfileStrip(profile)
                }
            }

            Text(String(localized: "stats.report.appDetail.source"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if viewModel.rangeModel?.apps.hasLegacyNameIdentities == true {
                Text(String(localized: "stats.r.legacyIdentityNotice"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if let model = viewModel.rangeModel, let notice = model.systemQualityNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            appTrend(app)

            if episodes.isEmpty {
                Text(String(localized: "stats.report.appDetail.noEvents"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
        .padding(.leading, 42)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.insetFill)
        )
    }

    private func appProfileStrip(_ profile: ReportAppProfile) -> some View {
        HStack(spacing: 8) {
            if let cpu = profile.cpuText {
                profileChip(icon: "cpu", label: "CPU", value: cpu, tint: palette.cpu)
            }
            if let mem = profile.memoryText {
                profileChip(icon: "memorychip", label: String(localized: "stats.r.kMem", defaultValue: "内存"), value: mem, tint: palette.memory)
            }
            if let gpu = profile.gpuText {
                profileChip(icon: "display", label: "GPU", value: gpu, tint: palette.gpu)
            }
            if let disk = profile.diskText {
                profileChip(icon: "internaldrive", label: String(localized: "stats.metrics.disk", defaultValue: "磁盘"), value: disk, tint: palette.diskRead)
            }
            if let net = profile.networkText {
                profileChip(icon: "network", label: String(localized: "overview.resources.network", defaultValue: "网络"), value: net, tint: palette.networkDown)
            }
        }
    }

    private func profileChip(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(label): \(value)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.10)))
    }

    // MARK: - 原生图标渲染与兜底

    private func appIconView(appKey: String, data: Data?) -> some View {
        Group {
            if let image = ReportIconProvider.shared.icon(forAppKey: appKey, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                let symbol = ReportIconProvider.shared.fallbackSymbol(forAppKey: appKey)
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 告警事件证据行

    private func episodeRow(_ episode: ProcessAlertEpisode) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(episode.metric.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Text(String(localized: "stats.r.episodeAverage \(Self.metricValue(episode.averageUsage, episode.metric))"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(String(localized: "stats.r.episodePeak \(Self.metricValue(episode.peakUsage, episode.metric))"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Text(String(localized: "stats.r.episodeDuration \(StatisticsDisplayFormat.duration(episode.continuousHighSeconds))"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)

                Text(episodeStatusText(episode))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(Self.episodeObservedRangeText(
                    start: ReportUIHelper.formatDateTime(episode.startedAt),
                    end: ReportUIHelper.formatDateTime(episode.endedAt ?? episode.lastSeenAt)
                ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if episode.eventSpanSeconds > episode.continuousHighSeconds + 1 {
                    Text(String(localized: "stats.r.episodeSpan \(StatisticsDisplayFormat.duration(episode.eventSpanSeconds))"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Text(String(localized: "stats.r.episodeObservations \(episode.observationCount)"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 44)

            episodeDistribution(episode)

            Text(String(localized: "stats.r.episodeDistributionNote"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 44)
        }
    }

    nonisolated static func episodeObservedRangeText(start: String, end: String, locale: Locale = .current) -> String {
        String(localized: "stats.r.episodeObserved \(start) – \(end)", locale: locale)
    }

    /// 该应用在本期的逐日趋势（修复双倍缩进并格式化 Y 轴单位）。
    @ViewBuilder
    private func appTrend(_ app: ReportAppRankingItem) -> some View {
        if let model = viewModel.rangeModel,
           let process = viewModel.snapshot?.process {
            let trendMetric = Self.trendMetric(for: selectedTab)
            let series = ReportDataAggregator.appTrendSeries(
                dailyRows: process.dailyRows,
                appKey: app.appKey,
                trendMetric: trendMetric,
                from: model.from,
                to: model.to
            )
            if series.count >= 2 {
                let hoveredPt = hoveredAppTrendDate.flatMap { target in
                    series.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(localized: "stats.report.appDetail.trendTitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let hoveredPt {
                            Text("\(ReportUIHelper.formatDateShort(hoveredPt.date)): \(formatAppTrendValue(hoveredPt.value, metric: trendMetric))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }

                    Chart {
                        ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Day", point.date),
                                y: .value("Value", point.value),
                                series: .value("App", app.appKey)
                            )
                            .foregroundStyle(trendTint(trendMetric))
                            .interpolationMethod(.monotone)
                        }
                        if let hoveredPt {
                            RuleMark(x: .value("Hover", hoveredPt.date))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            PointMark(x: .value("Hover", hoveredPt.date), y: .value("Val", hoveredPt.value))
                                .foregroundStyle(trendTint(trendMetric))
                                .symbolSize(30)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                            AxisGridLine()
                            AxisValueLabel {
                                if let num = val.as(Double.self) {
                                    Text(formatAppTrendValue(num, metric: trendMetric))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let frame = geo[plotFrame]
                                        let x = location.x - frame.origin.x
                                        guard x >= 0, x <= frame.size.width else {
                                            hoveredAppTrendDate = nil
                                            return
                                        }
                                        hoveredAppTrendDate = proxy.value(atX: x, as: Date.self)
                                    case .ended:
                                        hoveredAppTrendDate = nil
                                    }
                                }
                        }
                    }
                    .frame(height: 95)
                    .frame(maxWidth: 520, alignment: .leading)
                    .accessibilityLabel(Text(String(localized: "stats.report.appDetail.trendA11y \(app.name)")))
                }
            } else if !series.isEmpty {
                Text(String(localized: "stats.report.appDetail.trendTooShort"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatAppTrendValue(_ val: Double, metric: ReportDataAggregator.AppTrendMetric) -> String {
        switch metric {
        case .cpu, .gpu:
            return String(format: "%.1f%%", val)
        case .memory:
            return ReportUIHelper.formatBytes(val)
        case .disk, .network:
            return ReportUIHelper.formatVolume(val)
        }
    }

    @ViewBuilder
    private func episodeDistribution(_ episode: ProcessAlertEpisode) -> some View {
        let bands = Self.bandLabels(for: episode.metric)
        let seconds = [episode.tier1Seconds, episode.tier2Seconds, episode.tier3Seconds]
        let total = seconds.reduce(0, +)
        if total > 0 {
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(seconds.enumerated()), id: \.offset) { pair in
                            let index = pair.offset
                            let value = pair.element
                            if value > 0 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(bandTint(episode.metric).opacity(Self.bandOpacity(index: index)))
                                    .frame(width: max(2, geo.size.width * value / total))
                            }
                        }
                    }
                }
                .frame(height: 6)

                HStack(spacing: 8) {
                    ForEach(Array(seconds.enumerated()), id: \.offset) { pair in
                        let index = pair.offset
                        let value = pair.element
                        if value > 0 {
                            Text("\(bands[index]): \(StatisticsDisplayFormat.duration(value))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.leading, 44)
        }
    }

    private static func trendMetric(for tab: AppRankingTab) -> ReportDataAggregator.AppTrendMetric {
        switch tab {
        case .cpu: .cpu
        case .memory: .memory
        case .gpu: .gpu
        #if DIRECT_DISTRIBUTION
        case .disk: .disk
        case .network: .network
        #endif
        }
    }

    private func trendTint(_ metric: ReportDataAggregator.AppTrendMetric) -> Color {
        switch metric {
        case .cpu: return palette.cpu
        case .gpu: return palette.gpu
        case .memory: return palette.memory
        case .network: return palette.networkDown
        case .disk: return palette.diskRead
        }
    }

    private func bandTint(_ metric: ProcessAlertEpisode.Metric) -> Color {
        switch metric {
        case .cpu: return palette.cpu
        case .gpu: return palette.gpu
        case .memory: return palette.memory
        case .network: return palette.networkDown
        }
    }

    static func bandOpacity(index: Int) -> Double {
        0.25 + Double(index) * 0.3
    }

    static func bandLabels(for metric: ProcessAlertEpisode.Metric) -> [String] {
        StatisticsMetricDefinition.bandLabels(for: metric)
    }

    private func episodeStatusText(_ episode: ProcessAlertEpisode) -> String {
        switch episode.state {
        case .ongoing:
            return String(localized: "stats.r.episodeOngoing")
        case .recovered:
            return String(localized: "stats.r.episodeRecovered")
        case .interrupted:
            let reason: String = switch episode.endReason {
            case .observationGap: String(localized: "stats.r.episodeReasonGap")
            case .notObserved: String(localized: "stats.r.episodeReasonNotObserved")
            case .sourceFailure: String(localized: "stats.r.episodeReasonSourceFailed")
            case .processExited: String(localized: "stats.r.episodeReasonExited")
            case .suspended: String(localized: "stats.r.episodeReasonSuspended")
            case .replaced: String(localized: "stats.r.episodeReasonReplaced")
            case .recovered, nil: String(localized: "stats.r.episodeReasonUnknown")
            }
            return String(localized: "stats.r.episodeInterrupted \(reason)")
        }
    }

    static func displayIdentity(_ appKey: String) -> String {
        for prefix in ["bundle:", "systemExecutable:", "unresolved:"] where appKey.hasPrefix(prefix) {
            return String(appKey.dropFirst(prefix.count))
        }
        return appKey
    }

    static func metricValue(_ value: Double, _ metric: ProcessAlertEpisode.Metric) -> String {
        StatisticsDisplayFormat.applicationObservationValue(value, metric: metric)
    }

    private func alertsCard(alerts: [ReportHighLoadAppGroup]) -> some View {
        ReportCardView(
            title: String(localized: "stats.r.alertsTitle", defaultValue: "高负载告警记录"),
            icon: "exclamationmark.triangle.fill"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "stats.r.alertsContemporaneousNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(alerts) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            appIconView(appKey: alert.appKey, data: alert.iconData)

                            Text(alert.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(String(localized: "stats.r.alertCount \(alert.episodes.count)"))
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.base.severityTint(for: .warning).opacity(0.14))
                                .foregroundStyle(palette.base.severityTint(for: .warning))
                                .clipShape(Capsule())

                            Text(String(localized: "stats.r.alertMaxDuration \(alert.maxDurationMinutes)"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if let start = alert.earliestStart {
                                Text(ReportUIHelper.formatDateTime(start))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        ForEach(alert.episodes) { episode in
                            episodeRow(episode)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// 整行可点击的应用排行行组件（包含悬停底色、相对用量对比条与展开指示箭头）。
private struct ReportAppRankingRowView: View {
    let index: Int
    let app: ReportAppRankingItem
    let barRatio: Double
    let tint: Color
    let isExpanded: Bool
    let iconView: AnyView
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(index <= 3 ? Color.primary : Color.secondary)
                    .frame(width: 18, alignment: .trailing)

                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(ReportAppsView.displayIdentity(app.appKey))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(app.appKey)
                }
                .frame(minWidth: 160, maxWidth: 280, alignment: .leading)

                if let hint = app.tierHint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // 相对用量比例条 + 数值
                VStack(alignment: .trailing, spacing: 3) {
                    Text(app.valueText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)

                    GeometryReader { geo in
                        ZStack(alignment: .trailing) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(tint.opacity(0.70))
                                .frame(width: max(3, geo.size.width * barRatio))
                        }
                    }
                    .frame(width: 84, height: 3.5)
                }
                .frame(minWidth: 92, alignment: .trailing)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.045) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(app.name))
        .accessibilityHint(Text(isExpanded
            ? String(localized: "stats.report.appDetail.collapse")
            : String(localized: "stats.report.appDetail.expand")))
    }
}
