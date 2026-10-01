import SwiftUI

/// 设置侧栏「数据统计」:记录开关 + 可直读的统计摘要 + 使用打卡与存储入口。
/// 范围与完整报表入口在前，历史结论、最近应用观测与指标按层次呈现。
/// 完整趋势、事件与模块明细仍由现有独立报表窗口承载,这里不复制第二套详情。
struct StatisticsSettingsView: View {
    @ObservedObject var recorder: StatisticsRecorder
    @ObservedObject var settings: MonitorSettings
    /// 跳转存储管理页(入口收在本页底部,归属数据统计)。
    var openStorage: () -> Void = {}

    /// 摘要数据源:正式运行跟随记录器发布;验证夹具模式下只读夹具。
    @StateObject private var dataSource: StatisticsOverviewDataSource
    @State private var range: StatisticsOverviewRange = StatisticsSettingsView.initialRange
    /// 当前范围的时间序列:事件聚合与压力累计由它推导,换范围或新桶封口时重取。
    @State private var series: [StatisticsRow] = []
    /// 压力告警:本页是「查看」落点,在屏即视为已读(红点清除)。
    @ObservedObject private var alerts = PressureAlertCenter.shared
    /// 最近应用高占用观测；与历史系统压力结论分开呈现。
    @ObservedObject private var processAlerts = ProcessAlertCenter.shared
    /// 本页是否真的在屏(窗口可见且为活跃窗口)→ 新告警直接按已读处理。
    @State private var isPageOnScreen = false

    init(
        recorder: StatisticsRecorder,
        settings: MonitorSettings,
        openStorage: @escaping () -> Void = {}
    ) {
        self.recorder = recorder
        self.settings = settings
        self.openStorage = openStorage
        _dataSource = StateObject(wrappedValue: StatisticsOverviewDataSource.make(recorder: recorder))
    }

