import SwiftUI

/// 设置侧栏「数据统计」:记录开关 + 可直读的统计摘要 + 使用打卡与存储入口。
/// 摘要在本页内即可读完——范围 → 一句结论 → 几行指标 → 「查看完整统计」;
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
            checkinSection
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
        // 查看即清:页面成为在屏内容时清全部入口的红点;页面持续在屏期间
        // 新到的告警也直接按已读处理——用户正看着这块内容,不必再点一次。
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
        }
    }

    // MARK: - 统计摘要

    private var summaryGroup: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 0) {
                if settings.statisticsEnabled {
                    rangePicker
                }
                statusSection
                if showsSummaryBody {
                    metricsSection
                    SettingsDivider()
                    reportEntryRow
                }
            }
            // 只有状态行时(尚无记录/记录已关闭)内容不撑满,卡片会缩成一小块;
            // 固定占满分组宽度,与其余分组对齐。
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 有可用记录才展开指标与入口;「尚无记录」「记录已关闭」只留状态行。
    private var showsSummaryBody: Bool {
        guard settings.statisticsEnabled else { return false }
        if case .noObservation = conclusion { return false }
        return true
    }

    private var rangePicker: some View {
        Picker(String(localized: "overview.range.label"), selection: $range) {
            Text(String(localized: "stats.settings.range.today")).tag(StatisticsOverviewRange.today)
            Text(String(localized: "stats.settings.range.week")).tag(StatisticsOverviewRange.week)
            Text(String(localized: "stats.settings.range.month")).tag(StatisticsOverviewRange.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    // MARK: 状态区(一行结论,必要时附档位与限定)

    /// 状态块单独铺一层浅底,与下方指标行拉开界限:结论是「发生了什么」,
    /// 指标行是「这段时间的整体用量」,两者不是同一种信息。
    /// 真实异常(持续中的压力)用告警色浅底,其余状态用中性底,不滥用颜色。
    private var statusSection: some View {
        statusContent
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.top, settings.statisticsEnabled ? 10 : 8)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var statusContent: some View {
        if !settings.statisticsEnabled {
            statusLine(
                icon: "pause.circle",
                tint: Color.secondary,
                headline: String(localized: "stats.summary.off")
            )
        } else {
            switch conclusion {
            case .noObservation:
                statusLine(
                    icon: "tray",
                    tint: Color.secondary,
                    headline: String(localized: "stats.summary.noRecord")
                )
            case .insufficient(let recorded):
                statusLine(
                    icon: "hourglass",
                    tint: Color.secondary,
                    headline: String(localized: "overview.conclusion.insufficient"),
                    qualifier: String(localized: "overview.conclusion.recorded \(StatisticsDisplayFormat.duration(recorded))")
                )
            case .quiet:
                statusLine(
                    icon: "checkmark.circle.fill",
                    tint: palette.severityTint(for: .calm),
                    headline: String(localized: "overview.conclusion.quiet")
                )
            case .events:
                if let leading = pressureKinds.first {
                    eventStatusLine(leading, kinds: pressureKinds)
                }
            }
        }
    }

    private var pressureKinds: [StatisticsOverviewModel.PressureKind] {
        StatisticsOverviewModel.pressureKinds(row: aggregate, events: events)
    }

    /// 状态块底色:平稳用中性偏绿;压力进行中用档位浅底;已过去的压力用中性底
    /// (绿勾已经在说「现在不在了」,不必再铺一层告警色)。浅底只负责把结论块
    /// 与下方指标行分开,不喧宾夺主。
    private var statusFill: Color {
        guard settings.statisticsEnabled else { return Color.primary.opacity(0.045) }
        switch conclusion {
        case .quiet:
            return palette.severityTint(for: .calm).opacity(0.10)
        case .events:
            guard let leading = pressureKinds.first, leading.state == .ongoing else {
                return Color.primary.opacity(0.045)
            }
            return pressureTint(leading).opacity(0.08)
        default:
            return Color.primary.opacity(0.045)
        }
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

    /// 异常状态:标题一句总括,具体压力逐条分行列出。
    /// 状态用行首图标表达——进行中是告警三角、已恢复是勾、观测中断是问号,
    /// 标题在已恢复时用「出现过」的措辞,让「这件事已经过去」一眼可见;
    /// 同类较低档位的时长并进«累计»后的括号,不做灰色小字另起一行。
    private func eventStatusLine(
        _ leading: StatisticsOverviewModel.PressureKind,
        kinds: [StatisticsOverviewModel.PressureKind]
    ) -> some View {
        let tint = pressureTint(leading)
        let headline: String
        if kinds.count == 1 {
            headline = leading.state == .recovered
                ? String(localized: "stats.summary.pressureDuringPast \(eventKindText(leading.kind))")
                : String(localized: "stats.summary.pressureDuring \(eventKindText(leading.kind))")
        } else {
            headline = String(localized: "stats.summary.multipleKinds \(kinds.count)")
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: stateSymbol(leading.state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stateTint(leading))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(headline)
                        .font(.body.weight(.semibold))
                        // 进行中才用告警色;已过去的事实保持正文颜色,不淡化也不喊。
                        .foregroundStyle(leading.state == .ongoing ? tint : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    Button {
                        // 是谁的压力就落到谁的板块:内存压力→内存构成,热压力→热压力与温度。
                        StatisticsReportFlow.open(
                            recorder: recorder,
                            anchor: leading.kind == .memory ? .memory : .thermal
                        )
                    } label: {
                        Text(String(localized: "overview.events.view"))
                    }
                    .buttonStyle(.link)
                    .font(.body)
                }

                // 逐条列出:多类时每条带维度名与状态图标,单类时维度名已在标题里,不重复。
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                        pressureKindRow(
                            kind,
                            showsKindName: kinds.count > 1,
                            showsStateIcon: kinds.count > 1
                        )
                    }
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
        /// 数值文本(组合文本:压力档位按等级着色);nil = 暂无数据。
        let value: Text?
    }

    private var metricsSection: some View {
        VStack(spacing: 0) {
            ForEach(summaryMetrics) { metric in
                metricRow(metric)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// 行内容:CPU / GPU 平均使用率(附高负载累计)、功耗、内存占用、内存压力、
    /// 网络收发、磁盘读写。峰值、压缩、Swap 与评分明细留给报表。
    private var summaryMetrics: [SummaryMetric] {
        let row = aggregate
        return [
            SummaryMetric(
                id: "cpu",
                label: String(localized: "stats.metrics.cpu"),
                value: usageValue(average: row?.cpuAvg, highSeconds: row?.cpuHighS)
            ),
            SummaryMetric(
                id: "gpu",
                label: String(localized: "stats.metrics.gpu"),
                value: usageValue(average: row?.gpuAvg, highSeconds: row?.gpuHighS)
            ),
            SummaryMetric(
                id: "power",
                label: String(localized: "stats.metrics.power"),
                value: row?.powerAvg.map { Text(String(localized: "stats.metrics.average \(String(format: "%.1f W", $0))")) }
            ),
            SummaryMetric(
                id: "memoryUsage",
                label: String(localized: "stats.metrics.memoryUsage"),
                value: row?.memPctAvg.map { Text(String(localized: "stats.metrics.average \(StatisticsDisplayFormat.percent($0))")) }
            ),
            SummaryMetric(
                id: "memory",
                label: String(localized: "overview.event.kind.memory"),
                value: memoryPressureValue(row)
            ),
            SummaryMetric(
                id: "network",
                label: String(localized: "overview.resources.network"),
                value: networkValue(row)
            ),
            SummaryMetric(
                id: "disk",
                label: String(localized: "stats.metrics.disk"),
                value: diskValue(row)
            ),
        ]
    }

    /// CPU/GPU 行:平均使用率,有过高负载时补上累计时长(没有就不写,不堆零值)。
    private func usageValue(average: Double?, highSeconds: Double?) -> Text? {
        var parts: [Text] = []
        if let average {
            parts.append(Text(String(localized: "stats.metrics.average \(StatisticsDisplayFormat.percent(average))")))
        }
        if let highSeconds, highSeconds > 0 {
            parts.append(Text(String(localized: "stats.metrics.highLoad \(StatisticsDisplayFormat.duration(highSeconds))")))
        }
        guard !parts.isEmpty else { return nil }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
    }

    /// 内存压力行:有压力写「最高档位 · 累计时长」,档位按等级着色(与告警块同一口径);
    /// 观测不足时不说「正常」;无有效观测显示暂无数据。
    private func memoryPressureValue(_ row: StatisticsRow?) -> Text? {
        guard let row else { return nil }
        switch StatisticsOverviewModel.memoryPressureStatus(row) {
        case .noObservation:
            return nil
        case .pressure(let seconds):
            var parts: [Text] = []
            if let worst = StatisticsOverviewModel.pressureLevels(of: .memory, row: row).first,
               let level = levelText(.memory, worst.level) {
                parts.append(Text(level).foregroundStyle(levelTint(.memory, worst.level)))
            }
            parts.append(Text(String(localized: "stats.summary.accumulated \(StatisticsDisplayFormat.duration(seconds))")))
            return parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
        case .insufficient:
            return Text(String(localized: "stats.metrics.insufficient"))
        case .normal:
            return Text(String(localized: "memory-pressure.normal"))
        }
    }

    private func networkValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.netDown != nil || row.netUp != nil else { return nil }
        let down = StatisticsDisplayFormat.bytes(row.netDown ?? 0)
        let up = StatisticsDisplayFormat.bytes(row.netUp ?? 0)
        return Text(String(localized: "stats.metrics.networkValues \(down) \(up)"))
    }

    private func diskValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.diskRead != nil || row.diskWrite != nil else { return nil }
        let read = StatisticsDisplayFormat.bytes(row.diskRead ?? 0)
        let write = StatisticsDisplayFormat.bytes(row.diskWrite ?? 0)
        return Text(String(localized: "stats.metrics.diskValues \(read) \(write)"))
    }

    private func metricRow(_ metric: SummaryMetric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(metric.label)
                .font(.body)

            Spacer(minLength: 16)

            if let value = metric.value {
                value
                    .font(.body)
                    .monospacedDigit()
            } else {
                Text(String(localized: "overview.resources.noData"))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
    }

    private var reportEntryRow: some View {
        Button {
            StatisticsReportFlow.open(recorder: recorder)
        } label: {
            HStack(spacing: 8) {
                Text(String(localized: "stats.settings.open-report"))
                    .font(.body)

                Spacer(minLength: 16)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    // MARK: - 使用打卡(默认折叠)

    @State private var showCheckin = false
    @State private var dayCoverage: [Int64: Double] = [:]

    private var checkinSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showCheckin.toggle() }
                if showCheckin { loadDayCoverage() }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        )

                    Text(headerPrimary)
                        .font(.headline.weight(.semibold))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showCheckin ? -180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(StaticPressButtonStyle())

            if showCheckin {
                checkinPanel
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerPrimary: String {
        if recorder.usageTotalDays > 0 {
            return String(localized: "stats.settings.checkin-total \(recorder.usageTotalDays)")
        }
        if recorder.recordDays > 0 {
            return String(localized: "stats.settings.record-days \(recorder.recordDays)")
        }
        return String(localized: "stats.settings.subtitle-empty")
    }

    /// 展开区:周列 × 星期行的使用打卡日历 + 起始日摘要。
    @ViewBuilder
    private var checkinPanel: some View {
        let calendar = Calendar.current
        let active = Set(recorder.usageActiveDays)
        let todayKey = StatisticsProcessStore.dayKey(Date(), calendar: calendar)
        // 周一起列,与报表打卡网格一致,不随 locale firstWeekday 变化。
        // Calendar.weekday 为 1-based(周日=1):周一回退 0 天,周日回退 6 天。
        let weekday = calendar.component(.weekday, from: Date())
        let monday = calendar.date(
            byAdding: .day, value: -((weekday + 5) % 7),
            to: calendar.startOfDay(for: Date()))!

        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // 懒加载周列:26 周 × 7 格一次性建齐会让展开/收起瞬间的视图
                    // 重建与头部同帧竞争,只建可见列,切换更顺滑。
                    LazyHStack(alignment: .top, spacing: 3) {
                        ForEach(0..<26, id: \.self) { weekIndex in
                            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex - 25, to: monday)!
                            VStack(spacing: 3) {
                                Text(monthLabel(for: weekStart, calendar: calendar))
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 10)
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    let date = calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!
                                    let key = StatisticsProcessStore.dayKey(date, calendar: calendar)
                                    checkinCell(active: active.contains(key),
                                                hours: dayCoverage[key] ?? 0,
                                                isToday: key == todayKey)
                                }
                            }
                            .id(weekIndex)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    // 展开时滚到最后一列(今天所在周),不让用户从 26 周前开始翻。
                    // 延后到主线程帧末无动画定位:立即动画滚动会与展开切换竞争,产生跳动。
                    DispatchQueue.main.async {
                        proxy.scrollTo(25, anchor: .trailing)
                    }
                }
            }

            if recorder.usageFirstDay > 0 {
                Text(String(localized: "stats.settings.checkin-footer \(firstDayText) \(recorder.usageTotalDays)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 周列顶部月份标签:仅当该周跨入新月份时显示。
    private func monthLabel(for weekStart: Date, calendar: Calendar) -> String {
        let thisMonth = calendar.component(.month, from: weekStart)
        let prevMonth = calendar.component(.month, from: calendar.date(byAdding: .day, value: -7, to: weekStart)!)
        guard thisMonth != prevMonth else { return "" }
        return weekStart.formatted(.dateTime.month(.abbreviated))
    }

    /// 打卡格:未使用灰色;使用过按当日采样覆盖时长分四档深浅。
    private func checkinCell(active: Bool, hours: Double, isToday: Bool) -> some View {
        let opacity: Double = !active ? 0 : hours < 2 ? 0.35 : hours < 6 ? 0.6 : hours < 12 ? 0.85 : 1
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(active ? Color.accentColor.opacity(opacity) : Color.secondary.opacity(0.14))
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isToday ? 1 : 0)
            )
    }

    /// 展开时拉取日桶覆盖时长,供打卡格分档着色。
    /// 优先真实采样覆盖秒数(cover_s);迁移前的旧行回退帧数口径。
    private func loadDayCoverage() {
        recorder.storageBuckets(.day) { buckets in
            var map: [Int64: Double] = [:]
            let calendar = Calendar.current
            for bucket in buckets {
                let seconds = bucket.row.coverS ?? Double(bucket.row.n)
                map[StatisticsProcessStore.dayKey(bucket.start, calendar: calendar)] = seconds / 3600
            }
            dayCoverage = map
        }
    }

    private var firstDayText: String {
        let key = recorder.usageFirstDay
        let components = DateComponents(year: Int(key / 10_000), month: Int(key % 10_000 / 100), day: Int(key % 100))
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.year().month().day())
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

/// 打卡卡展开按钮的专属样式:按下时标签外观完全静止。
/// 按钮标签内含高饱和渐变图标,系统按压反馈施加在其上会被放大成一次可见
/// 闪烁;展开/收起反馈由 chevron 旋转与高度动画承担,按钮本身不做视觉变化。
private struct StaticPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 统计页「在屏」跟踪:窗口可见、未最小化且是活跃窗口时才算用户真的在看。
/// 之所以需要它:关闭设置窗口只是 orderOut,SwiftUI 收不到 onDisappear,
/// 单靠 onAppear 分不出「正在看」与「窗口被关掉/切走」,红点会在不该亮时
/// 亮、该清时清不掉。状态以异步方式回传,避免在视图挂载/更新过程中改状态。
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

private final class OnScreenObservingView: NSView {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []

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
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.report()
            }
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
