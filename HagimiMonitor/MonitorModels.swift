import Foundation
import SwiftUI
import Combine
import OSLog
import SwiftData

enum HaloRingSource: String, CaseIterable, Identifiable {
    case combined
    case cpu
    case gpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: String(localized: "ring-source.combined")
        case .cpu: "CPU"
        case .gpu: "GPU"
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
    case power // 仅用于统计数据采集，不在 UI 中显示为独立模块

    var id: String { rawValue }

    /// 用户可见的模块（排除 .power 等仅用于内部采集的模块）
    static let userVisibleCases: [MonitorKind] = allCases.filter { $0 != .power }

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
        case .power:
            String(localized: "kind.power")
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
        case .power:
            "bolt.fill"
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
                MetricSwitch(id: "ip-address", title: String(localized: "metric.network.ip-address"), isDefault: true),
                MetricSwitch(id: "public-ip", title: String(localized: "metric.network.public-ip"), isDefault: true),
            ]
        case .battery:
            return [
                MetricSwitch(id: "charging-power", title: String(localized: "metric.battery.charging-power"), isDefault: true),
                MetricSwitch(id: "health", title: String(localized: "metric.battery.health"), isDefault: true),
                MetricSwitch(id: "cycle-count", title: String(localized: "metric.battery.cycle-count"), isDefault: true),
                MetricSwitch(id: "temperature", title: String(localized: "metric.battery.temperature"), isDefault: true),
            ]
        case .power:
            return [
                MetricSwitch(id: "power-watts", title: String(localized: "metric.power.watts"), isDefault: true),
            ]
        }
    }
}

struct MetricSwitch: Identifiable, Hashable {
    let id: String
    let title: String
    let isDefault: Bool
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
        case .power:
            if value >= MonitorConstants.criticalThreshold { return .critical }
            if value >= MonitorConstants.warningThreshold { return .warning }
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
    @Published private(set) var displayedComputeLoad = 0.0

    /// 面板是否可见,用于按需启停进程采样。
    @Published private(set) var isPanelVisible = false

    private var allModules: [MonitorModule]
    private let refreshSchedule = MonitorRefreshSchedule()
    private var timerCancellable: AnyCancellable?
    private var smoothingTimerCancellable: AnyCancellable?
    private var procSampleTimer: AnyCancellable?
    private let sampler = SystemMonitorSampler()
    private let statisticsRecorder = StatisticsRecorder()

    // MARK: - Event Detection State

    /// 上一次内存压力等级（用于检测压力等级变化）
    private var previousPressureLevel: MemoryPressureLevel = .unknown
    /// 上一次热压力状态（用于检测热压力变化）
    private var previousThermalState: ProcessInfo.ThermalState = .nominal
    /// CPU 持续高负载开始时间（用于检测 CPU 持续高负载）
    private var cpuHighLoadStartTime: Date?
    /// 上一次电池是否处于过热状态（用于去重：降回正常后才能再次触发）
    private var batteryWasOverheating = false
    /// 上一次电源类型（用于检测电源切换）
    private var previousPowerSourceType: String?
    /// 上一次记录的 CPU 持续高负载结束时间（用于去重）
    private var lastCPUHighLoadEventTime: Date?

    private let cpuHighLoadThreshold: Double = 85.0
    private let cpuHighLoadMinDuration: TimeInterval = 300 // 5 分钟
    private let batteryOverheatThreshold: Double = 40.0 // 40°C

    /// 暴露给统计页，用于读取当前采集窗口尚未落库的内存桶。
    var statisticsPendingSnapshot: [String: PendingBucket] { statisticsRecorder.pendingSnapshot() }

    /// App 退出时将当前未落库的采样桶立即写入 SwiftData，避免丢失。
    func flushStatistics() {
        AppLogStore.shared.info("Flushing statistics before termination", category: "statistics")
        statisticsRecorder.flush()
    }
    private let samplingQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.sampling", qos: .utility)
    private let procSampleQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.proc-sample", qos: .utility)
    private var cancellables: Set<AnyCancellable> = []
    private var menuBarTargetComputeLoad = 0.0
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
                AppLogger.ui.debug("Timer tick triggered")
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

