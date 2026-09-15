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
    /// 进程长期高负载告警与时间分布
    @ObservedObject private var processAlerts = ProcessAlertCenter.shared
    /// 本页是否真的在屏(窗口可见且为活跃窗口)→ 新告警直接按已读处理。
    @State private var isPageOnScreen = false
    /// 是否展开所有高负载应用（默认只展示 1 个，保护下方核心用量在首屏可见）
    @State private var isAlertsExpanded = false

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
                if settings.statisticsEnabled {
                    rangePicker
                }
                systemStatusAndAlertsSection
                if showsSummaryBody {
                    SettingsDivider()
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
        if case .noObservation = conclusion, processAlerts.activeAlerts.isEmpty { return false }
        return true
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

            Spacer()
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

    private var unifiedAlertFill: Color {
        Color.primary.opacity(0.035)
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
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if hasPressureEvents || !processAlerts.activeAppGroups.isEmpty {
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
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .quiet:
                quietStatusContent
            case .events:
                EmptyView()
            }
        }
    }

    private var quietStatusContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.severityTint(for: .calm))
                .frame(width: 16)

            Text(String(localized: "overview.conclusion.quiet"))
                .font(.body.weight(.semibold))

            Spacer()

            Button {
                processAlerts.simulateWindowServerDemo()
            } label: {
                Text(String(localized: "stats.process.simulate.btn", defaultValue: "演练示例"))
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var unifiedAlertCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. 系统级压力（内存 / 热压力）
            if hasPressureEvents, let leading = pressureKinds.first {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: stateSymbol(leading.state))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(stateTint(leading))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 3) {
                        let headline: String = {
                            if pressureKinds.count == 1 {
                                return leading.state == .recovered
                                    ? String(localized: "stats.summary.pressureDuringPast \(eventKindText(leading.kind))")
                                    : String(localized: "stats.summary.pressureDuring \(eventKindText(leading.kind))")
                            } else {
                                return String(localized: "stats.summary.multipleKinds \(pressureKinds.count)")
                            }
                        }()

                        Text(headline)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(leading.state == .ongoing ? pressureTint(leading) : Color.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(pressureKinds.enumerated()), id: \.offset) { _, kind in
                                pressureKindRow(
                                    kind,
                                    showsKindName: pressureKinds.count > 1,
                                    showsStateIcon: pressureKinds.count > 1
                                )
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    viewDetailsButton
                }
            } else if !processAlerts.activeAppGroups.isEmpty {
                // 没有系统级压力，但有应用级高负载告警时，首行提供概括标题与右侧「查看明细」按钮
                let hasOngoing = processAlerts.activeAppGroups.contains { $0.worstState == .ongoing }
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: hasOngoing ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hasOngoing ? palette.severityTint(for: .critical) : Color.secondary)
                        .frame(width: 14)

                    Text(hasOngoing
                         ? String(localized: "stats.alerts.apps.ongoing")
                         : String(localized: "stats.alerts.apps.recovered"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Spacer(minLength: 8)

                    viewDetailsButton
                }
            }

            // 若同时存在系统压力与软件告警，显示浅分隔线
            if hasPressureEvents && !processAlerts.activeAppGroups.isEmpty {
                Divider()
                    .opacity(0.4)
                    .padding(.vertical, 1)
            }

            // 2. 软件级长期高负载告警（同应用合并，首屏限 1 个应用）
            if !processAlerts.activeAppGroups.isEmpty {
                let groups = processAlerts.activeAppGroups
                let displayedGroups = isAlertsExpanded ? groups : Array(groups.prefix(1))

                VStack(spacing: 6) {
                    ForEach(displayedGroups) { group in
                        processAppGroupCard(group)
                    }

                    if groups.count > 1 {
                        AlertExpandLineButton(
                            isExpanded: isAlertsExpanded,
                            groupsCount: groups.count
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAlertsExpanded.toggle()
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(unifiedAlertFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var viewDetailsButton: some View {
        Button {
            StatisticsReportFlow.open(recorder: recorder, anchor: .apps)
        } label: {
            Text(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// 高负载应用展开/收起按钮：内部管理 hover 状态，避免顶层重新求值导致上方卡片闪烁。
    private struct AlertExpandLineButton: View {
        let isExpanded: Bool
        let groupsCount: Int
        let onToggle: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.primary.opacity(isHovered ? 0.18 : 0.10))
                        .frame(height: 0.5)

                    HStack(spacing: 5) {
                        Text(isExpanded
                             ? String(localized: "stats.alerts.collapse", defaultValue: "收起高负载应用")
                             : String(format: String(localized: "stats.alerts.expandOthers", defaultValue: "展开其余 %d 个高负载应用"), groupsCount - 1))
                            .lineLimit(1)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(isHovered ? 0.07 : 0.035))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.07), lineWidth: 0.5)
                    )

                    Rectangle()
                        .fill(Color.primary.opacity(isHovered ? 0.18 : 0.10))
                        .frame(height: 0.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
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

    // MARK: - 长期高负载软件卡片

    private func processAppGroupCard(_ group: ProcessAppAlertGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // App 头部
            HStack(alignment: .center, spacing: 8) {
                processIconView(iconPNG: group.iconPNG, name: group.name)
                    .frame(width: 24, height: 24)

                Text(group.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(group.worstState == .ongoing ? palette.severityTint(for: .critical) : palette.severityTint(for: .calm))
                        .frame(width: 5, height: 5)
                    Text(group.worstState == .ongoing
                         ? String(localized: "stats.alerts.state.ongoing", defaultValue: "持续高负荷")
                         : String(localized: "stats.alerts.state.recovered", defaultValue: "已恢复"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(group.worstState == .ongoing ? palette.severityTint(for: .critical) : palette.severityTint(for: .calm))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill((group.worstState == .ongoing ? palette.severityTint(for: .critical) : palette.severityTint(for: .calm)).opacity(0.12))
                )
            }

            // 该 App 下合并的各超标指标列表
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.episodes) { ep in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(metricTag(ep.metric))
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(metricColor(ep.metric).opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                .foregroundStyle(metricColor(ep.metric))

                            Text(metricDetailText(ep))
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(timeRangeText(ep))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }

                        // 紧凑档位分布条
                        GeometryReader { geo in
                            let total = max(1, ep.tier1Minutes + ep.tier2Minutes + ep.tier3Minutes)
                            let w1 = max(geo.size.width * CGFloat(ep.tier1Minutes) / CGFloat(total), ep.tier1Minutes > 0 ? 6 : 0)
                            let w2 = max(geo.size.width * CGFloat(ep.tier2Minutes) / CGFloat(total), ep.tier2Minutes > 0 ? 6 : 0)
                            let w3 = max(geo.size.width * CGFloat(ep.tier3Minutes) / CGFloat(total), ep.tier3Minutes > 0 ? 6 : 0)

                            HStack(spacing: 2) {
                                if ep.tier1Minutes > 0 {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color(hex: 0xD4A034))
                                        .frame(width: w1)
                                }
                                if ep.tier2Minutes > 0 {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(palette.severityTint(for: .warning))
                                        .frame(width: w2)
                                }
                                if ep.tier3Minutes > 0 {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(palette.severityTint(for: .critical))
                                        .frame(width: w3)
                                }
                            }
                        }
                        .frame(height: 4)

                        // 紧凑档位标签
                        HStack(spacing: 8) {
                            tierLabel(name: tierName(metric: ep.metric, tier: 1), minutes: ep.tier1Minutes, color: Color(hex: 0xD4A034))
                            tierLabel(name: tierName(metric: ep.metric, tier: 2), minutes: ep.tier2Minutes, color: palette.severityTint(for: .warning))
                            tierLabel(name: tierName(metric: ep.metric, tier: 3), minutes: ep.tier3Minutes, color: palette.severityTint(for: .critical))
                        }
                        .font(.system(size: 9.5))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static let alertTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    private func timeRangeText(_ ep: ProcessAlertEpisode) -> String {
        let startStr = Self.alertTimeFormatter.string(from: ep.startedAt)
        if ep.state == .ongoing {
            return String(format: String(localized: "stats.alerts.timeRange.ongoing", defaultValue: "%@ 至今 · 已持续 %d 分钟"), startStr, ep.durationMinutes)
        } else {
            let endStr = Self.alertTimeFormatter.string(from: ep.endedAt ?? ep.lastSeenAt)
            return String(format: String(localized: "stats.alerts.timeRange.recovered", defaultValue: "%@ - %@ · 持续 %d 分钟"), startStr, endStr, ep.durationMinutes)
        }
    }

    private func tierName(metric: ProcessAlertEpisode.Metric, tier: Int) -> String {
        switch (metric, tier) {
        case (.gpu, 1): return "20-40%"
        case (.gpu, 2): return "40-70%"
        case (.gpu, 3): return "70%+"
        case (.memory, 1): return "2-4 GB"
        case (.memory, 2): return "4-8 GB"
        case (.memory, 3): return "8 GB+"
        case (.network, 1): return "10-30 MB/s"
        case (.network, 2): return "30-80 MB/s"
        case (.network, 3): return "80 MB/s+"
        default:
            return tier == 1 ? "30-50%" : (tier == 2 ? "50-80%" : "80%+")
        }
    }

    private func tierLabel(name: String, minutes: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 3.5, height: 3.5)
            Text("\(name): \(minutes)m")
                .foregroundStyle(minutes > 0 ? Color.primary : Color.secondary.opacity(0.55))
        }
    }

    private func metricTag(_ metric: ProcessAlertEpisode.Metric) -> String {
        switch metric {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return String(localized: "stats.metric.memory", defaultValue: "内存")
        case .network: return String(localized: "stats.metric.network", defaultValue: "网络")
        }
    }

    private func metricColor(_ metric: ProcessAlertEpisode.Metric) -> Color {
        switch metric {
        case .cpu: return palette.moduleTint(for: .cpu)
        case .gpu: return palette.moduleTint(for: .gpu)
        case .memory: return palette.moduleTint(for: .memory)
        case .network: return palette.moduleTint(for: .network)
        }
    }

    private func formatMemoryMB(_ mb: Double) -> String {
        if mb >= 1024 {
            let gb = (mb / 1024.0 * 10).rounded() / 10
            if gb == gb.rounded() {
                return String(format: "%.0f GB", gb)
            }
            return String(format: "%.1f GB", gb)
        }
        return "\(Int(mb.rounded())) MB"
    }

    private func metricDetailText(_ ep: ProcessAlertEpisode) -> String {
        let peakLabel = String(localized: "stats.alerts.peakLabel", defaultValue: "峰值")
        switch ep.metric {
        case .gpu, .cpu:
            let avg = String(format: "%.1f%%", ep.averageUsage)
            let peak = String(format: "%.1f%%", ep.peakUsage)
            return "\(avg) (\(peakLabel) \(peak))"
        case .memory:
            return "\(formatMemoryMB(ep.averageUsage)) (\(peakLabel) \(formatMemoryMB(ep.peakUsage)))"
        case .network:
            return "\(String(format: "%.1f MB/s", ep.averageUsage))"
        }
    }

    @ViewBuilder
    private func processIconView(iconPNG: Data?, name: String) -> some View {
        if let data = iconPNG, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else if name == "WindowServer" {
            Image(systemName: "display")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

    private func networkValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.netDown != nil || row.netUp != nil else { return nil }
        let down = StatisticsDisplayFormat.bytes(row.netDown ?? 0)
        let up = StatisticsDisplayFormat.bytes(row.netUp ?? 0)
        return qualifierText("↓ ") + mainValueText(down) + qualifierText("  ↑ ") + mainValueText(up)
    }

    private func diskValue(_ row: StatisticsRow?) -> Text? {
        guard let row, row.diskRead != nil || row.diskWrite != nil else { return nil }
        let read = StatisticsDisplayFormat.bytes(row.diskRead ?? 0)
        let write = StatisticsDisplayFormat.bytes(row.diskWrite ?? 0)
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
