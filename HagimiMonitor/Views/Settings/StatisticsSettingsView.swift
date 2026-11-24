import AppKit
import Combine
import SwiftUI
import UserNotifications

/// 设置侧栏「数据统计」：记录与警报控制 + 独立高占用实时提示条 + 历史范围概览卡 + 存储入口。
/// 完整趋势、应用排行与事件明细由独立报表窗口承载；本页保持克制与唯一视觉重心。
struct StatisticsSettingsView: View {
    @ObservedObject var recorder: StatisticsRecorder
    @ObservedObject var settings: MonitorSettings
    /// 跳转异常警报设置子页。
    var openAlerts: () -> Void = {}
    /// 跳转存储管理子页。
    var openStorage: () -> Void = {}

    /// 摘要数据源：正式运行跟随记录器发布；验证夹具模式下只读夹具。
    @StateObject private var dataSource: StatisticsOverviewDataSource
    @State private var range: StatisticsOverviewRange = StatisticsSettingsView.initialRange
    /// 当前范围的时间序列：事件聚合与压力累计由它推导，换范围或新桶封口时重取。
    @State private var series: [StatisticsRow] = []
    /// 压力告警：本页是「查看」落点，在屏即视为已读（红点清除）。
    @ObservedObject private var alerts = PressureAlertCenter.shared
    /// 实时应用高负载提示（与历史概览卡片空间分离）。
    @ObservedObject private var processAlerts = ProcessAlertCenter.shared
    /// 系统通知权限状态：用于在入口行及时提示权限缺失。
    @ObservedObject private var notificationDelegate = AlertNotificationDelegate.shared
    /// 本页是否真的在屏（窗口可见且为活跃窗口）→ 新告警直接按已读处理。
    @State private var isPageOnScreen = false
    /// 同一页面内的悬浮/点击明细浮层协调器：保证同一时刻至多只有一个详情浮层展开。
    @StateObject private var popoverCoordinator = HoverPopoverCoordinator()

    init(
        recorder: StatisticsRecorder,
        settings: MonitorSettings,
        openAlerts: @escaping () -> Void = {},
        openStorage: @escaping () -> Void = {}
    ) {
        self.recorder = recorder
        self.settings = settings
        self.openAlerts = openAlerts
        self.openStorage = openStorage
        _dataSource = StateObject(wrappedValue: StatisticsOverviewDataSource.make(recorder: recorder))
    }

    /// 初始范围可由验证环境变量指定（HAGIMI_STATS_RANGE=week/month），
    /// 便于三个范围逐项目测；正式运行始终从「今日」开始。
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

    /// 序列桶宽：从序列推断（判据见 StatisticsOverviewModel.bucketSeconds）。
    private var bucketSeconds: TimeInterval {
        StatisticsOverviewModel.bucketSeconds(for: range, series: series)
    }

