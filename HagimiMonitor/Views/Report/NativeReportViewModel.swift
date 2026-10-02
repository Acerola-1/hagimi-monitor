import AppKit
import Combine
import IOKit.ps
import SwiftUI

/// 模块导航条目标识与元信息。
enum ReportNavigationModule: String, CaseIterable, Identifiable {
    case overview
    case cpu
    case gpu
    case memory
    case network
    case disk
    case power
    case thermal
    case apps
    case events
    case details
    case insights
    case machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "stats.r.navOverview", defaultValue: "系统概览")
        case .cpu: return String(localized: "stats.r.railCpu", defaultValue: "处理器")
        case .gpu: return String(localized: "stats.r.railGpu", defaultValue: "图形处理")
        case .memory: return String(localized: "stats.r.railMemory", defaultValue: "系统内存")
        case .network: return String(localized: "stats.r.railNet", defaultValue: "网络流量")
        case .disk: return String(localized: "stats.r.railDisk", defaultValue: "磁盘存储")
        case .power: return String(localized: "stats.r.railPower", defaultValue: "电源与电池")
        case .thermal: return String(localized: "stats.r.secThermal", defaultValue: "热压力")
        case .apps: return String(localized: "stats.r.secAppsTitle", defaultValue: "应用排行")
        case .events: return String(localized: "stats.r.secEvents", defaultValue: "压力警告")
        case .details: return String(localized: "stats.r.rawRecords", defaultValue: "原始数据")
        case .insights: return String(localized: "stats.r.secInsights", defaultValue: "智能洞察")
        case .machine: return String(localized: "stats.r.kThisMac", defaultValue: "本机规格")
        }
    }

    var label: String { title }

    /// SF Symbols 图标：严格对齐 MonitorKind 语义与系统契约 (R13)
    var icon: String {
        switch self {
        case .overview: return "gauge.medium"
        case .cpu: return MonitorKind.cpu.symbol // "cpu"
        case .gpu: return MonitorKind.gpu.symbol // "display"
        case .memory: return MonitorKind.memory.symbol // "memorychip"
        case .network: return MonitorKind.network.symbol // "network"
        case .disk: return MonitorKind.storage.symbol // "internaldrive"
        case .power: return MonitorKind.battery.symbol // "powerplug"
        case .thermal: return "flame"
        case .apps: return "app.badge.checkmark"
        case .events: return "exclamationmark.triangle"
        case .details: return "tablecells"
        case .insights: return "sparkles"
        case .machine: return "laptopcomputer"
        }
    }

    /// 只有六个硬件模块有右栏实时数据;其余模块使用完整宽度并停掉实时源。
    var liveMonitorKind: MonitorKind? {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .storage
        case .power: return .battery
        case .overview, .thermal, .apps, .events, .details, .insights, .machine:
            return nil
        }
    }
}

/// 独立的 1 秒实时硬件读数数据源。
///
/// 源只读取当前模块，且同时受窗口可见性和模块是否有右栏控制。采样器注入为
/// 闭包后，门控和去重可以在没有真实 MonitorStore 的测试中验证。
@MainActor
final class ReportLiveHardwareSource: ObservableObject {
    typealias ReadingsProvider = @MainActor (ReportNavigationModule) -> [String: String]?

    @Published private(set) var liveReadings: [String: String] = [:]

    private let readingsProvider: ReadingsProvider
    private let interval: TimeInterval
    private let tolerance: TimeInterval
    private var timer: Timer?
    private var activeModule: ReportNavigationModule?
    private var isWindowVisible = false
    private var isRunning = false
    private var isManuallyPaused = false

    init(
        interval: TimeInterval = 1.0,
        tolerance: TimeInterval = 0.1,
        readingsProvider: @escaping ReadingsProvider = ReportLiveHardwareSource.defaultReadingsProvider
    ) {
        self.interval = max(0.1, interval)
        self.tolerance = max(0, min(tolerance, self.interval * 0.5))
        self.readingsProvider = readingsProvider
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reconcileTimer()
        refreshIfEligible()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isManuallyPaused = false
        isWindowVisible = false
        liveReadings.removeAll()
    }

    func pause() {
        guard !isManuallyPaused else { return }
        isManuallyPaused = true
        reconcileTimer()
    }

