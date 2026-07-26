import Foundation
import SwiftUI
import Combine
import OSLog

enum HaloRingSource: String, CaseIterable, Identifiable {
    case combined
    case cpu
    case gpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: String(localized: "ring-source.combined")
        case .cpu: String(localized: "ring-source.cpu")
        case .gpu: String(localized: "ring-source.gpu")
        case .memory: String(localized: "ring-source.memory")
        }
    }
}

enum MemoryPressureLevel: Int, Equatable {
    case normal = 0
    case warning = 1
    case critical = 2
    case unknown = 3
}

enum MonitorSeverity {
    case calm
    case warning
    case critical

    var title: String {
        switch self {
        case .calm:
            String(localized: "severity.calm")
        case .warning:
            String(localized: "severity.warning")
        case .critical:
            String(localized: "severity.critical")
        }
    }
}

enum MonitorKind: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case memory
    case storage
    case network
    case battery

    var id: String { rawValue }

    /// 用户可见的模块
    static let userVisibleCases: [MonitorKind] = allCases

    var title: String {
        switch self {
        case .cpu:
            String(localized: "kind.cpu")
        case .gpu:
            String(localized: "kind.gpu")
        case .memory:
            String(localized: "kind.memory")
        case .storage:
            String(localized: "kind.storage")
        case .network:
            String(localized: "kind.network")
        case .battery:
            String(localized: "kind.battery")
        }
    }

    var symbol: String {
        switch self {
        case .cpu:
            "cpu"
        case .gpu:
            "display"
        case .memory:
            "memorychip"
        case .storage:
            "internaldrive"
        case .network:
            "network"
        case .battery:
            "powerplug"
        }
    }

    var availableMetrics: [MetricSwitch] {
        switch self {
        case .cpu:
            return [
                MetricSwitch(id: "system", title: String(localized: "metric.cpu.system"), isDefault: true),
                MetricSwitch(id: "user", title: String(localized: "metric.cpu.user"), isDefault: true),
                MetricSwitch(id: "idle", title: String(localized: "metric.cpu.idle"), isDefault: true),
                MetricSwitch(id: "uptime", title: String(localized: "metric.cpu.uptime"), isDefault: true),
                MetricSwitch(id: "temperature", title: String(localized: "metric.cpu.temperature"), isDefault: false),
            ]
        case .gpu:
            return [
                MetricSwitch(id: "gpu-memory", title: String(localized: "metric.gpu.gpu-memory"), isDefault: true),
                MetricSwitch(id: "allocated", title: String(localized: "metric.gpu.allocated"), isDefault: true),
                MetricSwitch(id: "render", title: String(localized: "metric.gpu.render"), isDefault: true),
                MetricSwitch(id: "tiler", title: String(localized: "metric.gpu.tiler"), isDefault: true),
            ]
        case .memory:
            return [
                MetricSwitch(id: "used", title: String(localized: "metric.memory.used"), isDefault: true),
                MetricSwitch(id: "pressure", title: String(localized: "metric.memory.pressure"), isDefault: true),
                MetricSwitch(id: "swap-used", title: String(localized: "metric.memory.swap-used"), isDefault: true),
                MetricSwitch(id: "total", title: String(localized: "metric.memory.total"), isDefault: true),
            ]
        case .storage:
            return [
                MetricSwitch(id: "used", title: String(localized: "metric.storage.used"), isDefault: true),
                MetricSwitch(id: "free", title: String(localized: "metric.storage.free"), isDefault: true),
                MetricSwitch(id: "total", title: String(localized: "metric.storage.total"), isDefault: true),
            ]
        case .network:
            return [
                MetricSwitch(id: "ipv4", title: String(localized: "metric.network.ipv4"), isDefault: true),
                MetricSwitch(id: "ipv6", title: String(localized: "metric.network.ipv6"), isDefault: true),
                MetricSwitch(id: "public-ip", title: String(localized: "metric.network.public-ip"), isDefault: true),
            ]
        case .battery:
            return [
                MetricSwitch(id: "charging-power", title: String(localized: "metric.battery.charging-power"), isDefault: true),
                MetricSwitch(id: "health", title: String(localized: "metric.battery.health"), isDefault: true),
                MetricSwitch(id: "cycle-count", title: String(localized: "metric.battery.cycle-count"), isDefault: true),
                MetricSwitch(id: "temperature", title: String(localized: "metric.battery.temperature"), isDefault: true),
            ]
        }
    }
}