    /// 面板出现时调用:启动进程采样定时器,立即刷新一次。
    func panelDidAppear() {
        isPanelVisible = true
        refreshAllProcesses()
        startProcSampleTimer()
    }

    /// 面板消失时调用:暂停进程采样定时器,保留缓存数据。
    func panelDidDisappear() {
        isPanelVisible = false
        stopProcSampleTimer()
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

    /// 统一刷新所有进程采样:并行执行 4 类采样,避免多个独立定时器导致的密集触发。
    /// 使用 DispatchGroup 并行采样,全部完成后回主线程更新 @Published 属性。
    private func refreshAllProcesses() {
        let memoryIncludeSystem = settings.memoryShowSystemProcesses
        let cpuIncludeSystem = settings.cpuShowSystemProcesses
        let diskIncludeSystem = settings.diskShowSystemProcesses
        let networkIncludeSystem = settings.networkShowSystemProcesses

        let group = DispatchGroup()
        var memoryProcesses: [TopMemoryProcess]?
        var cpuProcesses: [TopCPUProcess]?
        var diskProcesses: [TopDiskProcess]?
        var networkProcesses: [TopNetworkProcess]?

        // 并行执行 4 类采样,各自独立互不阻塞。
        group.enter()
        procSampleQueue.async {
            let raw = sampleTopMemoryProcesses(includeSystemProcesses: memoryIncludeSystem)
            // enrich 使用 NSRunningApplication(pid:) 初始化,只读属性,后台线程安全。
            memoryProcesses = enrich(raw)
            group.leave()
        }

        group.enter()
        procSampleQueue.async {
            let raw = sampleTopCPUProcesses(includeSystemProcesses: cpuIncludeSystem)
            cpuProcesses = enrichCPU(raw)
            group.leave()
        }

        group.enter()
        procSampleQueue.async {
            let raw = sampleTopDiskProcesses(includeSystemProcesses: diskIncludeSystem)
            diskProcesses = enrichDisk(raw)
            group.leave()
        }

        group.enter()
        procSampleQueue.async {
            let raw = sampleTopNetworkProcesses(includeSystemProcesses: networkIncludeSystem)
            networkProcesses = enrichNetwork(raw)
            group.leave()
        }

        // 全部采样完成后,在主线程更新 @Published 属性。
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let m = memoryProcesses { self.topMemoryProcesses = m }
            if let c = cpuProcesses { self.topCPUProcesses = c }
            if let d = diskProcesses { self.topDiskProcesses = d }
            if let n = networkProcesses { self.topNetworkProcesses = n }
        }
    }

    /// 设置变化时刷新(仅面板可见时)。
    private func refreshAllProcessesIfNeeded() {
        guard isPanelVisible else { return }
        refreshAllProcesses()
    }

    deinit {
        timerCancellable?.cancel()
        smoothingTimerCancellable?.cancel()
        procSampleTimer?.cancel()
        cancellables.removeAll()
    }

    var selectedModule: MonitorModule {
        allModules.first { $0.kind == selectedKind }
            ?? allModules.first
            ?? MonitorModule.placeholder(kind: selectedKind)
    }

    var combinedComputeLoad: Double {
        switch settings.ringSource {
        case .combined:
            let cpuValue = allModules.first { $0.kind == .cpu }?.value ?? 0
            let gpuValue = allModules.first { $0.kind == .gpu }?.value ?? 0
            let memoryPressure = allModules.first { $0.kind == .memory }?.pressure ?? .unknown
            return ComputeLoadModel.combined(
                cpuValue: cpuValue,
                gpuValue: gpuValue,
                memoryPressure: memoryPressure
            )
        case .cpu:
            return allModules.first { $0.kind == .cpu }?.value ?? 0
        case .gpu:
            return allModules.first { $0.kind == .gpu }?.value ?? 0
        case .memory:
            return allModules.first { $0.kind == .memory }?.value ?? 0
        }
    }

    var haloRingLoadLevel: MenuBarComputeLoadLevel {
        switch settings.ringSource {
        case .combined, .cpu, .gpu:
            return ComputeLoadModel.loadLevel(for: combinedComputeLoad)
        case .memory:
            let pressure = allModules.first { $0.kind == .memory }?.pressure ?? .unknown
            switch pressure {
            case .normal: return .idle
            case .warning: return .busy
            case .critical: return .stressed
            case .unknown: return .working
            }
        }
    }