    func resume() {
        guard isManuallyPaused else { return }
        isManuallyPaused = false
        reconcileTimer()
        refreshIfEligible()
    }

    /// 更新当前模块。切换到没有实时栏的模块时立即清空旧值，避免短暂显示上一模块。
    func setActiveModule(_ module: ReportNavigationModule) {
        guard activeModule != module else { return }
        activeModule = module
        publishIfChanged([:])
        reconcileTimer()
        refreshIfEligible()
    }

    /// 由窗口代理调用。可见恢复时会先取一帧，再继续周期采样。
    func setWindowVisible(_ isVisible: Bool) {
        let changed = self.isWindowVisible != isVisible
        self.isWindowVisible = isVisible
        reconcileTimer()
        if changed && isVisible {
            refreshIfEligible()
        }
    }

    private var canSample: Bool {
        guard isRunning, !isManuallyPaused, isWindowVisible,
              let activeModule,
              moduleSupportsLiveReadings(activeModule) else { return false }
        return true
    }

    private func moduleSupportsLiveReadings(_ module: ReportNavigationModule) -> Bool {
        module.liveMonitorKind != nil
    }

    private func reconcileTimer() {
        guard canSample else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerDidFire()
            }
        }
        newTimer.tolerance = tolerance
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func timerDidFire() {
        guard canSample else {
            reconcileTimer()
            return
        }
        refreshIfEligible()
    }

    private func refreshIfEligible() {
        guard canSample, let activeModule else { return }
        publishIfChanged(readingsProvider(activeModule) ?? [:])
    }

    private func publishIfChanged(_ readings: [String: String]) {
        guard readings != liveReadings else { return }
        liveReadings = readings
    }

    private static func defaultReadingsProvider(_ module: ReportNavigationModule) -> [String: String]? {
        guard let kind = module.liveMonitorKind,
              let store = AppDelegate.shared?.store,
              let monitorModule = store.modules.first(where: { $0.kind == kind }) else {
            return nil
        }
        return ReportLiveReadings.readings(for: monitorModule)
    }
}

/// 原生报表主视图模型。
/// 管理后台快照读取、时间范围过滤重算、版本请求校验，以及关窗后的资源销毁。
@MainActor
final class NativeReportViewModel: ObservableObject {
    private static var initialRange: ReportTimeRange {
        switch ProcessInfo.processInfo.environment["HAGIMI_REPORT_RANGE"] {
        case "week": return .week
        case "month": return .month
        case "year": return .year
        default: return .today
        }
    }

    @Published var selectedModule: ReportNavigationModule = .overview {
        didSet {
            guard oldValue != selectedModule else { return }
            liveSource.setActiveModule(selectedModule)
        }
    }
    @Published var selectedRange: ReportTimeRange = NativeReportViewModel.initialRange
    @Published private(set) var snapshot: ReportSnapshot?
    @Published private(set) var rangeModel: ReportActiveRangeModel?
    @Published private(set) var isLoading: Bool = true
    /// 硬件清单仍在后台采集。统计已可用，只有依赖硬件事实的区域需要显示加载态。
    @Published private(set) var isHardwareLoading: Bool = false
    @Published private(set) var isAggregating: Bool = false
    /// 应用排行：是否包含系统应用（默认开启，跨模块切换保持）
    @Published var includeSystemApps: Bool = true
    /// 应用排行的搜索、排序与展开状态，跨模块切换保持。
    @Published var appSearchText: String = ""
    @Published var appSortOrder: ReportAppRankingFilter.SortOrder = .value
    @Published var appsShowsAll: Bool = false
    /// 展开完整列表后当前渲染到多少条；按批增长，避免一次渲染数百行。
    @Published var appsRenderLimit: Int = ReportAppRankingFilter.renderBatch
    /// 深链目标应用与指标；用于应用页默认选中对应排行分类并定位应用行。
    @Published private(set) var focusedAppKey: String?
    @Published private(set) var focusedMetric: ProcessAlertEpisode.Metric?
    /// 深链事件；目标事件已被删除时用于展示「记录不存在」说明。
    @Published private(set) var focusedEventID: UUID?
    /// 深链事件在快照中是否确实存在；用于区分「待加载」与「已确认为缺失」。
    @Published private(set) var focusedEventIsMissing = false