struct MetricSwitch: Identifiable, Hashable {
    let id: String
    let title: String
    let isDefault: Bool
}

/// 面板来源类型,用于引用计数式可见性判定。
enum PanelKind: Hashable {
    case menuBar
    case pinned
}

struct MonitorMetric: Identifiable, Equatable {
    let name: String
    let value: String
    var numericValue: Double?

    var id: String { name }
}

struct MonitorModule: Identifiable, Equatable {
    let kind: MonitorKind
    var context: String? = nil
    var value: Double
    var summary: String
    var metrics: [MonitorMetric]
    var samples: [Double]
    var pressure: MemoryPressureLevel? = nil
    /// 连续内存压力百分比(0-100,口径同活动监视器压力图),仅内存模块有值。
    var pressureValue: Double? = nil
    /// 压力百分比历史序列,与 samples 同法滚动积累,供压力模式下的迷你曲线使用。
    var pressureSamples: [Double] = []

    var id: MonitorKind { kind }

    var severity: MonitorSeverity {
        switch kind {
        case .cpu, .gpu, .memory, .storage:
            if value >= MonitorConstants.criticalThreshold { return .critical }
            if value >= MonitorConstants.warningThreshold { return .warning }
            return .calm
        case .network:
            if value >= MonitorConstants.networkWarningThreshold { return .warning }
            return .calm
        case .battery:
            if metrics.first(where: { $0.name == "type" })?.value == "ac-power" {
                return .calm
            }
            if value <= MonitorConstants.batteryCriticalThreshold { return .critical }
            if value <= MonitorConstants.batteryWarningThreshold { return .warning }
            return .calm
        }
    }

    nonisolated static func placeholder(kind: MonitorKind) -> MonitorModule {
        MonitorModule(
            kind: kind,
            context: nil,
            value: 0,
            summary: "--",
            metrics: [
                MonitorMetric(name: "current", value: "--"),
                MonitorMetric(name: "average", value: "--"),
                MonitorMetric(name: "peak", value: "--")
            ],
            samples: Array(repeating: 0, count: 28)
        )
    }
}

final class MonitorStore: ObservableObject {
    let settings: MonitorSettings

    @Published private(set) var modules: [MonitorModule]
    @Published var topMemoryProcesses: [TopMemoryProcess] = []
    @Published var topCPUProcesses: [TopCPUProcess] = []
    @Published var topDiskProcesses: [TopDiskProcess] = []
    @Published var topNetworkProcesses: [TopNetworkProcess] = []
    var selectedKind: MonitorKind = .cpu

    /// 菜单栏负载环的 30fps 平滑动画状态,独立发布(而非 MonitorStore 自身的
    /// @Published),避免 MonitorPanelView 等只用 `@ObservedObject` 订阅整个 store、
    /// 却从不读取该值的视图,在负载爬升/回落期间被拖着以 30fps 重算整棵视图树。
    let loadAnimator = MenuBarLoadAnimator()

    /// 面板是否可见,用于按需启停进程采样。
    @Published private(set) var isPanelVisible = false

    /// 可见面板来源集合。任一来源可见时 isPanelVisible 为真,仅当集合为空时为假。
    private var visiblePanelKinds: Set<PanelKind> = []

    /// 一次性展开动画标记。用户展开/收起时置位,仅供窗口层
    /// (FluidPanelController / PinnedPanelController)读取:用户 toggle 后的第一次尺寸上报
    /// 消费该标记、走补间动画;其后由进程数据到达/定时刷新引起的尺寸变化不再置位,
    /// 故瞬时贴合、不与展开动画叠加(避免二次高度跳变与掉帧)。非 @Published:仅内部协调。
    private var pendingExpansionAnimation = false

