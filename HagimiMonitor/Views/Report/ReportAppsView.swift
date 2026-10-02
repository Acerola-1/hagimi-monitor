import AppKit
import Charts
import SwiftUI

/// 应用排行与高负载告警视图：支持 CPU/内存/GPU/网络分类排行、应用图标原生呈现与精准兜底、活跃档位提示与告警事件列表。
struct ReportAppsView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedTab: AppRankingTab = .cpu
    /// 当前展开详情的应用标识。
    @State private var expandedAppKey: String? = ProcessInfo.processInfo
        .environment["HAGIMI_REPORT_EXPAND_APP"]

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
        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            if viewModel.focusedEventIsMissing {
                missingRecordNotice
            }

            // 1. 分类选择与排行列表卡片
            rankingCard

            // 2. 高负载告警卡片（若有告警记录）
            if let alerts = viewModel.rangeModel?.apps.highLoadAlerts, !alerts.isEmpty {
                alertsCard(alerts: alerts)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { applyFocusedContext() }
        .onChange(of: viewModel.focusedMetric) { _, _ in applyFocusedContext() }
    }

    /// 深链目标事件已被删除时的明确说明，替代静默切换到其他应用。
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

    /// 把设置页传入的指标映射到排行分类，让用户落在刚看的那一项上。
    private func applyFocusedContext() {
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

        return ReportCardView(
            title: String(localized: "stats.r.secAppsTitle", defaultValue: "应用活动排行"),
            icon: "app.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // 分类切换选择器：统一使用系统液态玻璃胶囊导航样式
                    ReportNavigationPicker(
                        title: "",
                        selection: $selectedTab
                    ) {
                        ForEach(AppRankingTab.allCases) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
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

                    // 包含系统应用开关（默认开启，靠右放置）
                    Toggle(isOn: $viewModel.includeSystemApps) {
                        Text(String(localized: "stats.report.includeSystemApps", defaultValue: "包含系统应用"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField(
                        String(localized: "stats.report.search.placeholder", defaultValue: "搜索应用"),
                        text: searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(maxWidth: 220)
                    // 搜索框本身不含可见标签，必须补辅助功能名称。
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

                    Spacer()

                    Picker("", selection: sortOrder) {
                        ForEach(ReportAppRankingFilter.SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    // 排序选择器隐藏了标签，补上辅助功能名称，否则读屏只报「弹出式按钮」。
                    .accessibilityLabel(Text(String(localized: "stats.report.sort.label", defaultValue: "排序方式")))

                    if !showsAllEntries.wrappedValue, totalEntryCount > displayedEntries.count {
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
                } else if displayedEntries.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.report.search.empty", defaultValue: "没有匹配的应用"))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(displayedEntries.enumerated()), id: \.element.id) { index, app in
                            appRow(index: index + 1, app: app)
                            if expandedAppKey == app.appKey {
                                appDetail(for: app)
                            }
                            if index < displayedEntries.count - 1 {
                                Divider().opacity(0.3)
                            }
                        }

                        if hasMoreEntries {
                            Button {
                                viewModel.appsRenderLimit += ReportAppRankingFilter.renderBatch
                            } label: {
                                Text(String(localized: "stats.report.loadMore \(currentEntries.count - displayedEntries.count)"))
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

    /// 当前分类的全部已记录应用，只应用系统过滤与搜索，不做数量截断。
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

    /// 列表条目按视图模型限制增量渲染。
    private var displayedEntries: [ReportAppRankingItem] {
        ReportAppRankingFilter.visible(
            entries: currentEntries,
            showsAll: showsAllEntries.wrappedValue,
            focusedAppKey: viewModel.focusedAppKey,
            expandedLimit: viewModel.appsRenderLimit
        )
    }

    /// 是否还有未渲染的条目。
    private var hasMoreEntries: Bool {
        displayedEntries.count < currentEntries.count
    }

    private func appRow(index: Int, app: ReportAppRankingItem) -> some View {
        HStack(spacing: 12) {
            // 序号
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(index <= 3 ? Color.primary : Color.secondary)
                .frame(width: 18, alignment: .trailing)

            // 图标渲染
            appIconView(appKey: app.appKey, data: app.iconData)

            // 应用名与可读标识
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(Self.displayIdentity(app.appKey))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(app.appKey)
            }
            .frame(minWidth: 160, maxWidth: 300, alignment: .leading)

            // 档位提示说明
            if let hint = app.tierHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 主指标数值
            Text(app.valueText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 80, alignment: .trailing)

            // 展开该应用的详情：来源覆盖、指标趋势与事件列表。
            Button {
                expandedAppKey = expandedAppKey == app.appKey ? nil : app.appKey
            } label: {
                Image(systemName: expandedAppKey == app.appKey ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expandedAppKey == app.appKey
                ? String(localized: "stats.report.appDetail.collapse")
                : String(localized: "stats.report.appDetail.expand"))
        }
        .padding(.vertical, 4)
    }

    // MARK: - 应用详情（来源覆盖、指标趋势与事件列表）

    @ViewBuilder
    private func appDetail(for app: ReportAppRankingItem) -> some View {
        let episodes = (viewModel.rangeModel?.apps.highLoadAlerts ?? [])
            .first { $0.appKey == app.appKey }?.episodes ?? []

        VStack(alignment: .leading, spacing: 6) {
            // 数据来源与质量说明。
            Text(String(localized: "stats.report.appDetail.source"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if viewModel.rangeModel?.apps.hasLegacyNameIdentities == true {
                Text(String(localized: "stats.r.legacyIdentityNotice"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if let model = viewModel.rangeModel, let notice = model.qualityNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // 逐日趋势：应用数据的最小粒度是日汇总，因此按天给出，不伪造更细的分辨。
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
        .padding(.leading, 46)
        .padding(.vertical, 6)
    }

    // MARK: - 原生图标渲染与契约兜底 (R13)

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

    // MARK: - 2. 告警事件列表卡片 (R16 & R21: 真实只读告警语义)

    /// 单条指标事件的证据行：有效起止、有效高占用时长、均值/采样峰值、状态与结束原因。
    ///
    /// 有效高占用时长与事件跨度是两件事：缺口会让跨度更大，这里分别标注，
    /// 并给出观测次数，避免把次数读成时间。
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

            // 有效起止与观测次数：次数不等于时长，缺口不连线也不补时长。
            HStack(spacing: 8) {
                Text(String(localized: "stats.r.episodeObserved \(ReportUIHelper.formatDateTime(episode.startedAt)) – \(ReportUIHelper.formatDateTime(episode.endedAt ?? episode.lastSeenAt))"))
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

            // 档位分布：表示各量级持续了多久，不是时间线；零秒档位不显示。
            episodeDistribution(episode)

            Text(String(localized: "stats.r.episodeDistributionNote"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 44)
        }
        .padding(.leading, 34)
    }

    /// 该应用在本期的逐日趋势。没有数据时明确显示「无趋势数据」，不画空图。
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.report.appDetail.trendTitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

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
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 90)
                    .frame(maxWidth: 520, alignment: .leading)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .accessibilityLabel(Text(String(localized: "stats.report.appDetail.trendA11y \(app.name)")))
                }
                .padding(.leading, 46)
            } else if !series.isEmpty {
                Text(String(localized: "stats.report.appDetail.trendTooShort"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 46)
            }
        }
    }

    /// 档位分布条与图例。
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

    /// 当前分类对应的趋势指标类型。
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

    /// 趋势图使用的模块色。
    private func trendTint(_ metric: ReportDataAggregator.AppTrendMetric) -> Color {
        let kind: MonitorKind = switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        case .disk: .storage
        }
        return MonitorPalette(
            preference: MonitorColorSchemePreference(
                rawValue: UserDefaults.standard.string(forKey: "settings.colorSchemePreference") ?? ""
            ) ?? .vibrant,
            colorScheme: colorScheme
        ).moduleTint(for: kind)
    }

    /// 档位条使用的模块色。
    private func bandTint(_ metric: ProcessAlertEpisode.Metric) -> Color {
        let kind: MonitorKind = switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        }
        return MonitorPalette(
            preference: MonitorColorSchemePreference(
                rawValue: UserDefaults.standard.string(forKey: "settings.colorSchemePreference") ?? ""
            ) ?? .vibrant,
            colorScheme: colorScheme
        ).moduleTint(for: kind)
    }

    @Environment(\.colorScheme) private var colorScheme

    /// 档位序号到色彩深浅的映射。
    static func bandOpacity(index: Int) -> Double {
        0.25 + Double(index) * 0.3
    }

    /// 档位标签来自共享指标定义。
    static func bandLabels(for metric: ProcessAlertEpisode.Metric) -> [String] {
        StandaloneHTMLReportExporter.bandLabels(for: metric)
    }

    /// 事件状态与结束原因描述。
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

    /// 普通行显示的可读身份：去掉身份类别前缀；无法识别时回退原值。
    static func displayIdentity(_ appKey: String) -> String {
        for prefix in ["bundle:", "systemExecutable:", "unresolved:"] where appKey.hasPrefix(prefix) {
            return String(appKey.dropFirst(prefix.count))
        }
        return appKey
    }

    /// 事件数值的单位与设置页一致：容量二进制、速率十进制、占比百分比。
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
                                .background(Color(hex: 0xFF9500).opacity(0.15))
                                .foregroundStyle(Color(hex: 0xFF9500))
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