    /// 判定当前选定范围是否为单日跨度（优先取已算好的 rangeModel，加载期回退取 selectedRange 的起止计算）
    var isSingleDaySelected: Bool {
        rangeModel?.isSingleDay ?? selectedRange.isSingleDay()
    }

    /// 独立的 1 秒实时更新源，供右栏硬件观察
    let liveSource = ReportLiveHardwareSource()

    private weak var recorder: StatisticsRecorder?
    private var aggregateTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var currentRequestID = UUID()
    private var isClosed = false

    init(recorder: StatisticsRecorder?) {
        self.recorder = recorder
        liveSource.setActiveModule(selectedModule)
    }

    // MARK: - 生命周期与加载

    /// 加载完整报表快照，可在携带锚点时直接跳转对应模块。
    func load(anchor: StatisticsReportAnchor? = nil) {
        apply(StatisticsReportContext(anchor: anchor))
    }

    /// 应用一次完整打开上下文：更新时间范围、模块、应用与指标选择，并同步重新加载快照。
    func apply(_ context: StatisticsReportContext) {
        if let range = context.range {
            selectedRange = range.reportTimeRange
        }
        switch context.anchor {
        case .memory: selectedModule = .memory
        case .thermal: selectedModule = .thermal
        case .apps: selectedModule = .apps
        case nil: break
        }
        if context.appKey != nil {
            selectedModule = .apps
        }
        focusedAppKey = context.appKey
        focusedMetric = context.metric
        focusedEventID = context.eventID
        focusedEventIsMissing = false
        reload()
    }