    /// 各来源面板当前展开的模块集合。进程列表只在对应模块行展开时才渲染,故仅对
    /// 展开的类目采样;面板打开时默认全部折叠,可避免「一开面板就 spawn ps/nettop、
    /// 构建大量进程图标」造成的内存/CPU 峰值。
    private var expandedKindsBySource: [PanelKind: Set<MonitorKind>] = [:]

    private var allModules: [MonitorModule]
    private let refreshSchedule = MonitorRefreshSchedule()
    private var timerCancellable: AnyCancellable?
    private var procSampleTimer: AnyCancellable?
    private let sampler = SystemMonitorSampler()
    private let samplingQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.sampling", qos: .utility)
    private let procSampleQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.proc-sample", qos: .utility)
    private var cancellables: Set<AnyCancellable> = []
    private var isSampling = false
    private var pendingSampleKinds: Set<MonitorKind> = []

    init() {
        let settings = MonitorSettings()
        let initialModules = MonitorKind.allCases.map(MonitorModule.placeholder)
        self.settings = settings
        allModules = initialModules
        modules = initialModules.filter { settings.isVisible($0.kind) }
        advance(kinds: MonitorKind.allCases)
        refreshSchedule.markRefreshed(MonitorKind.allCases, at: Date())
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.modules = self.visibleModules(from: self.allModules)
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        timerCancellable = Timer.publish(every: refreshSchedule.tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advance()
            }

        // 进程采样定时器:面板可见时启动,不可见时暂停。
        // 统一为单个定时器,并行执行 4 类采样,避免多个独立定时器导致的密集触发。
        // init 时不采样,首次采样在 panelDidAppear() 中触发。

        settings.$memoryShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$cpuShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$diskShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)

        settings.$networkShowSystemProcesses
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAllProcessesIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// 面板出现时调用（菜单栏面板便捷封装）。
    func panelDidAppear() {
        panelDidAppear(.menuBar)
    }

    /// 面板消失时调用（菜单栏面板便捷封装）。
    func panelDidDisappear() {
        panelDidDisappear(.menuBar)
    }

    /// 面板出现时调用:记录来源,仅在集合「空→非空」时启动进程采样。
    func panelDidAppear(_ kind: PanelKind) {
        let wasEmpty = visiblePanelKinds.isEmpty
        visiblePanelKinds.insert(kind)
        if wasEmpty {
            isPanelVisible = true
            refreshAllProcesses()
            startProcSampleTimer()
        }
    }

    /// 面板消失时调用:移除来源,仅在集合「非空→空」时停止进程采样。
    func panelDidDisappear(_ kind: PanelKind) {
        visiblePanelKinds.remove(kind)
        expandedKindsBySource[kind] = nil
        if visiblePanelKinds.isEmpty {
            isPanelVisible = false
            stopProcSampleTimer()
        }
    }

    /// 所有可见面板展开模块的并集。进程采样只覆盖这个集合。
    private var expandedProcessKinds: Set<MonitorKind> {
        expandedKindsBySource.values.reduce(into: Set<MonitorKind>()) { $0.formUnion($1) }
    }

    /// 由 SwiftUI 侧在 `withAnimation` 展开/收起时调用,置位一次性动画标记。
    func beginExpansionAnimation() {
        pendingExpansionAnimation = true
    }

    /// 由窗口层在处理内容尺寸变化时调用:返回并清除标记。true 表示本次变化源自用户
    /// toggle、应走补间;false 表示数据驱动的尺寸变化、应瞬时贴合。
    func consumeExpansionAnimationFlag() -> Bool {
        defer { pendingExpansionAnimation = false }
        return pendingExpansionAnimation
    }