    /// 初始范围可由验证环境变量指定(HAGIMI_STATS_RANGE=week/month),
    /// 便于三个范围逐项目测;正式运行始终从「今日」开始。
    private static var initialRange: StatisticsOverviewRange {
        switch ProcessInfo.processInfo.environment["HAGIMI_STATS_RANGE"] {
        case "week": return .week
        case "month": return .month
        default: return .today
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MonitorPalette {
        MonitorPalette(preference: settings.colorSchemePreference, colorScheme: colorScheme)
    }

    private var aggregate: StatisticsRow? { dataSource.range(range) }

    private var events: [StatisticsOverviewModel.Event] {
        StatisticsOverviewModel.events(from: series, bucketSeconds: bucketSeconds, now: dataSource.referenceNow)
    }

    /// 序列桶宽:从序列推断(判据见 StatisticsOverviewModel.bucketSeconds)。
    private var bucketSeconds: TimeInterval {
        StatisticsOverviewModel.bucketSeconds(for: range, series: series)
    }

    private var conclusion: StatisticsOverviewModel.Conclusion {
        StatisticsOverviewModel.conclusion(row: aggregate, events: events)
    }

    var body: some View {
        SettingsPage {
            recordToggleGroup
            summaryGroup

            SettingsGroup {
                entryRow(
                    icon: "internaldrive",
                    title: String(localized: "settings.sidebar.storage"),
                    action: openStorage
                )
            }
        }
        .task {
            dataSource.start()
            loadSeries()
        }
        .onChange(of: range) { _, _ in loadSeries() }
        .onChange(of: aggregate?.t) { _, _ in loadSeries() }
        .background {
            SettingsPageOnScreenReader { isPageOnScreen = $0 }
        }
        // 页面在屏时标记所有告警为已读。
        .onChange(of: isPageOnScreen) { _, onScreen in
            if onScreen { alerts.markAllRead() }
        }
        .onChange(of: alerts.statisticsEntryUnread) { _, unread in
            if unread, isPageOnScreen { alerts.markAllRead() }
        }
    }

    private func loadSeries() {
        dataSource.series(range) { rows in
            series = rows
        }
    }

    private var recordToggleGroup: some View {
        SettingsGroup {
            SettingsRow(title: String(localized: "stats.settings.toggle")) {
                Toggle("", isOn: $settings.statisticsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if settings.statisticsEnabled {
                SettingsDivider()
                SettingsRow(title: String(localized: "stats.settings.notifications", defaultValue: "推送异常警报通知")) {
                    Toggle("", isOn: $settings.alertNotificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - 统计摘要

    private var summaryGroup: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 0) {
                rangePicker
                #if DEBUG
                if StatisticsApplicationFixture.fromEnvironment() != nil {
                    Label(String(localized: "stats.apps.fixture.label"), systemImage: "testtube.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }
                #endif
                systemStatusAndAlertsSection
                if settings.statisticsEnabled, !applicationGroups.isEmpty {
                    SettingsDivider()
                    applicationObservationsSection
                }
                if aggregate != nil {
                    SettingsDivider()
                    metricsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 按最大高负载持续时长降序排列，时长相同时按应用标识稳定排序。
    private var applicationGroups: [ProcessAppAlertGroup] {
        #if DEBUG
        if let fixture = StatisticsApplicationFixture.fromEnvironment() {
            return fixture
        }
        #endif
        return processAlerts.activeAppGroups.sorted {
            if $0.maxDurationMinutes != $1.maxDurationMinutes {
                return $0.maxDurationMinutes > $1.maxDurationMinutes
            }
            return $0.appKey < $1.appKey
        }
    }

    private var applicationObservationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "stats.apps.recent.title"))
                    .font(.callout.weight(.medium))
                Text(String(localized: "stats.apps.count \(applicationGroups.count)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range, anchor: .apps))
                } label: {
                    Text(String(localized: "stats.apps.open-list"))
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.bottom, 6)

            ForEach(Array(applicationGroups.prefix(2))) { group in
                StatisticsApplicationObservationRow(group: group, palette: palette) { appKey, metric in
                    StatisticsReportFlow.open(
                        recorder: recorder,
                        context: StatisticsReportContext(range: range, anchor: .apps, appKey: appKey, metric: metric)
                    )
                }
                if group.id != applicationGroups.prefix(2).last?.id {
                    Divider().padding(.leading, 40)
                }
            }

            Text(String(localized: "stats.apps.recent.explanation"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// 时间范围选择栏
    private var rangePicker: some View {
        HStack {
            Picker(String(localized: "overview.range.label"), selection: $range) {
                Text(String(localized: "stats.settings.range.today")).tag(StatisticsOverviewRange.today)
                Text(String(localized: "stats.settings.range.week")).tag(StatisticsOverviewRange.week)
                Text(String(localized: "stats.settings.range.month")).tag(StatisticsOverviewRange.month)
            }
            .labelsHidden()
            .compatibleTabPickerStyle()

            Spacer(minLength: 8)
            Button {
                // 携带当前选中的统计范围打开报表。
                StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range))
            } label: {
                Label(String(localized: "stats.settings.open-report"), systemImage: "arrow.up.forward")
            }
            .buttonStyle(.link)
            .font(.callout)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    // MARK: - 系统状态与异常告警统一编排

    private var hasPressureEvents: Bool {
        if case .events = conclusion, !pressureKinds.isEmpty {
            return true
        }
        return false
    }

    private var systemStatusAndAlertsSection: some View {
        systemStatusAndAlertsContent
            .padding(.horizontal, 8)
            .padding(.top, settings.statisticsEnabled ? 10 : 8)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var systemStatusAndAlertsContent: some View {
        if !settings.statisticsEnabled {
            statusLine(
                icon: "pause.circle",
                tint: Color.secondary,
                headline: String(localized: "stats.summary.off")
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

        } else if hasPressureEvents {
            unifiedAlertCard
        } else {
            switch conclusion {
            case .noObservation:
                statusLine(
                    icon: "tray",
                    tint: Color.secondary,
                    headline: String(localized: "stats.summary.noRecord")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .insufficient(let recorded):
                statusLine(
                    icon: "hourglass",
                    tint: Color.secondary,
                    headline: String(localized: "overview.conclusion.insufficient"),
                    qualifier: String(localized: "overview.conclusion.recorded \(StatisticsDisplayFormat.duration(recorded))")
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .quiet:
                quietStatusContent
            case .events:
                EmptyView()
            }
        }
    }

    private var quietStatusContent: some View {
        statusLine(
            icon: "checkmark.circle.fill",
            tint: palette.severityTint(for: .calm),
            headline: String(localized: "overview.conclusion.quiet"),
            qualifier: String(localized: "stats.summary.period-caption")
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unifiedAlertCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "stats.summary.period-caption"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let anchor: StatisticsReportAnchor = pressureKinds.first?.kind == .thermal ? .thermal : .memory
                    StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range, anchor: anchor))
                } label: {
                    Text(String(localized: "stats.process.view-details.btn"))
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            ForEach(pressureKinds, id: \.kind) { kind in
                pressureKindRow(kind, showsKindName: true, showsStateIcon: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pressureKinds: [StatisticsOverviewModel.PressureKind] {
        StatisticsOverviewModel.pressureKinds(row: aggregate, events: events)
    }

    private func statusLine(
        icon: String,
        tint: Color,
        headline: String,
        qualifier: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let qualifier {
                    Text(qualifier)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 单条压力:多条并列时行首带状态图标(单条时标题图标已表状态,不重复),
    /// 正文是「档位 · 累计(含较低档位)」,保持正文颜色。
    private func pressureKindRow(
        _ kind: StatisticsOverviewModel.PressureKind,
        showsKindName: Bool,
        showsStateIcon: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showsStateIcon {
                Image(systemName: stateSymbol(kind.state))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(stateTint(kind))
                    .frame(width: 16)
            }

            pressureFactsText(kind, showsKindName: showsKindName)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 单条压力的事实文本:维度名与剩余事实用正文色,档位名按等级着色
    /// (警告/轻微=琥珀,严重/临界=红),一眼能看出这条压力的分量。
    private func pressureFactsText(
        _ kind: StatisticsOverviewModel.PressureKind,
        showsKindName: Bool
    ) -> Text {
        var segments: [Text] = []
        if let worst = kind.worstLevel, let levelName = levelText(kind.kind, worst.level) {
            let tint = levelTint(kind.kind, worst.level)
            if showsKindName {
                segments.append(
                    Text(String(localized: "stats.summary.kindWithLevel \(eventKindText(kind.kind)) \(levelName)"))
                        .foregroundStyle(tint)
                )
            } else {
                segments.append(Text(levelName).foregroundStyle(tint))
            }
        } else if showsKindName {
            segments.append(Text(eventKindText(kind.kind)))
        }

        // 括号短语直接跟在「累计 X 分钟」后面,不再多一个分隔符。
        var accumulated = Text(String(localized: "stats.summary.accumulated \(StatisticsDisplayFormat.duration(kind.seconds))"))
        if let includes = lowerLevelsText(kind) {
            accumulated = accumulated + includes
        }
        segments.append(accumulated)

        // 观测中断会改变「现在到底怎样」的判断,这一条限定仍用文字写明。
        if kind.state == .interrupted {
            segments.append(Text(eventStateText(kind.state)))
        }
        return segments.dropFirst().reduce(segments[0]) { $0 + Text(" · ") + $1 }
    }

    /// 状态图标:进行中是告警三角,已恢复是勾,观测中断是问号。
    private func stateSymbol(_ state: StatisticsOverviewModel.Event.State) -> String {
        switch state {
        case .ongoing: "exclamationmark.triangle.fill"
        case .recovered: "checkmark.circle.fill"
        case .interrupted: "questionmark.circle"
        }
    }

    /// 状态配色:已恢复用平静色示意「现在不在了」,中断中性,进行中随档位。
    private func stateTint(_ kind: StatisticsOverviewModel.PressureKind) -> Color {
        switch kind.state {
        case .ongoing: pressureTint(kind)
        case .recovered: palette.severityTint(for: .calm)
        case .interrupted: Color.secondary
        }
    }

    /// 同类较低档位的组成,如「（含警告 10 分钟）」;档位名同样按等级着色。
    /// 只有一个档位时返回 nil,不做重复陈述。
    private func lowerLevelsText(_ kind: StatisticsOverviewModel.PressureKind) -> Text? {
        let items = kind.levels.dropFirst().compactMap { item -> Text? in
            guard let levelName = levelText(kind.kind, item.level) else { return nil }
            let duration = Text(StatisticsDisplayFormat.duration(item.seconds))
            return Text(levelName).foregroundStyle(levelTint(kind.kind, item.level)) + Text(" ") + duration
        }
        guard !items.isEmpty else { return nil }
        let joined = items.dropFirst().reduce(items[0]) { $0 + Text(" · ") + $1 }
        return Text(String(localized: "stats.summary.levelIncludesOpen")) + joined + Text(String(localized: "stats.summary.levelIncludesClose"))
    }

    /// 压力配色按达到的最高档位定;已恢复不等于没事发生——
    /// 压在范围内的存在感不因状态回退而变浅。
    private func pressureTint(_ kind: StatisticsOverviewModel.PressureKind) -> Color {
        levelTint(kind.kind, kind.worstLevel?.level ?? 0)
    }

    /// 档位配色:警告/轻微用琥珀,严重/临界用红色。
    private func levelTint(_ kind: StatisticsOverviewModel.Event.Kind, _ level: Int) -> Color {
        let isCritical: Bool
        switch (kind, level) {
        case (.memory, 2), (.thermal, 2), (.thermal, 3):
            isCritical = true
        default:
            isCritical = false
        }
        return palette.severityTint(for: isCritical ? .critical : .warning)
    }

    /// 原生档位文案:内存 1=警告 2=严重;热状态 1=轻微 2=严重 3=临界。
    private func levelText(_ kind: StatisticsOverviewModel.Event.Kind, _ level: Int) -> String? {
        switch (kind, level) {
        case (.memory, 2): String(localized: "memory-pressure.critical")
        case (.memory, 1): String(localized: "memory-pressure.warning")
        case (.thermal, 3): String(localized: "thermal-pressure.critical")
        case (.thermal, 2): String(localized: "thermal-pressure.serious")
        case (.thermal, 1): String(localized: "thermal-pressure.fair")
        default: nil
        }
    }

    // MARK: 指标行

    private struct SummaryMetric: Identifiable {
        let id: String
        let label: String
        /// 行首图标:沿用 MonitorKind.symbol 语义映射与 MonitorPalette 模块色,
        /// 与设置侧栏/面板同一套语义,作纯文字行间的扫读锚点。
        let icon: String
        let tint: Color
        /// 数值文本(主值加粗等宽、限定词次要小字的组合文本);nil = 暂无数据。
        let value: Text?
    }

    private var metricsSection: some View {
        VStack(spacing: 0) {
            metricGroup(caption: String(localized: "stats.group.usage"), metrics: usageMetrics)
            SettingsDivider()
                .padding(.leading, 34)
            metricGroup(caption: String(localized: "stats.group.transfer"), metrics: transferMetrics)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// 一组指标:组标题(次要小字)+ 逐行。分组把「机器用了多少」与「进出多少数据」
    /// 在视觉上分开,不必逐字读完所有行。
    private func metricGroup(caption: String, metrics: [SummaryMetric]) -> some View {
        VStack(spacing: 0) {
            Text(caption)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(metrics) { metric in
                metricRow(metric)
            }
        }
    }

    /// 「用量」组:CPU / GPU 平均使用率(附高负载累计)、内存占用、功耗。
    /// 内存压力不再单列——状态块已按档位与累计时长承载同一信息,重复列一遍只会
    /// 互相打架;峰值、压缩、Swap 与评分明细仍留给报表。
    private var usageMetrics: [SummaryMetric] {
        let row = aggregate
        return [
            SummaryMetric(
                id: "cpu",
                label: String(localized: "stats.metrics.cpu"),
                icon: MonitorKind.cpu.symbol,
                tint: palette.moduleTint(for: .cpu),
                value: usageValue(average: row?.cpuAvg, highSeconds: row?.cpuHighS)
            ),
            SummaryMetric(
                id: "gpu",
                label: String(localized: "stats.metrics.gpu"),
                icon: MonitorKind.gpu.symbol,
                tint: palette.moduleTint(for: .gpu),
                value: usageValue(average: row?.gpuAvg, highSeconds: row?.gpuHighS)
            ),
            SummaryMetric(
                id: "memoryUsage",
                label: String(localized: "stats.metrics.memoryUsage"),
                icon: MonitorKind.memory.symbol,
                tint: palette.moduleTint(for: .memory),
                value: row?.memPctAvg.map { averageText(StatisticsDisplayFormat.percent($0)) }
            ),
            SummaryMetric(
                id: "power",
                label: String(localized: "stats.metrics.power"),
                icon: MonitorKind.battery.symbol,
                tint: palette.moduleTint(for: .battery),
                value: row?.powerAvg.map { averageText(String(format: "%.1f W", $0)) }
            ),
        ]
    }

    /// 「传输」组:网络收发与磁盘读写的范围累计量。
    private var transferMetrics: [SummaryMetric] {
        let row = aggregate
        return [
            SummaryMetric(
                id: "network",
                label: String(localized: "overview.resources.network"),
                icon: MonitorKind.network.symbol,
                tint: palette.moduleTint(for: .network),
                value: networkValue(row)
            ),
            SummaryMetric(
                id: "disk",
                label: String(localized: "stats.metrics.disk"),
                icon: MonitorKind.storage.symbol,
                tint: palette.moduleTint(for: .storage),
                value: diskValue(row)
            ),
        ]
    }

    /// 主值:加粗等宽数字,行内的扫读落点。
    private func mainValueText(_ value: String) -> Text {
        Text(value).font(.body.weight(.semibold)).monospacedDigit()
    }

    /// 限定词(平均/高负载/读/写/方向符):次要色小字,需要细读时才进入视野。
    private func qualifierText(_ text: String) -> Text {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    /// 「平均 X」:限定词前缀 + 主值。
    private func averageText(_ value: String) -> Text {
        qualifierText(String(localized: "stats.metrics.word.average") + " ") + mainValueText(value)
    }

    /// CPU/GPU 行:平均使用率为主值,有过高负载时以限定词补累计时长(没有就不写,不堆零值)。
    private func usageValue(average: Double?, highSeconds: Double?) -> Text? {
        var parts: [Text] = []
        if let average {
            parts.append(averageText(StatisticsDisplayFormat.percent(average)))
        }
        if let highSeconds, highSeconds > 0 {
            parts.append(qualifierText(String(localized: "stats.metrics.word.highLoad") + " " + StatisticsDisplayFormat.duration(highSeconds)))
        }
        guard !parts.isEmpty else { return nil }
        return parts.dropFirst().reduce(parts[0]) { $0 + qualifierText(" · ") + $1 }
    }

    /// 传输总量用十进制单位（GB/TB），与报表、导出保持同一除数。
    private func networkValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.netDown != nil || row.netUp != nil else { return nil }
        let down = StatisticsDisplayFormat.decimalVolume(row.netDown ?? 0)
        let up = StatisticsDisplayFormat.decimalVolume(row.netUp ?? 0)
        return qualifierText("↓ ") + mainValueText(down) + qualifierText("  ↑ ") + mainValueText(up)
    }

    private func diskValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.diskRead != nil || row.diskWrite != nil else { return nil }
        let read = StatisticsDisplayFormat.decimalVolume(row.diskRead ?? 0)
        let write = StatisticsDisplayFormat.decimalVolume(row.diskWrite ?? 0)
        return qualifierText(String(localized: "stats.metrics.word.read") + " ") + mainValueText(read)
            + qualifierText("  " + String(localized: "stats.metrics.word.write") + " ") + mainValueText(write)
    }

    private func metricRow(_ metric: SummaryMetric) -> some View {
        HStack(spacing: 10) {
            Image(systemName: metric.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(metric.tint)
                .frame(width: 24, height: 24)
                .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(metric.label)
                .font(.body)

            Spacer(minLength: 16)

            if let value = metric.value {
                value
            } else {
                Text(String(localized: "overview.resources.noData"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func eventKindText(_ kind: StatisticsOverviewModel.Event.Kind) -> String {
        switch kind {
        case .memory: String(localized: "overview.event.kind.memory")
        case .thermal: String(localized: "overview.event.kind.thermal")
        }
    }

    private func eventStateText(_ state: StatisticsOverviewModel.Event.State) -> String {
        switch state {
        case .ongoing: String(localized: "overview.event.state.ongoing")
        case .recovered: String(localized: "overview.event.state.recovered")
        case .interrupted: String(localized: "overview.event.state.interrupted")
        }
    }

    /// 功能入口行:图标 + 标题 + 右箭头,视觉统一。
    @ViewBuilder
    private func entryRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 统计页在屏状态跟踪：窗口可见、未最小化且为 Key 窗口时判定为在屏。
/// 避免因设置窗口 orderOut 未触发 onDisappear 导致在屏状态不准确。
private struct SettingsPageOnScreenReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> OnScreenObservingView {
        OnScreenObservingView { visible in
            DispatchQueue.main.async { onChange(visible) }
        }
    }

    func updateNSView(_ nsView: OnScreenObservingView, context: Context) {
        nsView.onChange = { visible in
            DispatchQueue.main.async { onChange(visible) }
        }
    }
}

/// 自动管理多个 NotificationCenter 观察者生命周期的包装器。
/// 安全不变式：在 deinit 时自动注销所有观察者，避免在 MainActor 隔离类的 deinit 中访问非 Sendable 数组。
nonisolated private final class NotificationObserversBox: @unchecked Sendable {
    private var observers: [any NSObjectProtocol] = []

    func add(_ observer: any NSObjectProtocol) {
        observers.append(observer)
    }

    func removeAll() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }
}

private final class OnScreenObservingView: NSView {
    var onChange: ((Bool) -> Void)?
    private let observersBox = NotificationObserversBox()

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observersBox.removeAll()

        // 未挂到窗口时不订阅通知:report() 会把「不在屏」直接回传。
        guard window != nil else {
            report()
            return
        }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ]
        for name in names {
            observersBox.add(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.report()
                    }
                }
            )
        }
        report()
    }

    private func report() {
        guard let window else {
            onChange?(false)
            return
        }
        onChange?(window.isVisible && !window.isMiniaturized && window.isKeyWindow)
    }
}