    private func advance() {
        let kinds = refreshSchedule.dueKinds(at: Date())
        guard !kinds.isEmpty else {
            return
        }
        let kindNames = kinds.map { $0.rawValue }.joined(separator: ", ")
        AppLogger.ui.debug("Advancing modules: \(kindNames, privacy: .public)")
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
            allModules = snapshot.modules
            modules = visibleModules(from: allModules)
            updateMenuBarTargetComputeLoad()
            statisticsRecorder.record(modules: snapshot.modules)
            detectEvents(modules: snapshot.modules)
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

    // MARK: - Event Detection

    /// 对采样结果进行实时事件检测
    private func detectEvents(modules: [MonitorModule]) {
        for module in modules {
            switch module.kind {
            case .memory:
                checkMemoryPressureChange(module: module)
            case .cpu:
                checkCPUHighLoad(module: module)
            case .battery:
                checkBatteryOverheat(module: module)
                checkPowerSourceChange(module: module)
            default:
                break
            }
        }
        checkThermalStateChange()
    }

    /// 检测内存压力等级变化
    private func checkMemoryPressureChange(module: MonitorModule) {
        guard let currentLevel = module.pressure, currentLevel != .unknown else { return }
        let prev = previousPressureLevel
        guard prev != .unknown, currentLevel != prev else {
            if previousPressureLevel == .unknown { previousPressureLevel = currentLevel }
            return
        }

        let isUpgrade = currentLevel.rawValue > prev.rawValue
        let eventType: SystemEventType = isUpgrade ? .memoryPressureUpgrade : .memoryPressureDowngrade
        let severity: Int16
        switch currentLevel {
        case .critical: severity = 2
        case .warning: severity = 1
        default: severity = 0
        }

        let pressureNames: [MemoryPressureLevel: String] = [
            .normal: String(localized: "event.pressure.normal"),
            .warning: String(localized: "event.pressure.warning"),
            .critical: String(localized: "event.pressure.critical"),
            .unknown: ""
        ]
        let detail = "\(pressureNames[prev] ?? "") → \(pressureNames[currentLevel] ?? "")"

        recordEvent(eventType, severity: severity, title: eventType.title,
                    detail: detail, value: Double(currentLevel.rawValue),
                    previousValue: Double(prev.rawValue))
        previousPressureLevel = currentLevel
    }

    /// 检测热压力状态变化
    private func checkThermalStateChange() {
        let current = ProcessInfo.processInfo.thermalState
        let prev = previousThermalState
        guard current != prev else { return }

        let isUpgrade = current.rawValue > prev.rawValue
        let eventType: SystemEventType = isUpgrade ? .thermalUpgrade : .thermalDowngrade
        let severity: Int16
        switch current {
        case .critical: severity = 2
        case .serious: severity = 1
        default: severity = 0
        }

        let thermalNames: [ProcessInfo.ThermalState: String] = [
            .nominal: String(localized: "event.thermal.nominal"),
            .fair: String(localized: "event.thermal.fair"),
            .serious: String(localized: "event.thermal.serious"),
            .critical: String(localized: "event.thermal.critical")
        ]
        let detail = "\(thermalNames[prev] ?? "") → \(thermalNames[current] ?? "")"

        recordEvent(eventType, severity: severity, title: eventType.title,
                    detail: detail, value: Double(current.rawValue),
                    previousValue: Double(prev.rawValue))
        previousThermalState = current
    }

    /// 检测 CPU 持续高负载（85% 超过 5 分钟）
    private func checkCPUHighLoad(module: MonitorModule) {
        let cpuValue = module.value
        if cpuValue >= cpuHighLoadThreshold {
            if cpuHighLoadStartTime == nil {
                cpuHighLoadStartTime = Date()
            }
            let duration = Date().timeIntervalSince(cpuHighLoadStartTime!)
            if duration >= cpuHighLoadMinDuration {
                // 去重：上次记录后需重新积累
                if let lastTime = lastCPUHighLoadEventTime,
                   Date().timeIntervalSince(lastTime) < cpuHighLoadMinDuration {
                    return
                }
                let topProcess = topCPUProcesses.first?.name
                let detail: String
                if let proc = topProcess {
                    detail = String(localized: "event.cpu-sustained-high") + " (\(proc))"
                } else {
                    detail = String(localized: "event.cpu-sustained-high")
                }
                recordEvent(.cpuSustainedHigh, severity: 1, title: SystemEventType.cpuSustainedHigh.title,
                            detail: detail, value: cpuValue, duration: duration,
                            topProcesses: topProcess.map { [$0] })
                cpuHighLoadStartTime = nil
                lastCPUHighLoadEventTime = Date()
            }
        } else {
            cpuHighLoadStartTime = nil
        }
    }

    /// 检测电池过热（>40°C）
    private func checkBatteryOverheat(module: MonitorModule) {
        guard let tempStr = module.metrics.first(where: { $0.name == "temperature" })?.value,
              let temp = Double(tempStr) else { return }

        let isOverheating = temp > batteryOverheatThreshold
        if isOverheating && !batteryWasOverheating {
            let detail = String(format: "%.1f°C", temp)
            recordEvent(.batteryOverheat, severity: 2, title: SystemEventType.batteryOverheat.title,
                        detail: detail, value: temp)
        }
        batteryWasOverheating = isOverheating
    }

    /// 检测电源切换（AC ↔ 电池）
    private func checkPowerSourceChange(module: MonitorModule) {
        guard let typeMetric = module.metrics.first(where: { $0.name == "type" }) else { return }
        let currentType = typeMetric.value
        if let prev = previousPowerSourceType, prev != currentType {
            let detail: String
            if currentType == "battery" {
                detail = String(localized: "event.power-source-change") + " → Battery"
            } else {
                detail = String(localized: "event.power-source-change") + " → AC"
            }
            recordEvent(.powerSourceChange, severity: 0, title: SystemEventType.powerSourceChange.title,
                        detail: detail)
        }
        previousPowerSourceType = currentType
    }

    // MARK: - Event Recording

    /// 记录系统事件到 SwiftData
    private func recordEvent(_ eventType: SystemEventType, severity: Int16,
                             title: String, detail: String,
                             value: Double? = nil, previousValue: Double? = nil,
                             duration: Double? = nil, topProcesses: [String]? = nil) {
        // 尽力而为获取 top processes
        var processes = topProcesses
        if processes == nil {
            if !topCPUProcesses.isEmpty {
                processes = Array(topCPUProcesses.prefix(3).map(\.name))
            } else if !topMemoryProcesses.isEmpty {
                processes = Array(topMemoryProcesses.prefix(3).map(\.name))
            }
        }

        let topProcessesJSON: String?
        if let procs = processes, !procs.isEmpty {
            if let data = try? JSONEncoder().encode(procs) {
                topProcessesJSON = String(data: data, encoding: .utf8)
            } else {
                topProcessesJSON = nil
            }
        } else {
            topProcessesJSON = nil
        }

        let event = SystemEvent(
            timestamp: Date(),
            eventType: eventType.rawValue,
            severity: severity,
            title: title,
            detail: detail,
            topProcesses: topProcessesJSON,
            value: value,
            previousValue: previousValue,
            duration: duration
        )

        let context = ModelContext(StatisticsStore.container)
        context.insert(event)
        do {
            try context.save()
        } catch {
            AppLogger.sampler.error("Failed to record event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func advanceSmoothing() {
        let next = ComputeLoadModel.smoothedDisplayValue(
            current: displayedComputeLoad,
            target: menuBarTargetComputeLoad
        )
        let quantized = MonitorStore.quantizeLoad(next)
        if quantized != displayedComputeLoad {
            displayedComputeLoad = quantized
        }
        let quantizedTarget = MonitorStore.quantizeLoad(menuBarTargetComputeLoad)
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

    private func updateMenuBarTargetComputeLoad() {
        let currentLoad = combinedComputeLoad
        guard ComputeLoadModel.shouldUpdateMenuBarTarget(
            currentTarget: menuBarTargetComputeLoad,
            nextTarget: currentLoad
        ) else {
            return
        }
        menuBarTargetComputeLoad = currentLoad
        ensureSmoothingTimer()
    }

    private func visibleModules(from modules: [MonitorModule]) -> [MonitorModule] {
        modules.filter { settings.isVisible($0.kind) }
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
            .storage: 10, .network: 1, .battery: 5,
            .power: 2
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