    /// 面板上报其当前展开的模块集合。新增展开项会立即触发一次针对性采样,保证
    /// 「展开即见数据」;集合收缩时对应类目自然停采(下一轮定时器不再覆盖它)。
    func updateExpandedKinds(_ kinds: Set<MonitorKind>, for source: PanelKind) {
        let previous = expandedProcessKinds
        expandedKindsBySource[source] = kinds
        let newlyExpanded = expandedProcessKinds.subtracting(previous)
        guard isPanelVisible, !newlyExpanded.isEmpty else { return }
        refreshProcesses(for: newlyExpanded) { [weak self] in
            guard let self else { return }
            // 网络:首采的 nettop 仅建立基线(因无前一快照,增量为空),完成后立即
            // 链式再采一次即可算出增量,避免干等下一个 5s 定时。不用固定延时是
            // 因为 nettop 单次耗时 1-2s 不确定,按完成回调链式接力最稳。
            guard newlyExpanded.contains(.network),
                  self.isPanelVisible,
                  self.expandedProcessKinds.contains(.network),
                  self.topNetworkProcesses.isEmpty else { return }
            self.refreshProcesses(for: [.network])
        }
        // 磁盘读写量是两次快照的增量:首采只建基线、常返空。磁盘采样本身极快,故用
        // 0.6s 定时补采(需一个测量窗口),把磁盘 TOP 从「干等 5s 定时」缩短到 ~0.6s 出数。
        if newlyExpanded.contains(.storage) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.isPanelVisible, self.expandedProcessKinds.contains(.storage) else { return }
                self.refreshProcesses(for: [.storage])
            }
        }
    }

    /// 当前设置里已开启进程列表的类目集合。
    private func enabledProcessKinds() -> Set<MonitorKind> {
        var enabled = Set<MonitorKind>()
        if settings.showMemoryProcesses { enabled.insert(.memory) }
        if settings.showCPUProcesses { enabled.insert(.cpu) }
        if settings.showDiskProcesses { enabled.insert(.storage) }
        if settings.showNetworkProcesses { enabled.insert(.network) }
        return enabled
    }

    /// 计算实际需要采样的进程类目:展开集合与「设置里开启的进程列表」集合的交集。
    /// 纯函数,便于单测。
    static func activeProcessKinds(expanded: Set<MonitorKind>, enabled: Set<MonitorKind>) -> Set<MonitorKind> {
        expanded.intersection(enabled)
    }

    /// 启动进程采样定时器(5 秒间隔)。
    private func startProcSampleTimer() {
        guard procSampleTimer == nil else { return }
        procSampleTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAllProcesses()
            }
    }

    /// 暂停进程采样定时器。
    private func stopProcSampleTimer() {
        procSampleTimer?.cancel()
        procSampleTimer = nil
    }

    /// 刷新当前展开且开启的进程列表。由 5 秒定时器驱动;未展开任何模块时为空转。
    private func refreshAllProcesses() {
        refreshProcesses(for: expandedProcessKinds)
    }

    /// 对指定类目采样(仅限其中设置已开启的列表)。并行执行,全部完成后回主线程
    /// 更新 @Published 属性。只采「展开 ∩ 设置开启」的类目,避免为不可见的列表
    /// spawn ps/nettop 子进程、构建图标。
    private func refreshProcesses(for kinds: Set<MonitorKind>, completion: (() -> Void)? = nil) {
        let enabled = enabledProcessKinds()

        let active = Self.activeProcessKinds(expanded: kinds, enabled: enabled)
        guard !active.isEmpty else {
            completion?()
            return
        }

        let memoryIncludeSystem = settings.memoryShowSystemProcesses
        let cpuIncludeSystem = settings.cpuShowSystemProcesses
        let diskIncludeSystem = settings.diskShowSystemProcesses
        let networkIncludeSystem = settings.networkShowSystemProcesses

        let group = DispatchGroup()
        var memoryProcesses: [TopMemoryProcess]?
        var cpuProcesses: [TopCPUProcess]?
        var diskProcesses: [TopDiskProcess]?
        var networkProcesses: [TopNetworkProcess]?

        // 并行执行各类采样,各自独立互不阻塞;只采样当前可见(展开)且已开启的列表。
        if active.contains(.memory) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopMemoryProcesses(includeSystemProcesses: memoryIncludeSystem)
                // enrich 使用 NSRunningApplication(pid:) 初始化,只读属性,后台线程安全。
                memoryProcesses = enrich(raw)
                group.leave()
            }
        }

        if active.contains(.cpu) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopCPUProcesses(includeSystemProcesses: cpuIncludeSystem)
                cpuProcesses = enrichCPU(raw)
                group.leave()
            }
        }

        if active.contains(.storage) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopDiskProcesses(includeSystemProcesses: diskIncludeSystem)
                diskProcesses = enrichDisk(raw)
                group.leave()
            }
        }

        if active.contains(.network) {
            group.enter()
            procSampleQueue.async {
                let raw = sampleTopNetworkProcesses(includeSystemProcesses: networkIncludeSystem)
                networkProcesses = enrichNetwork(raw)
                group.leave()
            }
        }

        // 全部采样完成后,在主线程更新 @Published 属性。
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let m = memoryProcesses { self.topMemoryProcesses = m }
            if let c = cpuProcesses { self.topCPUProcesses = c }
            if let d = diskProcesses { self.topDiskProcesses = d }
            if let n = networkProcesses { self.topNetworkProcesses = n }
            completion?()
        }
    }

    /// 设置变化时刷新(仅面板可见时)。
    private func refreshAllProcessesIfNeeded() {
        guard isPanelVisible else { return }
        refreshAllProcesses()
    }

    deinit {
        timerCancellable?.cancel()
        procSampleTimer?.cancel()
        cancellables.removeAll()
    }

    var selectedModule: MonitorModule {
        allModules.first { $0.kind == selectedKind }
            ?? allModules.first
            ?? MonitorModule.placeholder(kind: selectedKind)
    }

    var combinedComputeLoad: Double {
        let cpuValue = allModules.first { $0.kind == .cpu }?.value ?? 0
        let gpuValue = allModules.first { $0.kind == .gpu }?.value ?? 0
        let memoryPressure = allModules.first { $0.kind == .memory }?.pressure ?? .unknown
        return ComputeLoadModel.combined(
            cpuValue: cpuValue,
            gpuValue: gpuValue,
            memoryPressure: memoryPressure
        )
    }

    var haloRingLoadLevel: MenuBarComputeLoadLevel {
        ComputeLoadModel.loadLevel(for: combinedComputeLoad)
    }

    var menuBarMetricItems: [MenuBarMetricItem] {
        settings.menuBarMetricKinds.map { kind in
            MenuBarMetricItem(kind: kind, value: menuBarMetricValue(for: kind))
        }
    }

    func previewMenuBarMetricItems() -> [MenuBarMetricItem] {
        settings.menuBarMetricKinds.map { kind in
            MenuBarMetricItem(kind: kind, value: previewMenuBarMetricValue(for: kind))
        }
    }

    private func menuBarMetricValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.cpu))
        case .gpuUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.gpu))
        case .memoryUsage:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.memory))
        case .memoryPressure:
            // 连续压力百分比,口径同面板压力曲线(活动监视器压力图)。
            return MenuBarMetricFormatter.fixedPercentage(allModules.first { $0.kind == .memory }?.pressureValue)
        case .batteryLevel:
            return MenuBarMetricFormatter.fixedPercentage(moduleValue(.battery))
        case .networkDownload:
            return MenuBarMetricFormatter.throughput(metricValue("download", in: .network), direction: "↓")
        case .networkUpload:
            return MenuBarMetricFormatter.throughput(metricValue("upload", in: .network), direction: "↑")
        case .cpuTemperature:
            return MenuBarMetricFormatter.temperature(metricValue("temperature", in: .cpu))
        case .storageFree:
            return MenuBarMetricFormatter.capacity(metricValue("free", in: .storage))
        case .systemPower:
            return MenuBarMetricFormatter.power(metricValue("power", in: .battery))
        }
    }

    private func previewMenuBarMetricValue(for kind: MenuBarMetricKind) -> String {
        switch kind {
        case .cpuUsage:
            "35%"
        case .gpuUsage:
            "34%"
        case .memoryUsage:
            "61%"
        case .memoryPressure:
            "23%"
        case .batteryLevel:
            "76%"
        case .networkDownload:
            "↓2.4M"
        case .networkUpload:
            "↑320K"
        case .cpuTemperature:
            " 88°"
        case .storageFree:
            "128G"
        case .systemPower:
            " 12W"
        }
    }

    private func moduleValue(_ kind: MonitorKind) -> Double? {
        allModules.first { $0.kind == kind }?.value
    }

    private func metricValue(_ name: String, in kind: MonitorKind) -> Double? {
        allModules.first { $0.kind == kind }?.metrics.first { $0.name == name }?.numericValue
    }

    private func advance() {
        let kinds = refreshSchedule.dueKinds(at: Date())
        guard !kinds.isEmpty else {
            return
        }
        advance(kinds: kinds)
    }

    private func advance(kinds: some Sequence<MonitorKind>) {
        let requestedKinds = Set(kinds)
        guard !requestedKinds.isEmpty else {
            return
        }

        if isSampling {
            pendingSampleKinds.formUnion(requestedKinds)
            return
        }

        isSampling = true
        runSampling(kinds: requestedKinds)
    }

    private func runSampling(kinds: Set<MonitorKind>) {
        let previousModules = allModules
        sampler.sampleAsync(kinds: kinds, previousModules: previousModules, on: samplingQueue) { [weak self] result in
            guard let self else { return }
            self.applySamplingResult(result)
        }
    }

    private func applySamplingResult(_ result: Result<SystemMonitorSnapshot, SamplingError>) {
        switch result {
        case .success(let snapshot):
            // 采样值未变时跳过重新赋值:避免空转触发 @Published,拖动
            // MonitorPanelView 等 @ObservedObject 订阅方做无意义的重算。
            if allModules != snapshot.modules {
                allModules = snapshot.modules
            }
            let newVisibleModules = visibleModules(from: allModules)
            if modules != newVisibleModules {
                modules = newVisibleModules
            }
            updateMenuBarTargetComputeLoad()

        case .failure(let error):
            let message = "Sampling failed: \(error.description)"
            AppLogger.sampler.error("\(message, privacy: .public)")
            AppLogStore.shared.error(message, category: "sampler")
        }

        if pendingSampleKinds.isEmpty {
            isSampling = false
        } else {
            let kinds = pendingSampleKinds
            pendingSampleKinds.removeAll()
            runSampling(kinds: kinds)
        }
    }



    private func updateMenuBarTargetComputeLoad() {
        loadAnimator.updateTarget(combinedComputeLoad)
    }

    private func visibleModules(from modules: [MonitorModule]) -> [MonitorModule] {
        modules.filter { settings.isVisible($0.kind) }
    }
}

