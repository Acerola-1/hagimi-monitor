import AppKit
import Combine
import IOKit.ps
import SwiftUI

/// 模块导航条目标识与元信息。
nonisolated enum ReportNavigationModule: String, CaseIterable, Identifiable, Sendable {
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
        case .overview: return String(localized: "report.ui.overview", defaultValue: "概览")
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

nonisolated struct ReportLivePressureReading: Equatable {
    let kind: ReportEventItem.Kind
    let level: Int
    let durationSeconds: TimeInterval

    var isCritical: Bool { level >= (kind == .memory ? 2 : 3) }
}

/// 实时压力以每个维度的新采样为准，连续时长只累计到最后一次有效观测。
nonisolated struct ReportLivePressureObservations {
    private struct Observation {
        let level: Int
        let startedAt: Date
        let observedAt: Date
    }

    private static let freshness: TimeInterval = 30
    private var memory: Observation?
    private var thermal: Observation?

    mutating func record(
        memoryLevel: Int?,
        thermalLevel: Int?,
        freshKinds: Set<MonitorKind>,
        at date: Date
    ) {
        if freshKinds.contains(.memory) {
            memory = Self.advance(memory, level: memoryLevel, threshold: 1, at: date)
        }
        if freshKinds.contains(.cpu) {
            thermal = Self.advance(thermal, level: thermalLevel, threshold: 2, at: date)
        }
    }

    private static func advance(
        _ previous: Observation?,
        level: Int?,
        threshold: Int,
        at date: Date
    ) -> Observation? {
        guard let level, level >= threshold else { return nil }
        let startedAt = previous.flatMap { previous in
            let gap = date.timeIntervalSince(previous.observedAt)
            return (0...freshness).contains(gap) ? previous.startedAt : nil
        } ?? date
        return Observation(level: level, startedAt: startedAt, observedAt: date)
    }

    func current(at date: Date) -> ReportLivePressureReading? {
        func reading(_ observation: Observation?, kind: ReportEventItem.Kind) -> ReportLivePressureReading? {
            guard let observation, (0...Self.freshness).contains(date.timeIntervalSince(observation.observedAt))
            else { return nil }
            return ReportLivePressureReading(
                kind: kind, level: observation.level,
                durationSeconds: observation.observedAt.timeIntervalSince(observation.startedAt)
            )
        }

        let memoryReading = reading(memory, kind: .memory)
        let thermalReading = reading(thermal, kind: .thermal)
        if let thermalReading, thermalReading.isCritical || memoryReading == nil {
            return thermalReading
        }
        return memoryReading
    }
}

/// 可见报表按当前模块读取缓存中的实时指标或压力。
@MainActor
final class ReportLiveHardwareSource: ObservableObject {
    typealias ReadingsProvider = @MainActor (ReportNavigationModule) -> [String: String]?
    typealias PressureProvider = @MainActor () -> ReportLivePressureReading?

    @Published private(set) var liveReadings: [String: String] = [:]
    @Published private(set) var livePressure: ReportLivePressureReading?

    private let readingsProvider: ReadingsProvider
    private let pressureProvider: PressureProvider
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
        readingsProvider: @escaping ReadingsProvider = ReportLiveHardwareSource.defaultReadingsProvider,
        pressureProvider: @escaping PressureProvider = {
            AppDelegate.shared?.store.reportLivePressure.current(at: Date())
        }
    ) {
        self.interval = max(0.1, interval)
        self.tolerance = max(0, min(tolerance, self.interval * 0.5))
        self.readingsProvider = readingsProvider
        self.pressureProvider = pressureProvider
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
        publishPressureIfChanged(nil)
    }

    func pause() {
        guard !isManuallyPaused else { return }
        isManuallyPaused = true
        publishPressureIfChanged(nil)
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
        publishPressureIfChanged(nil)
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
        } else if !isVisible {
            publishPressureIfChanged(nil)
        }
    }

    private var canSample: Bool {
        guard isRunning, !isManuallyPaused, isWindowVisible,
              let activeModule,
              activeModule == .overview || activeModule.liveMonitorKind != nil else { return false }
        return true
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
        if activeModule == .overview {
            publishPressureIfChanged(pressureProvider())
        } else {
            publishIfChanged(readingsProvider(activeModule) ?? [:])
        }
    }

    private func publishIfChanged(_ readings: [String: String]) {
        guard readings != liveReadings else { return }
        liveReadings = readings
    }

    private func publishPressureIfChanged(_ reading: ReportLivePressureReading?) {
        guard reading != livePressure else { return }
        livePressure = reading
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

/// 压力事件筛选分类。
nonisolated enum ReportEventFilterKind: String, CaseIterable, Identifiable, Sendable {
    case all
    case memory
    case thermal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "stats.r.allEvents", defaultValue: "全部事件")
        case .memory: return String(localized: "stats.r.alertMem", defaultValue: "内存压力")
        case .thermal: return String(localized: "stats.r.alertThermal", defaultValue: "热压力")
        }
    }
}