    /// 以当前上下文重新加载（不清除深链目标）。
    private func reload() {
        guard let recorder, !isClosed else {
            self.isLoading = false
            return
        }

        isLoading = true
        let requestID = UUID()
        self.currentRequestID = requestID

        let now = Date()
        let recordDays = recorder.recordDays
        let targetRange = selectedRange
        let dataProvider = recorder.reportDataProvider()
        // ProcessAlertCenter 是 MainActor 状态;只复制不可变值,后台不直接访问它。
        let alertSnapshot = ProcessAlertCenter.shared.activeAlerts + ProcessAlertCenter.shared.recentAlerts
        // NSScreen 只能在 MainActor 读取;这里只复制轻量值,重型硬件探针仍在后台。
        let screenSnapshots = DisplaySection.captureScreenSnapshots()

        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let input = dataProvider.load(now: now, alerts: alertSnapshot) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.currentRequestID == requestID, !self.isClosed else { return }
                    self.isLoading = false
                    self.isHardwareLoading = false
                }
                return
            }
            guard !Task.isCancelled else { return }

            let meta = ReportMeta(
                deviceName: StandaloneHTMLReportExporter.deviceName(),
                modelName: StandaloneHTMLReportExporter.modelName(),
                osVersion: "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)",
                recordDays: recordDays,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                isDirect: StandaloneHTMLReportExporter.isDirect
            )

            // 第一阶段：先发布统计数据，硬件清单在后台并行采集后补充。
            let statisticsSnapshot = ReportSnapshot(
                capturedAt: now,
                meta: meta,
                minutes: input.minutes,
                hours: input.hours,
                days: input.days,
                process: input.process,
                hardware: nil,
                systemSleepIntervals: input.systemSleepIntervals
            )

            let hasBattery = Self.checkHardwareBattery()
            let hasFans = Self.checkHardwareFans(model: meta.modelName)

            // 使用请求中的 targetRange 计算初次聚合。
            let statisticsModel = ReportDataAggregator.aggregate(
                snapshot: statisticsSnapshot,
                range: targetRange,
                now: now,
                hardwareHasBattery: hasBattery,
                hardwareHasFans: hasFans,
                fanSensorAvailable: meta.isDirect
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.currentRequestID == requestID, !self.isClosed else { return }
                self.snapshot = statisticsSnapshot
                self.rangeModel = statisticsModel
                self.isLoading = false
                self.isHardwareLoading = true
                self.resolveFocusedEvent(in: statisticsModel)
                self.liveSource.start()
            }

            // 第二阶段：硬件清单独立补充。失败只影响硬件区，不撤销已发布的统计。
            let hardware = HardwareInventoryReader().capture(
                screenSnapshots: screenSnapshots)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.currentRequestID == requestID, !self.isClosed else { return }
                let enriched = ReportSnapshot(
                    capturedAt: statisticsSnapshot.capturedAt,
                    meta: statisticsSnapshot.meta,
                    minutes: statisticsSnapshot.minutes,
                    hours: statisticsSnapshot.hours,
                    days: statisticsSnapshot.days,
                    process: statisticsSnapshot.process,
                    hardware: hardware,
                    systemSleepIntervals: statisticsSnapshot.systemSleepIntervals
                )
                let enrichedModel = ReportDataAggregator.aggregate(
                    snapshot: enriched,
                    range: targetRange,
                    now: now,
                    hardwareHasBattery: hasBattery,
                    hardwareHasFans: hasFans,
                    fanSensorAvailable: meta.isDirect
                )
                self.snapshot = enriched
                self.rangeModel = enrichedModel
                self.isHardwareLoading = false
                self.resolveFocusedEvent(in: enrichedModel)
            }
        }
    }

    /// 当前提交范围的导出上下文：标签与右开区间。
    ///
    /// 供打印与 HTML 导出使用，保证离线文件打开时先落在用户正在看的时间段，
    /// 而不是回退到默认的今日。
    func committedExportRange() -> (label: String, from: Date, to: Date)? {
        guard let model = rangeModel else { return nil }
        return (model.range.label, model.from, model.to)
    }

    /// 刷新当前报表快照，保留范围与深链目标（供「重新载入报表」使用）。
    func refreshCurrentReport() {
        reload()
    }

    /// 深链目标事件是否仍存在于已提交快照中。目标被删除时页面需要明确说明，
    /// 而不是静默地把用户切到别的应用或事件。
    private func resolveFocusedEvent(in model: ReportActiveRangeModel) {
        guard let focusedEventID else {
            focusedEventIsMissing = false
            return
        }
        // 在分组的所有 episode 中匹配目标事件 ID。
        let exists = model.apps.highLoadAlerts.contains { group in
            group.episodes.contains { $0.id == focusedEventID }
        }
        focusedEventIsMissing = !exists
    }

    /// 切换时间范围并重新计算聚合模型。
    func selectRange(_ range: ReportTimeRange) {
        guard selectedRange != range || rangeModel == nil else { return }
        selectedRange = range
        recomputeActiveRange()
    }

    /// 应用自定义时间范围
    func applyCustomRange(from: Date, to: Date) {
        selectedRange = .custom(from: from, to: to)
        recomputeActiveRange()
    }

    private func recomputeActiveRange() {
        guard let snapshot, !isClosed else { return }
        isAggregating = true
        let requestID = UUID()
        self.currentRequestID = requestID
        let range = selectedRange

        let hasBattery = Self.checkHardwareBattery()
        let hasFans = Self.checkHardwareFans(model: snapshot.meta.modelName)
        let isDirect = snapshot.meta.isDirect

        aggregateTask?.cancel()
        aggregateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let model = ReportDataAggregator.aggregate(
                snapshot: snapshot,
                range: range,
                hardwareHasBattery: hasBattery,
                hardwareHasFans: hasFans,
                fanSensorAvailable: isDirect
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentRequestID == requestID, !self.isClosed else { return }
                self.rangeModel = model
                self.isAggregating = false
            }
        }
    }

    // MARK: - 窗口可见性与定时器门控 (R10)

    func setWindowVisible(_ isVisible: Bool) {
        liveSource.setWindowVisible(isVisible)
    }

    /// 检测系统是否存在物理电池（台式 Mac 如 Mac mini / Mac Studio / Mac Pro 无电池）
    nonisolated private static func checkHardwareBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return false
        }
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let type = desc[kIOPSTypeKey] as? String,
               type == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }

    /// 检测物理风扇（MacBook Air / 被动散热设备无风扇）
    nonisolated private static func checkHardwareFans(model: String) -> Bool {
        // MacBook Air 采用全被动散热设计
        if model.localizedCaseInsensitiveContains("MacBookAir") {
            return false
        }
        return true
    }

    // MARK: - 资源彻底释放

    /// 窗口关闭时调用：取消任务、停定时器、置空数据并清空图标缓存
    func teardown() {
        isClosed = true
        liveSource.stop()
        loadTask?.cancel()
        loadTask = nil
        aggregateTask?.cancel()
        aggregateTask = nil
        snapshot = nil
        rangeModel = nil
        ReportIconProvider.shared.clear()
    }
}