/// 菜单栏负载环的 30fps 平滑动画状态。从 MonitorStore 拆出独立发布,详见
/// `MonitorStore.loadAnimator` 处的说明。
final class MenuBarLoadAnimator: ObservableObject {
    @Published private(set) var displayedComputeLoad = 0.0

    private var targetComputeLoad = 0.0
    private var smoothingTimerCancellable: AnyCancellable?

    func updateTarget(_ target: Double) {
        guard ComputeLoadModel.shouldUpdateMenuBarTarget(
            currentTarget: targetComputeLoad,
            nextTarget: target
        ) else {
            return
        }
        targetComputeLoad = target
        ensureSmoothingTimer()
    }

    private func advanceSmoothing() {
        let next = ComputeLoadModel.smoothedDisplayValue(
            current: displayedComputeLoad,
            target: targetComputeLoad
        )
        let quantized = Self.quantizeLoad(next)
        if quantized != displayedComputeLoad {
            displayedComputeLoad = quantized
        }
        let quantizedTarget = Self.quantizeLoad(targetComputeLoad)
        if abs(displayedComputeLoad - quantizedTarget) <= MonitorConstants.menuBarLoadSmoothStopThreshold {
            if displayedComputeLoad != quantizedTarget {
                displayedComputeLoad = quantizedTarget
            }
            smoothingTimerCancellable?.cancel()
            smoothingTimerCancellable = nil
        }
    }