/// 跨模块跳转时用于高亮目标时间区间的聚焦窗。
nonisolated struct ReportFocusedTimeWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let title: String
    let kind: ReportEventItem.Kind?
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
    @Published private(set) var loadFailed = false
    @Published private(set) var isLoading: Bool = true
    /// 硬件清单仍在后台采集。统计已可用，只有依赖硬件事实的区域需要显示加载态。
    @Published private(set) var isHardwareLoading: Bool = false
    @Published private(set) var isAggregating: Bool = false
    /// 当前设备形态与电池能力（供顶栏自适应设备图标）。
    @Published private(set) var deviceFormFactor: ReportEnvironment.FormFactor = .laptop
    /// 有采样记录的本地自然日 `yyyyMMdd` 集合，用于日历浮窗日期点亮提示。
    @Published private(set) var recordedDayKeys: Set<Int64> = []
    /// 应用排行：是否包含系统应用（默认开启，跨模块切换保持）
    @Published var includeSystemApps: Bool = true
    /// 应用排行的搜索、排序与展开状态，跨模块切换保持。
    @Published var appSearchText: String = ""
    @Published var appSortOrder: ReportAppRankingFilter.SortOrder = .value
    @Published var appsShowsAll: Bool = false
    /// 展开完整列表后当前渲染到多少条；按批增长，避免一次渲染数百行。
    @Published var appsRenderLimit: Int = ReportAppRankingFilter.renderBatch
    /// 压力事件页当前过滤类别（支持从概览胶囊预设）。
    @Published var eventFilterKind: ReportEventFilterKind = .all
    /// 跨模块时间聚焦窗（用于在内存/热压力曲线上高亮对应事件区间）。
    @Published var focusedTimeWindow: ReportFocusedTimeWindow?
    /// 应用页滚动定位至告警区的令牌。
    @Published var scrollToAppAlertsToken: UUID?
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

    typealias SnapshotLoader = @Sendable (Date, [ProcessAlertEpisode]) -> StatisticsReportSnapshotInput?
    typealias HardwareLoader = @Sendable ([DisplayScreenSnapshot]) -> HardwareInventory
    private let snapshotLoader: SnapshotLoader?
    private let hardwareLoader: HardwareLoader?
    private weak var recorder: StatisticsRecorder?
    private var aggregateTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loadRequestID = UUID()
    private var aggregateRequestID = UUID()
    /// 快照每次替换（包含第二阶段硬件补全）均递增，防止基于旧快照启动的聚合任务覆写新模型。
    private var snapshotVersion: UInt64 = 0
    private var isClosed = false

    init(
        recorder: StatisticsRecorder?,
        snapshotLoader: SnapshotLoader? = nil,
        hardwareLoader: HardwareLoader? = nil
    ) {
        self.recorder = recorder
        self.snapshotLoader = snapshotLoader
        self.hardwareLoader = hardwareLoader
        liveSource.setActiveModule(selectedModule)
    }

    #if DEBUG
    /// 原生预览使用确定快照，不启动采样、存储读取或当前机器的硬件探针。
    convenience init(previewSnapshot: ReportSnapshot?, hardwareHasBattery: Bool,
                     hardwareHasFans: Bool, loadFailed: Bool = false) {
        self.init(recorder: nil)
        snapshot = previewSnapshot
        if previewSnapshot != nil {
            snapshotVersion &+= 1
        }
        if let previewSnapshot {
            rangeModel = ReportDataAggregator.aggregate(snapshot: previewSnapshot, range: selectedRange,
                now: previewSnapshot.capturedAt, hardwareHasBattery: hardwareHasBattery,
                hardwareHasFans: hardwareHasFans, fanSensorAvailable: previewSnapshot.meta.isDirect)
            recordedDayKeys = Self.computeRecordedDayKeys(from: previewSnapshot)
            deviceFormFactor = ReportEnvironment.formFactor(
                hasBattery: hardwareHasBattery,
                model: previewSnapshot.meta.modelName,
                hardware: previewSnapshot.hardware
            )
        }
        isLoading = false
        self.loadFailed = loadFailed
    }
    #endif

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
        focusedTimeWindow = nil
        reload()
    }

    /// 以当前上下文重新加载（不清除深链目标）。
    private func reload() {
        aggregateTask?.cancel()
        aggregateTask = nil
        isAggregating = false
        isHardwareLoading = false
        let recorder = self.recorder
        guard !isClosed, recorder != nil || snapshotLoader != nil else {
            self.isLoading = false
            self.loadFailed = true
            return
        }

        loadFailed = false
        isLoading = true
        let loadID = UUID()
        self.loadRequestID = loadID
        self.aggregateRequestID = loadID

        let now = Date()
        let recordDays = recorder?.recordDays ?? 0
        let loadInput: SnapshotLoader = snapshotLoader ?? { [recorder] now, alerts in
            recorder?.reportDataProvider().load(now: now, alerts: alerts)
        }
        let captureHardware: HardwareLoader = hardwareLoader ?? { snapshots in
            HardwareInventoryReader().capture(screenSnapshots: snapshots)
        }
        // ProcessAlertCenter 是 MainActor 状态;只复制不可变值,后台不直接访问它。
        let alertSnapshot = ProcessAlertCenter.shared.activeAlerts + ProcessAlertCenter.shared.recentAlerts
        // NSScreen 只能在 MainActor 读取;这里只复制轻量值,重型硬件探针仍在后台。
        let screenSnapshots = DisplaySection.captureScreenSnapshots()

        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            // 首次历史读取可能打开存储容器，句柄准备也留在后台。
            guard let input = loadInput(now, alertSnapshot) else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.loadRequestID == loadID, !self.isClosed else { return }
                    self.isLoading = false
                    self.loadFailed = true
                    self.isHardwareLoading = false
                }
                return
            }
            guard !Task.isCancelled else { return }

            let meta = ReportMeta(
                deviceName: ReportEnvironment.deviceName(),
                modelName: ReportEnvironment.modelName(),
                osVersion: "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)",
                recordDays: recordDays,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                isDirect: ReportEnvironment.isDirect
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
            let hasFans = ReportEnvironment.hasPhysicalFans(model: meta.modelName)
            let dayKeys = Self.computeRecordedDayKeys(from: statisticsSnapshot)
            let formFactor = ReportEnvironment.formFactor(hasBattery: hasBattery, model: meta.modelName)

            let activeRange = await MainActor.run { [weak self] in
                self?.selectedRange
            } ?? .today

            let statisticsModel = ReportDataAggregator.aggregate(
                snapshot: statisticsSnapshot,
                range: activeRange,
                now: now,
                hardwareHasBattery: hasBattery,
                hardwareHasFans: hasFans,
                fanSensorAvailable: meta.isDirect
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.loadRequestID == loadID, !self.isClosed else { return }
                self.snapshot = statisticsSnapshot
                self.snapshotVersion &+= 1
                self.recordedDayKeys = dayKeys
                self.deviceFormFactor = formFactor
                // 若期间用户已触发范围重算（aggregateRequestID 变化），不再用旧范围结果覆盖，只更新基础快照。
                if self.aggregateRequestID == loadID {
                    self.rangeModel = statisticsModel
                    self.resolveFocusedEvent(in: statisticsModel)
                } else {
                    self.recomputeActiveRange()
                }
                self.isLoading = false
                self.isHardwareLoading = true
                self.liveSource.start()
            }

            // 第二阶段：硬件清单独立补充。失败或用户期间切范围都不丢弃硬件档案。
            let hardware = captureHardware(screenSnapshots)

            guard !Task.isCancelled else { return }

            let latestRange = await MainActor.run { [weak self] in
                self?.selectedRange
            } ?? activeRange
            let refinedHasFans = ReportEnvironment.hasPhysicalFans(model: meta.modelName, hardware: hardware)
            let refinedFormFactor = ReportEnvironment.formFactor(
                hasBattery: hasBattery,
                model: meta.modelName,
                hardware: hardware
            )

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
                range: latestRange,
                now: now,
                hardwareHasBattery: hasBattery,
                hardwareHasFans: refinedHasFans,
                fanSensorAvailable: meta.isDirect
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.loadRequestID == loadID, !self.isClosed else { return }
                self.snapshot = enriched
                self.snapshotVersion &+= 1
                self.deviceFormFactor = refinedFormFactor
                self.isHardwareLoading = false
                if self.selectedRange == latestRange {
                    // 取消任何基于旧快照在途的聚合任务并使旧 ID 失效，避免随后回写覆盖硬件补全模型
                    self.aggregateTask?.cancel()
                    self.aggregateTask = nil
                    self.aggregateRequestID = UUID()
                    self.isAggregating = false
                    self.rangeModel = enrichedModel
                    self.resolveFocusedEvent(in: enrichedModel)
                } else {
                    self.recomputeActiveRange()
                }
            }
        }
    }

    /// 当前提交范围的导出上下文：标签与右开区间。
    ///
    /// 供打印与多格式导出使用，保证离线文件携带用户正在查看的时间段。
    func committedExportRange() -> (label: String, from: Date, to: Date)? {
        guard !isLoading, !isAggregating, !loadFailed, let model = rangeModel else { return nil }
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
        let exists = model.apps.highLoadAlerts.contains { group in
            group.episodes.contains { $0.id == focusedEventID }
        }
        focusedEventIsMissing = !exists
    }

    /// 切换时间范围并重新计算聚合模型。
    func selectRange(_ range: ReportTimeRange) {
        guard selectedRange != range || rangeModel == nil else { return }
        selectedRange = range
        focusedTimeWindow = nil
        if isLoading {
            reload()
        } else {
            recomputeActiveRange()
        }
    }

    /// 应用自定义时间范围
    func applyCustomRange(from: Date, to: Date) {
        selectedRange = .custom(from: from, to: to)
        focusedTimeWindow = nil
        if isLoading {
            reload()
        } else {
            recomputeActiveRange()
        }
    }

    /// 按当前选定跨度前后步进（-1 上一周期，+1 下一周期，上限不超过今天）。
    func stepRange(by direction: Int) {
        let calendar = Calendar.current
        let now = snapshot?.capturedAt ?? Date()
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86400)
        let currentBounds = selectedRange.bounds(now: now, calendar: calendar)
        let currentStart = calendar.startOfDay(for: currentBounds.from)

        let spanDays: Int = switch selectedRange {
        case .today: 1
        case .week: 7
        case .month: 30
        case .year: 365
        case .custom(let from, let to):
            max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 1)
        }

        let offset = direction * spanDays
        guard let newFrom = calendar.date(byAdding: .day, value: offset, to: currentStart),
              let rawNewTo = calendar.date(byAdding: .day, value: spanDays, to: newFrom) else { return }

        if newFrom > todayStart { return }
        let clampedTo = min(rawNewTo, tomorrowStart)
        if clampedTo == tomorrowStart,
           let expectedTodayStart = calendar.date(byAdding: .day, value: -(spanDays - 1), to: todayStart),
           newFrom == expectedTodayStart {
            switch spanDays {
            case 1: selectRange(.today); return
            case 7: selectRange(.week); return
            case 30: selectRange(.month); return
            case 365: selectRange(.year); return
            default: break
            }
        }
        applyCustomRange(from: newFrom, to: clampedTo)
    }

    var canStepForward: Bool {
        let calendar = Calendar.current
        let now = snapshot?.capturedAt ?? Date()
        let todayStart = calendar.startOfDay(for: now)
        let bounds = selectedRange.bounds(now: now, calendar: calendar)
        let inclusiveEnd = calendar.startOfDay(for: bounds.to.addingTimeInterval(-1))
        return inclusiveEnd < todayStart
    }

    // MARK: - 跨模块联动导航

    func focusOnEvent(_ event: ReportEventItem) {
        focusedTimeWindow = ReportFocusedTimeWindow(
            start: event.start,
            end: event.end,
            title: "\(event.kind.title) · \(StatisticsDisplayFormat.duration(event.pressureSeconds))",
            kind: event.kind
        )
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedModule = event.kind == .memory ? .memory : .thermal
        }
    }

    func focusOnInsight(_ insight: ReportInsightItem) {
        if let start = insight.focusStart, let end = insight.focusEnd {
            let kind: ReportEventItem.Kind? = switch insight.destination {
            case .memory: .memory
            case .thermal: .thermal
            default: nil
            }
            focusedTimeWindow = ReportFocusedTimeWindow(
                start: start,
                end: end,
                title: insight.title,
                kind: kind
            )
        } else {
            focusedTimeWindow = nil
        }
        if let dest = insight.destination {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedModule = dest
            }
        }
    }

    func openEvents(filter: ReportEventFilterKind = .all) {
        eventFilterKind = filter
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedModule = .events
        }
    }

    func openAppAlerts() {
        scrollToAppAlertsToken = UUID()
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedModule = .apps
        }
    }

    func clearFocusedTimeWindow() {
        focusedTimeWindow = nil
    }

    private func recomputeActiveRange() {
        guard let snapshot, !isClosed else { return }
        isAggregating = true
        let aggID = UUID()
        let expectedVersion = self.snapshotVersion
        self.aggregateRequestID = aggID
        let range = selectedRange

        let hasBattery = Self.checkHardwareBattery()
        let hasFans = ReportEnvironment.hasPhysicalFans(model: snapshot.meta.modelName, hardware: snapshot.hardware)
        let isDirect = snapshot.meta.isDirect

        aggregateTask?.cancel()
        aggregateTask = Task.detached(priority: .userInitiated) { [weak self] in
            let model = ReportDataAggregator.aggregate(
                snapshot: snapshot,
                range: range,
                now: snapshot.capturedAt,
                hardwareHasBattery: hasBattery,
                hardwareHasFans: hasFans,
                fanSensorAvailable: isDirect
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.aggregateRequestID == aggID,
                      self.snapshotVersion == expectedVersion,
                      !self.isClosed else {
                    return
                }
                self.rangeModel = model
                self.isAggregating = false
                self.resolveFocusedEvent(in: model)
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

    /// 收集当前快照中存在有效采样行的自然日键集合，供自定义日历绘制有数标记。
    nonisolated private static func computeRecordedDayKeys(from snapshot: ReportSnapshot, calendar: Calendar = .current) -> Set<Int64> {
        var keys = Set<Int64>()
        for row in snapshot.days where row.n > 0 {
            keys.insert(StatisticsProcessStore.dayKey(Date(timeIntervalSince1970: TimeInterval(row.t)), calendar: calendar))
        }
        for row in snapshot.hours where row.n > 0 {
            keys.insert(StatisticsProcessStore.dayKey(Date(timeIntervalSince1970: TimeInterval(row.t)), calendar: calendar))
        }
        for row in snapshot.minutes where row.n > 0 {
            keys.insert(StatisticsProcessStore.dayKey(Date(timeIntervalSince1970: TimeInterval(row.t)), calendar: calendar))
        }
        return keys
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