    var body: some View {
        SettingsPage {
            controlGroup

            if settings.statisticsEnabled, !visibleApplicationGroups.isEmpty {
                activeHighLoadCard
            }

            summaryGroup

            SettingsGroup {
                entryRow(
                    icon: "internaldrive",
                    title: String(localized: "settings.sidebar.storage"),
                    trailingText: storageTotalText,
                    action: openStorage
                )
            }
        }
        .task {
            dataSource.start()
            loadSeries()
            notificationDelegate.refreshAuthorizationStatus()
        }
        .onAppear { recorder.setOverviewObservationActive(true) }
        .onDisappear { recorder.setOverviewObservationActive(false) }
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

    // MARK: - 1. 控制卡片

    private var controlGroup: some View {
        let toggleSubtitle = (settings.statisticsEnabled && recorder.recordDays > 0)
            ? String(localized: "stats.settings.record-days \(recorder.recordDays)")
            : nil

        return SettingsGroup {
            SettingsRow(title: String(localized: "stats.settings.toggle"), subtitle: toggleSubtitle) {
                Toggle(String(localized: "stats.settings.toggle"), isOn: $settings.statisticsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if settings.statisticsEnabled {
                SettingsDivider()
                alertsEntryRow
            }
        }
    }

    private var alertsEntryRow: some View {
        let isDenied = settings.alertNotificationsEnabled && notificationDelegate.authorizationStatus == .denied
        let iconName = settings.alertNotificationsEnabled ? "bell.badge" : "bell"
        let iconTint: Color = isDenied ? palette.severityTint(for: .warning) : .secondary

        return Button(action: openAlerts) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundStyle(iconTint)
                    .frame(width: 24)

                Text(String(localized: "stats.alerts.title"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 16)

                Text(alertsEntryStatusText)
                    .font(.callout)
                    .foregroundStyle(isDenied ? palette.severityTint(for: .warning) : .secondary)

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

    private var alertsEntryStatusText: String {
        if !settings.alertNotificationsEnabled {
            return String(localized: "stats.alerts.status.off")
        }
        if notificationDelegate.authorizationStatus == .denied {
            return String(localized: "stats.alerts.status.unauthorized")
        }
        let count = settings.enabledAlertCategoryCount
        if count < 3 {
            return String(localized: "stats.alerts.status.partial \(count)")
        }
        return String(localized: "stats.alerts.status.on")
    }

    // MARK: - 2. 独立实时高负载提示条

    private var visibleApplicationGroups: [ProcessAppAlertGroup] {
        let base: [ProcessAppAlertGroup]
        #if DEBUG
        if let fixture = StatisticsApplicationFixture.fromEnvironment() {
            base = fixture
        } else {
            base = processAlerts.activeAppGroups
        }
        #else
        base = processAlerts.activeAppGroups
        #endif

        return base
            .filter { !settings.isAlertAppIgnored(appKey: $0.appKey, name: $0.name) }
            .sorted {
                if $0.maxDurationMinutes != $1.maxDurationMinutes {
                    return $0.maxDurationMinutes > $1.maxDurationMinutes
                }
                return $0.appKey < $1.appKey
            }
    }

    private var activeHighLoadCard: some View {
        SettingsGroup {
            ActiveHighLoadBanner(
                groups: visibleApplicationGroups,
                onIgnore: { group in
                    settings.addIgnoredAlertApp(
                        AlertIgnoredApp.from(appKey: group.appKey, displayName: group.name)
                    )
                },
                onOpenApps: {
                    let leading = visibleApplicationGroups.first
                    let metric = leading.flatMap { StatisticsApplicationObservationRow.primaryEpisode(in: $0)?.metric }
                    StatisticsReportFlow.open(
                        recorder: recorder,
                        context: StatisticsReportContext(
                            range: range,
                            anchor: .apps,
                            appKey: visibleApplicationGroups.count == 1 ? leading?.appKey : nil,
                            metric: visibleApplicationGroups.count == 1 ? metric : nil
                        )
                    )
                }
            )
        }
    }

    // MARK: - 3. 统计概览卡片（唯一视觉重心）

    private var summaryGroup: some View {
        SettingsGroup(
            String(localized: "stats.overview.title"),
            titleAccessory: {
                Button {
                    StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range))
                } label: {
                    Label(String(localized: "stats.settings.open-report"), systemImage: "arrow.up.forward")
                }
                .buttonStyle(.link)
                .font(.callout)
                .fixedSize()
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                rangeBar
                fullBleedDivider

                if !settings.statisticsEnabled {
                    statusNoticeRow(
                        icon: "pause.circle",
                        tint: .secondary,
                        headline: String(localized: "stats.summary.off"),
                        detail: String(localized: "stats.summary.off.detail")
                    )
                } else if let row = aggregate {
                    pressureStatusRow(for: row)
                    fullBleedDivider
                    metricsGrid(for: row)
                } else {
                    statusNoticeRow(
                        icon: "tray",
                        tint: .secondary,
                        headline: String(localized: "stats.summary.noRecord"),
                        detail: String(localized: "stats.summary.noRecord.detail")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var coverageSummary: StatisticsOverviewModel.CoverageSummary {
        StatisticsOverviewModel.coverageSummary(for: range, row: aggregate, now: dataSource.referenceNow)
    }

    private var rangeBar: some View {
        HStack(spacing: 12) {
            Picker(String(localized: "overview.range.label"), selection: $range) {
                Text(String(localized: "stats.settings.range.today")).tag(StatisticsOverviewRange.today)
                Text(String(localized: "stats.settings.range.week")).tag(StatisticsOverviewRange.week)
                Text(String(localized: "stats.settings.range.month")).tag(StatisticsOverviewRange.month)
            }
            .labelsHidden()
            .compatibleTabPickerStyle()
            .fixedSize()

            Spacer(minLength: 8)

            CoverageClockButton(
                range: range,
                summary: coverageSummary,
                isRecordingEnabled: settings.statisticsEnabled,
                popoverCoordinator: popoverCoordinator
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var fullBleedDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.35))
            .frame(height: 1)
    }

    // MARK: - 系统压力双格状态栏（内存压力 | 热压力）

    private func pressureStatusRow(for row: StatisticsRow) -> some View {
        HStack(spacing: 0) {
            PressureStatusCell(
                status: StatisticsOverviewModel.dimensionStatus(for: .memory, row: row, events: events),
                palette: palette,
                popoverCoordinator: popoverCoordinator,
                onOpenReport: {
                    StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range, anchor: .memory))
                }
            )
            gridVerticalDivider
            PressureStatusCell(
                status: StatisticsOverviewModel.dimensionStatus(for: .thermal, row: row, events: events),
                palette: palette,
                popoverCoordinator: popoverCoordinator,
                onOpenReport: {
                    StatisticsReportFlow.open(recorder: recorder, context: StatisticsReportContext(range: range, anchor: .thermal))
                }
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statusNoticeRow(
        icon: String,
        tint: Color,
        headline: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 2×3 指标宫格

    private struct MetricCellData {
        enum Content {
            case average(value: String?, secondary: String?)
            case pair(firstLabel: String, firstValue: String, secondLabel: String, secondValue: String)
            case empty
        }

        let label: String
        let icon: String
        let tint: Color
        let content: Content
    }

    private func metricsGrid(for row: StatisticsRow) -> some View {
        let cells = makeGridCells(from: row)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                WorkloadMetricCell(
                    label: String(localized: "stats.metrics.cpu"),
                    icon: MonitorKind.cpu.symbol,
                    tint: palette.moduleTint(for: .cpu),
                    workload: StatisticsOverviewModel.workloadSummary(for: .cpu, row: row),
                    popoverCoordinator: popoverCoordinator
                )
                gridVerticalDivider
                WorkloadMetricCell(
                    label: String(localized: "stats.metrics.gpu"),
                    icon: MonitorKind.gpu.symbol,
                    tint: palette.moduleTint(for: .gpu),
                    workload: StatisticsOverviewModel.workloadSummary(for: .gpu, row: row),
                    popoverCoordinator: popoverCoordinator
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            gridHorizontalDivider
            gridRow(left: cells[0], right: cells[1])
            gridHorizontalDivider
            gridRow(left: cells[2], right: cells[3])
        }
    }

    private func gridRow(left: MetricCellData, right: MetricCellData) -> some View {
        HStack(spacing: 0) {
            metricCell(left)
            gridVerticalDivider
            metricCell(right)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var gridHorizontalDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.30))
            .frame(height: 1)
    }

    private var gridVerticalDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.30))
            .frame(width: 1)
    }

    private func metricCell(_ cell: MetricCellData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: cell.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(cell.tint)
                    .frame(width: 13, alignment: .center)

                Text(cell.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            switch cell.content {
            case .average(let value, let secondary):
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(localized: "stats.metrics.word.average"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

            case .pair(let firstLabel, let firstValue, let secondLabel, let secondValue):
                VStack(alignment: .leading, spacing: 3) {
                    pairValueRow(label: firstLabel, value: firstValue)
                    pairValueRow(label: secondLabel, value: secondValue)
                }

            case .empty:
                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pairValueRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func makeGridCells(from row: StatisticsRow) -> [MetricCellData] {
        let memSecondary = row.memPctMax.map {
            "\(String(localized: "stats.r.prefixPeak", defaultValue: "峰值")) \(StatisticsDisplayFormat.percent($0))"
        }
        let powerSecondary = row.powerMax.map {
            "\(String(localized: "stats.r.prefixPeak", defaultValue: "峰值")) \(String(format: "%.1f W", $0))"
        }

        let networkContent: MetricCellData.Content = if row.netDown != nil || row.netUp != nil {
            .pair(
                firstLabel: "↓",
                firstValue: StatisticsDisplayFormat.decimalVolume(row.netDown ?? 0),
                secondLabel: "↑",
                secondValue: StatisticsDisplayFormat.decimalVolume(row.netUp ?? 0)
            )
        } else {
            .empty
        }

        let diskContent: MetricCellData.Content = if row.diskRead != nil || row.diskWrite != nil {
            .pair(
                firstLabel: String(localized: "stats.metrics.word.read"),
                firstValue: StatisticsDisplayFormat.decimalVolume(row.diskRead ?? 0),
                secondLabel: String(localized: "stats.metrics.word.write"),
                secondValue: StatisticsDisplayFormat.decimalVolume(row.diskWrite ?? 0)
            )
        } else {
            .empty
        }

        return [
            MetricCellData(
                label: String(localized: "stats.metrics.memoryUsage"),
                icon: MonitorKind.memory.symbol,
                tint: palette.moduleTint(for: .memory),
                content: .average(
                    value: row.memPctAvg.map { StatisticsDisplayFormat.percent($0) },
                    secondary: memSecondary
                )
            ),
            MetricCellData(
                label: String(localized: "stats.metrics.power"),
                icon: MonitorKind.battery.symbol,
                tint: palette.moduleTint(for: .battery),
                content: .average(
                    value: row.powerAvg.map { String(format: "%.1f W", $0) },
                    secondary: powerSecondary
                )
            ),
            MetricCellData(
                label: String(localized: "overview.resources.network"),
                icon: MonitorKind.network.symbol,
                tint: palette.moduleTint(for: .network),
                content: networkContent
            ),
            MetricCellData(
                label: String(localized: "stats.metrics.disk"),
                icon: MonitorKind.storage.symbol,
                tint: palette.moduleTint(for: .storage),
                content: diskContent
            ),
        ]
    }

    // MARK: - 4. 存储入口

    private var storageTotalText: String? {
        guard let info = recorder.storageInfo else { return nil }
        return ByteCountFormatter.string(fromByteCount: info.totalBytes, countStyle: .file)
    }

    /// 功能入口行：图标 + 标题 + 可选状态/大小 + 右箭头，视觉统一。
    @ViewBuilder
    private func entryRow(
        icon: String,
        title: String,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
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

                if let trailingText {
                    Text(trailingText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

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

/// 百分比文本格式化：卡片正面采用紧凑整数，悬浮明细保留一位小数。
private enum OverviewShareFormat {
    static func compact(_ ratio: Double) -> String {
        let clamped = min(1, max(0, ratio))
        if clamped == 0 { return "0%" }
        let percent = clamped * 100
        if percent < 1 { return "<1%" }
        return String(format: "%.0f%%", percent.rounded())
    }

    static func detailed(_ ratio: Double) -> String {
        let clamped = min(1, max(0, ratio))
        if clamped == 0 { return "0%" }
        let percent = clamped * 100
        if percent < 0.1 { return "<0.1%" }
        if percent >= 99.95 { return "100%" }
        return String(format: "%.1f%%", percent)
    }
}

/// 视图悬停边界判定：显式裁切到 `bounds` 与滚动可视区交集，隔离 macOS 14+ 默认
/// `clipsToBounds == false` 时 `visibleRect` 向外溢出的祖先区域。
enum NativeHoverGeometry {
    static func activeRect(bounds: CGRect, visibleRect: CGRect) -> CGRect {
        let rect = bounds.intersection(visibleRect)
        return rect.isNull ? .zero : rect
    }

    static func contains(localPoint: CGPoint, bounds: CGRect, visibleRect: CGRect) -> Bool {
        let rect = activeRect(bounds: bounds, visibleRect: visibleRect)
        return !rect.isEmpty && rect.contains(localPoint)
    }
}

/// 基于 AppKit `NSTrackingArea` 的精确悬停追踪器，替代 `ScrollView` + `fullSizeContentView`
/// 工具栏窗口下可能出现坐标系漂移或穿透子浮层窗口的 SwiftUI `.onHover`。
struct NativeHoverTracker: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChange = onHoverChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHoverChange = onHoverChange
    }

    static func dismantleNSView(_ view: TrackingView, coordinator: ()) {
        view.stopTracking()
        view.onHoverChange = nil
    }

    final class TrackingView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        private var isHovering = false
        private var trackingArea: NSTrackingArea?
        private var trackedRect: CGRect = .zero
        private let scrollObservers = NotificationObserversBox()

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            refreshTrackingArea()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            refreshTrackingArea()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window {
                stopTracking()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scrollObservers.removeAll()

            guard window != nil else {
                stopTracking()
                return
            }

            if let clipView = enclosingScrollView?.contentView {
                clipView.postsBoundsChangedNotifications = true
                let observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.refreshTrackingArea()
                        self?.evaluatePointer()
                    }
                }
                scrollObservers.add(observer)
            }
            refreshTrackingArea()
        }

        func refreshTrackingArea() {
            let rect = NativeHoverGeometry.activeRect(bounds: bounds, visibleRect: visibleRect)
            guard rect != trackedRect else { return }

            if let trackingArea {
                removeTrackingArea(trackingArea)
                self.trackingArea = nil
            }
            trackedRect = rect
            guard !rect.isEmpty else { return }

            // 显式使用裁切后的子矩形且不传 `.inVisibleRect`，防止 tracking area 越过 `bounds`。
            let area = NSTrackingArea(
                rect: rect,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            evaluatePointer()
        }

        override func mouseMoved(with event: NSEvent) {
            evaluatePointer()
        }

        override func mouseExited(with event: NSEvent) {
            report(false)
        }

        func evaluatePointer() {
            guard let window, window.isVisible, !window.ignoresMouseEvents, !isHiddenOrHasHiddenAncestor else {
                report(false)
                return
            }
            let screenPoint = NSEvent.mouseLocation
            // 指针落在前端 `_NSPopoverWindow` 或其他应用窗口上时，禁止底层触发格穿透接管。
            guard NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0) == window.windowNumber else {
                report(false)
                return
            }
            let localPoint = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            report(NativeHoverGeometry.contains(localPoint: localPoint, bounds: bounds, visibleRect: visibleRect))
        }

        func stopTracking() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
                self.trackingArea = nil
            }
            trackedRect = .zero
            scrollObservers.removeAll()
            report(false)
        }

        private func report(_ hovering: Bool) {
            guard hovering != isHovering else { return }
            isHovering = hovering
            onHoverChange?(hovering)
        }
    }
}

/// 同页详情浮层的互斥协调器：保证同一时刻至多只有一个详情浮层展开。
@MainActor
final class HoverPopoverCoordinator: ObservableObject {
    private weak var activeController: HoverPopoverController?

    func willPresent(_ controller: HoverPopoverController) {
        if let active = activeController, active !== controller {
            active.dismissImmediately()
        }
        activeController = controller
    }

    func didDismiss(_ controller: HoverPopoverController) {
        if activeController === controller {
            activeController = nil
        }
    }
}

/// 悬浮/点击双驱弹窗控制器：触发区与弹窗本体共用悬停状态，离开两侧后防抖收起，点击可固定开关。
@MainActor
final class HoverPopoverController: ObservableObject {
    /// 弹出防抖高于收起防抖，避免指针在相邻格之间移过时旧浮层尚未收起、新浮层已抢先弹出。
    static let defaultShowDelay: Duration = .milliseconds(200)
    static let defaultHideDelay: Duration = .milliseconds(150)

    @Published var isPresented = false {
        didSet {
            if !isPresented {
                openedByClick = false
                coordinator?.didDismiss(self)
            }
        }
    }

    private let showDelay: Duration
    private let hideDelay: Duration
    private weak var coordinator: HoverPopoverCoordinator?
    private var hoveringTrigger = false
    private var hoveringContent = false
    private var openedByClick = false
    private var pendingTask: Task<Void, Never>?

    init(
        coordinator: HoverPopoverCoordinator? = nil,
        showDelay: Duration = HoverPopoverController.defaultShowDelay,
        hideDelay: Duration = HoverPopoverController.defaultHideDelay
    ) {
        self.coordinator = coordinator
        self.showDelay = showDelay
        self.hideDelay = hideDelay
    }

    func attach(coordinator: HoverPopoverCoordinator?) {
        self.coordinator = coordinator
    }

    func setTriggerHover(_ hovering: Bool) {
        hoveringTrigger = hovering
        if openedByClick { return }
        scheduleUpdate()
    }

    func setContentHover(_ hovering: Bool) {
        hoveringContent = hovering
        if openedByClick { return }
        scheduleUpdate()
    }

    func toggle() {
        pendingTask?.cancel()
        pendingTask = nil
        if isPresented {
            openedByClick = false
            isPresented = false
        } else {
            coordinator?.willPresent(self)
            openedByClick = true
            isPresented = true
        }
    }

    func dismissImmediately() {
        pendingTask?.cancel()
        pendingTask = nil
        openedByClick = false
        if isPresented {
            isPresented = false
        } else {
            coordinator?.didDismiss(self)
        }
    }

    private func scheduleUpdate() {
        pendingTask?.cancel()
        let shouldShow = hoveringTrigger || hoveringContent
        guard shouldShow != isPresented else { return }
        let delay: Duration = shouldShow ? showDelay : hideDelay
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.openedByClick else { return }
            let current = self.hoveringTrigger || self.hoveringContent
            if self.isPresented != current {
                if current {
                    self.coordinator?.willPresent(self)
                }
                self.isPresented = current
            }
        }
    }
}

/// 顶栏右上角统计覆盖度时钟图标：悬浮或点击查看数据完整度百分比与已累计统计时长。
private struct CoverageClockButton: View {
    let range: StatisticsOverviewRange
    let summary: StatisticsOverviewModel.CoverageSummary
    let isRecordingEnabled: Bool
    let popoverCoordinator: HoverPopoverCoordinator

    @StateObject private var hoverPopover: HoverPopoverController
    @State private var isHovered = false

    init(
        range: StatisticsOverviewRange,
        summary: StatisticsOverviewModel.CoverageSummary,
        isRecordingEnabled: Bool,
        popoverCoordinator: HoverPopoverCoordinator
    ) {
        self.range = range
        self.summary = summary
        self.isRecordingEnabled = isRecordingEnabled
        self.popoverCoordinator = popoverCoordinator
        _hoverPopover = StateObject(wrappedValue: HoverPopoverController(coordinator: popoverCoordinator))
    }

    private var rangeTitle: String {
        switch range {
        case .today: String(localized: "stats.settings.range.today")
        case .week: String(localized: "stats.settings.range.week")
        case .month: String(localized: "stats.settings.range.month")
        }
    }

    var body: some View {
        Button {
            hoverPopover.toggle()
        } label: {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered || hoverPopover.isPresented ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered || hoverPopover.isPresented ? 0.08 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(
            NativeHoverTracker { hovering in
                isHovered = hovering
                hoverPopover.setTriggerHover(hovering)
            }
        )
        .onAppear {
            hoverPopover.attach(coordinator: popoverCoordinator)
        }
        .accessibilityLabel(Text(String(localized: "stats.coverage.accessibility")))
        .popover(isPresented: $hoverPopover.isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(String(localized: "stats.coverage.title"))
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(rangeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "stats.coverage.completeness"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(OverviewShareFormat.compact(summary.completeness))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.16))
                            if summary.completeness > 0 {
                                Capsule()
                                    .fill(isRecordingEnabled ? Color.accentColor : Color.secondary)
                                    .frame(width: max(4, proxy.size.width * summary.completeness))
                            }
                        }
                    }
                    .frame(height: 4)
                }

                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.30))
                    .frame(height: 1)

                VStack(spacing: 5) {
                    HStack {
                        Text(String(localized: "stats.coverage.recorded-label"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(
                            summary.recordedSeconds > 0
                                ? StatisticsDisplayFormat.duration(summary.recordedSeconds)
                                : String(localized: "stats.summary.noRecord")
                        )
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    }

                    HStack {
                        Text(String(localized: "stats.coverage.window-label"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(StatisticsDisplayFormat.duration(summary.windowElapsedSeconds))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if !isRecordingEnabled {
                    Text(String(localized: "stats.summary.off"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 248)
            .background(
                NativeHoverTracker { hovering in
                    hoverPopover.setContentHover(hovering)
                }
            )
        }
    }
}

/// 单一维度的系统压力原生档位描述，供环图、状态格与悬浮详表共用。
private enum PressureLevelGuide {
    struct Entry: Identifiable {
        let level: Int
        let title: String
        let help: String
        let severity: MonitorSeverity
        var id: Int { level }
    }

    static func entries(for kind: StatisticsOverviewModel.Event.Kind) -> [Entry] {
        switch kind {
        case .memory:
            return [
                Entry(
                    level: 0,
                    title: String(localized: "memory-pressure.normal"),
                    help: String(localized: "stats.pressure.help.memory.normal"),
                    severity: .calm
                ),
                Entry(
                    level: 1,
                    title: String(localized: "memory-pressure.warning"),
                    help: String(localized: "stats.pressure.help.memory.warning"),
                    severity: .warning
                ),
                Entry(
                    level: 2,
                    title: String(localized: "memory-pressure.critical"),
                    help: String(localized: "stats.pressure.help.memory.critical"),
                    severity: .critical
                ),
            ]
        case .thermal:
            return [
                Entry(
                    level: 0,
                    title: String(localized: "thermal-pressure.normal"),
                    help: String(localized: "stats.pressure.help.thermal.normal"),
                    severity: .calm
                ),
                Entry(
                    level: 2,
                    title: String(localized: "thermal-pressure.serious"),
                    help: String(localized: "stats.pressure.help.thermal.serious"),
                    severity: .warning
                ),
                Entry(
                    level: 3,
                    title: String(localized: "thermal-pressure.critical"),
                    help: String(localized: "stats.pressure.help.thermal.critical"),
                    severity: .critical
                ),
            ]
        }
    }

    static func entry(for kind: StatisticsOverviewModel.Event.Kind, level: Int) -> Entry? {
        entries(for: kind).first { $0.level == level }
    }

    static func severity(kind: StatisticsOverviewModel.Event.Kind, level: Int) -> MonitorSeverity {
        switch (kind, level) {
        case (_, 0): .calm
        case (.memory, 2...), (.thermal, 3...): .critical
        default: .warning
        }
    }
}

/// 微型系统压力占比环形图：一圈代表该时段全部有效观测，绿/黄/红直观映射正常、警告、严重占比。
private struct PressureDonutRing: View {
    let status: StatisticsOverviewModel.DimensionStatus
    let palette: MonitorPalette

    private let size: CGFloat = 40
    private let strokeWidth: CGFloat = 5.5

    var body: some View {
        ZStack {
            switch status.state {
            case .noData:
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: strokeWidth)
            case .insufficient:
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.28),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, dash: [4, 3])
                    )
            case .normal:
                Circle()
                    .stroke(palette.severityTint(for: .calm), lineWidth: strokeWidth)
            case .hasPressure:
                let segments = displaySegments
                if segments.isEmpty {
                    Circle()
                        .stroke(palette.severityTint(for: .warning), lineWidth: strokeWidth)
                } else if segments.count == 1 {
                    Circle()
                        .stroke(segments[0].color, lineWidth: strokeWidth)
                } else {
                    ForEach(segments) { segment in
                        Circle()
                            .trim(from: segment.start, to: segment.end)
                            .stroke(segment.color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct Segment: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let color: Color
    }

    private var displaySegments: [Segment] {
        // 12 点钟顺时针优先排异常档（最严重 → 警告 → 正常），让极短异常片段也能一眼看到。
        let ordered = status.slices
            .filter { $0.seconds > 0 }
            .sorted { lhs, rhs in
                if (lhs.level == 0) != (rhs.level == 0) {
                    return rhs.level == 0
                }
                return lhs.level > rhs.level
            }
        guard !ordered.isEmpty else { return [] }
        if ordered.count == 1 {
            let color = palette.severityTint(for: PressureLevelGuide.severity(kind: status.kind, level: ordered[0].level))
            return [Segment(id: ordered[0].level, start: 0, end: 1, color: color)]
        }

        let minFraction = 0.045
        var shares = ordered.map(\.share)
        var deficit = 0.0
        for index in shares.indices where shares[index] < minFraction {
            deficit += (minFraction - shares[index])
            shares[index] = minFraction
        }
        if deficit > 0 {
            let expandable = shares.indices
                .filter { shares[$0] > minFraction }
                .reduce(0.0) { $0 + (shares[$1] - minFraction) }
            if expandable > 0 {
                let scale = min(1.0, deficit / expandable)
                for index in shares.indices where shares[index] > minFraction {
                    shares[index] -= (shares[index] - minFraction) * scale
                }
            }
        }

        let gap = 0.012
        var cursor = 0.0
        var result: [Segment] = []
        for (index, slice) in ordered.enumerated() {
            let length = shares[index]
            let start = cursor + gap / 2
            let end = cursor + length - gap / 2
            if end > start {
                let color = palette.severityTint(for: PressureLevelGuide.severity(kind: status.kind, level: slice.level))
                result.append(Segment(id: slice.level, start: start, end: end, color: color))
            }
            cursor += length
        }
        return result
    }
}

/// 统计概览顶栏的单格压力状态：头部点击直达完整报表，环图与状态区悬浮/点击展开各档时长与释义。
private struct PressureStatusCell: View {
    let status: StatisticsOverviewModel.DimensionStatus
    let palette: MonitorPalette
    let popoverCoordinator: HoverPopoverCoordinator
    let onOpenReport: () -> Void

    @StateObject private var hoverPopover: HoverPopoverController
    @State private var isBodyHovered = false

    init(
        status: StatisticsOverviewModel.DimensionStatus,
        palette: MonitorPalette,
        popoverCoordinator: HoverPopoverCoordinator,
        onOpenReport: @escaping () -> Void
    ) {
        self.status = status
        self.palette = palette
        self.popoverCoordinator = popoverCoordinator
        self.onOpenReport = onOpenReport
        _hoverPopover = StateObject(wrappedValue: HoverPopoverController(coordinator: popoverCoordinator))
    }

    private var dimensionTitle: String {
        switch status.kind {
        case .memory: String(localized: "stats.pressure.label.memory")
        case .thermal: String(localized: "stats.pressure.label.thermal")
        }
    }

    private var worstAbnormalTint: Color {
        if let worstLevel = status.abnormalSlices.map(\.level).max() {
            return palette.severityTint(for: PressureLevelGuide.severity(kind: status.kind, level: worstLevel))
        }
        return palette.severityTint(for: .warning)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpenReport) {
                HStack(spacing: 6) {
                    Text(dimensionTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if status.isOngoing {
                        PressureStateBadge(state: .ongoing, severityTint: worstAbnormalTint)
                    } else if status.isInterrupted {
                        PressureStateBadge(state: .interrupted, severityTint: .secondary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                hoverPopover.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    PressureDonutRing(status: status, palette: palette)

                    statusSummaryText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isBodyHovered || hoverPopover.isPresented ? 0.045 : 0))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                NativeHoverTracker { hovering in
                    isBodyHovered = hovering
                    hoverPopover.setTriggerHover(hovering)
                }
            )
            .padding(.horizontal, -6)
            .onAppear {
                hoverPopover.attach(coordinator: popoverCoordinator)
            }
            .popover(isPresented: $hoverPopover.isPresented, arrowEdge: .bottom) {
                PressureBreakdownPopover(status: status, palette: palette)
                    .background(
                        NativeHoverTracker { hovering in
                            hoverPopover.setContentHover(hovering)
                        }
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusSummaryText: some View {
        switch status.state {
        case .noData:
            Text(String(localized: "stats.pressure.state.no-data"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .insufficient:
            Text(String(localized: "stats.pressure.state.insufficient"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .normal:
            Text(String(localized: "stats.pressure.state.normal"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        case .hasPressure:
            if !status.abnormalSlices.isEmpty {
                let slices = Array(status.abnormalSlices.prefix(2))
                let isSingle = slices.count == 1
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slices) { slice in
                        let entry = PressureLevelGuide.entry(for: status.kind, level: slice.level)
                        let severity = PressureLevelGuide.severity(kind: status.kind, level: slice.level)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(entry?.title ?? "")
                                .font(.system(size: isSingle ? 14 : 13, weight: severity == .critical ? .semibold : .medium))
                                .foregroundStyle(palette.severityTint(for: severity))
                                .lineLimit(1)

                            Text(OverviewShareFormat.compact(slice.share))
                                .font(.system(size: isSingle ? 15 : 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text(StatisticsDisplayFormat.duration(status.pressureSeconds))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

private struct PressureStateBadge: View {
    let state: StatisticsOverviewModel.Event.State
    let severityTint: Color

    var body: some View {
        switch state {
        case .ongoing:
            Text(String(localized: "overview.event.state.ongoing"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(severityTint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(severityTint.opacity(0.14), in: Capsule())
                .fixedSize()
        case .interrupted:
            Text(String(localized: "overview.event.state.interrupted"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .fixedSize()
        case .recovered:
            EmptyView()
        }
    }
}

/// 悬浮/点击压力环图时展示的明细面板：列出原生档位、具体时长、精确占比及白话含义。
private struct PressureBreakdownPopover: View {
    let status: StatisticsOverviewModel.DimensionStatus
    let palette: MonitorPalette

    private var title: String {
        switch status.kind {
        case .memory: String(localized: "stats.pressure.label.memory")
        case .thermal: String(localized: "stats.pressure.label.thermal")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 8)

                Text(
                    status.validSeconds > 0
                        ? String(localized: "stats.pressure.popover.valid \(StatisticsDisplayFormat.duration(status.validSeconds))")
                        : String(localized: "stats.pressure.state.no-data")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(PressureLevelGuide.entries(for: status.kind)) { entry in
                    let slice = status.slices.first { $0.level == entry.level }
                    let seconds = slice?.seconds ?? 0
                    let share = slice?.share ?? 0
                    let color = palette.severityTint(for: entry.severity)
                    let isHighlighted: Bool = switch entry.level {
                    case 0: status.state == .normal
                    default: seconds > 0
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)

                        Text(entry.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color)
                            .fixedSize()

                        Text(entry.help)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        if status.validSeconds > 0 {
                            Text(
                                seconds > 0
                                    ? StatisticsDisplayFormat.duration(seconds)
                                    : String(localized: "stats.pressure.popover.zero-duration")
                            )
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(seconds > 0 ? .primary : .secondary)
                            .fixedSize()

                            Text(OverviewShareFormat.detailed(share))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 38, alignment: .trailing)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHighlighted ? color.opacity(0.09) : Color.clear)
                    )
                }
            }

            if status.state == .insufficient {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.30))
                    .frame(height: 1)

                Text(String(localized: "stats.pressure.popover.insufficient-note"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 328)
    }
}

/// CPU / GPU 指标格：界面默认展示「平均使用率 + 高负载占比」，悬浮或点击弹出常规/高负载时长分解。
private struct WorkloadMetricCell: View {
    let label: String
    let icon: String
    let tint: Color
    let workload: StatisticsOverviewModel.WorkloadSummary
    let popoverCoordinator: HoverPopoverCoordinator

    @StateObject private var hoverPopover: HoverPopoverController
    @State private var isHovered = false

    init(
        label: String,
        icon: String,
        tint: Color,
        workload: StatisticsOverviewModel.WorkloadSummary,
        popoverCoordinator: HoverPopoverCoordinator
    ) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.workload = workload
        self.popoverCoordinator = popoverCoordinator
        _hoverPopover = StateObject(wrappedValue: HoverPopoverController(coordinator: popoverCoordinator))
    }

    var body: some View {
        if workload.hasBreakdown {
            Button {
                hoverPopover.toggle()
            } label: {
                cellContent(horizontalPadding: 10, verticalPadding: 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(isHovered || hoverPopover.isPresented ? 0.045 : 0))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(
                NativeHoverTracker { hovering in
                    isHovered = hovering
                    hoverPopover.setTriggerHover(hovering)
                }
            )
            .onAppear {
                hoverPopover.attach(coordinator: popoverCoordinator)
            }
            .popover(isPresented: $hoverPopover.isPresented, arrowEdge: .bottom) {
                WorkloadBreakdownPopover(label: label, icon: icon, tint: tint, workload: workload)
                    .background(
                        NativeHoverTracker { hovering in
                            hoverPopover.setContentHover(hovering)
                        }
                    )
            }
            .padding(4)
        } else {
            cellContent(horizontalPadding: 14, verticalPadding: 11)
        }
    }

    private func cellContent(horizontalPadding: CGFloat, verticalPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 13, alignment: .center)

                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let avg = workload.averagePercent {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(localized: "stats.metrics.word.average"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(StatisticsDisplayFormat.percent(avg))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if workload.hasHighLoad, let highShare = workload.highShare {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(localized: "stats.metrics.word.highLoad"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(OverviewShareFormat.compact(highShare))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.85))
                }
                .lineLimit(1)
            } else if let peak = workload.peakPercent {
                Text("\(String(localized: "stats.r.prefixPeak", defaultValue: "峰值")) \(StatisticsDisplayFormat.percent(peak))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// CPU / GPU 悬浮明细浮层：展示比例条、常规与高负载精确时长及平均/峰值使用率。
private struct WorkloadBreakdownPopover: View {
    let label: String
    let icon: String
    let tint: Color
    let workload: StatisticsOverviewModel.WorkloadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(label)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 8)

                if workload.validSeconds > 0 {
                    Text(String(localized: "stats.pressure.popover.valid \(StatisticsDisplayFormat.duration(workload.validSeconds))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if workload.validSeconds > 0, let highShare = workload.highShare, let normalShare = workload.normalShare {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.16))
                        if highShare > 0 {
                            Capsule()
                                .fill(tint)
                                .frame(width: max(5, proxy.size.width * highShare))
                        }
                    }
                }
                .frame(height: 6)

                VStack(alignment: .leading, spacing: 5) {
                    breakdownRow(
                        title: String(localized: "stats.workload.popover.normal"),
                        threshold: "<\(workload.kind.highThresholdPercent)%",
                        dotColor: Color.secondary.opacity(0.38),
                        titleColor: .primary,
                        seconds: workload.normalSeconds,
                        share: normalShare,
                        isHighlighted: false
                    )

                    breakdownRow(
                        title: String(localized: "stats.workload.popover.high"),
                        threshold: "≥\(workload.kind.highThresholdPercent)%",
                        dotColor: tint,
                        titleColor: tint,
                        seconds: workload.highSeconds,
                        share: highShare,
                        isHighlighted: workload.hasHighLoad
                    )
                }
            }

            if workload.averagePercent != nil || workload.peakPercent != nil {
                if workload.validSeconds > 0 {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.30))
                        .frame(height: 1)
                }

                VStack(spacing: 5) {
                    if let avg = workload.averagePercent {
                        HStack {
                            Text(String(localized: "stats.workload.popover.average"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(StatisticsDisplayFormat.percent(avg))
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }

                    if let peak = workload.peakPercent {
                        HStack {
                            Text(String(localized: "stats.workload.popover.peak"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(StatisticsDisplayFormat.percent(peak))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 292)
    }

    private func breakdownRow(
        title: String,
        threshold: String,
        dotColor: Color,
        titleColor: Color,
        seconds: Double,
        share: Double,
        isHighlighted: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleColor)
                .fixedSize()

            Text(threshold)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()

            Spacer(minLength: 8)

            Text(
                seconds > 0
                    ? StatisticsDisplayFormat.duration(seconds)
                    : String(localized: "stats.pressure.popover.zero-duration")
            )
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(seconds > 0 ? .primary : .secondary)
            .fixedSize()

            Text(OverviewShareFormat.detailed(share))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 38, alignment: .trailing)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHighlighted ? tint.opacity(0.09) : Color.clear)
        )
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