    private static func quantizeLoad(_ load: Double) -> Double {
        min(100.0, max(0.0, load)).rounded()
    }

    private func ensureSmoothingTimer() {
        guard smoothingTimerCancellable == nil else { return }
        smoothingTimerCancellable = Timer.publish(every: MonitorConstants.menuBarLoadSmoothFrameInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceSmoothing()
            }
    }

    deinit {
        smoothingTimerCancellable?.cancel()
    }
}

enum ComputeLoadModel {
    static func combined(
        cpuValue: Double,
        gpuValue: Double,
        memoryPressure: MemoryPressureLevel = .normal,
        sharpness: Double = MonitorConstants.computeLoadSoftmaxSharpness
    ) -> Double {
        let cpu = min(100, max(0, cpuValue))
        let gpu = min(100, max(0, gpuValue))
        let memory = memoryPressureScore(memoryPressure)
        return softmaxAggregate([cpu, gpu, memory], sharpness: sharpness)
    }

    /// 归一化 LSE（softmax mean）：结果严格落在 [mean, max] 之间。
    /// sharpness(k)→0 趋近均值，→∞ 趋近最大值；体现「多个子系统同时吃紧 = 整体更糟」。
    /// 减去 max 做指数平移以避免溢出。
    static func softmaxAggregate(_ values: [Double], sharpness k: Double) -> Double {
        guard let maxValue = values.max(), !values.isEmpty else {
            return 0
        }
        guard k > 0 else {
            return values.reduce(0, +) / Double(values.count)
        }
        let expSum = values.reduce(0.0) { $0 + exp(k * ($1 - maxValue)) }
        return maxValue + log(expSum / Double(values.count)) / k
    }

    static func memoryPressureScore(_ pressure: MemoryPressureLevel) -> Double {
        switch pressure {
        case .normal:
            return 0
        case .warning:
            return 50
        case .critical:
            return 85
        case .unknown:
            return 0
        }
    }

    static func loadLevel(for load: Double) -> MenuBarComputeLoadLevel {
        // 阈值按 softmax 聚合(k=0.08)的值分布校准：单瓶颈天花板≈86，
        // 故 stressed 下探到 78 以让「单子系统近满/双高/内存critical」触红。
        switch load {
        case ..<25: return .idle
        case ..<50: return .working
        case ..<78: return .busy
        default: return .stressed
        }
    }

    static func smoothedDisplayValue(
        current: Double,
        target: Double,
        factor: Double = MonitorConstants.menuBarLoadSmoothFactor,
        minStep: Double = MonitorConstants.menuBarLoadSmoothMinStep
    ) -> Double {
        let clampedCurrent = min(100, max(0, current))
        let clampedTarget = min(100, max(0, target))
        let delta = clampedTarget - clampedCurrent
        let distance = abs(delta)

        if distance <= minStep {
            return clampedTarget
        }

        // ease-out: proportional step, fast start, slow finish.
        let step = max(minStep, distance * factor)
        return clampedCurrent + (delta > 0 ? step : -step)
    }

    static func shouldUpdateMenuBarTarget(
        currentTarget: Double,
        nextTarget: Double,
        threshold: Double = MonitorConstants.menuBarLoadChangeThreshold
    ) -> Bool {
        abs(min(100, max(0, nextTarget)) - min(100, max(0, currentTarget))) >= threshold
    }
}

final class MonitorRefreshSchedule {
    let tickInterval: TimeInterval

    private let intervals: [MonitorKind: TimeInterval]
    private var lastRefreshDates: [MonitorKind: Date] = [:]

    init(
        tickInterval: TimeInterval = 1,
        intervals: [MonitorKind: TimeInterval] = [
            .cpu: 1, .gpu: 2, .memory: 3,
            .storage: 10, .network: 1, .battery: 2
        ]
    ) {
        self.tickInterval = tickInterval
        self.intervals = intervals
    }

    func dueKinds(at date: Date) -> [MonitorKind] {
        let dueKinds = MonitorKind.allCases.filter { kind in
            let interval = intervals[kind] ?? tickInterval
            guard let lastRefreshDate = lastRefreshDates[kind] else {
                return true
            }

            return date.timeIntervalSince(lastRefreshDate) >= interval
        }
        markRefreshed(dueKinds, at: date)
        return dueKinds
    }

    func markRefreshed(_ kinds: some Sequence<MonitorKind>, at date: Date) {
        for kind in kinds {
            lastRefreshDates[kind] = date
        }
    }
}
