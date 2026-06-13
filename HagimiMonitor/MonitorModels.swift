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
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: String(localized: "ring-source.memory")
        }
    }
}

enum MemoryPressureLevel {
    case normal
    case warning
    case critical
    case unknown
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
        }
    }
}

struct MetricSwitch: Identifiable, Hashable {
    let id: String
    let title: String
    let isDefault: Bool
}

struct MonitorMetric: Identifiable {
    let name: String
    let value: String

    var id: String { name }
}

struct MonitorModule: Identifiable {
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
    var selectedKind: MonitorKind = .cpu
    @Published private(set) var displayedComputeLoad = 0.0

    private var allModules: [MonitorModule]
    private let refreshSchedule = MonitorRefreshSchedule()
    private var timerCancellable: AnyCancellable?
    private var smoothingTimerCancellable: AnyCancellable?
    private let sampler = SystemMonitorSampler()
    private let samplingQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.sampling", qos: .utility)
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
    }

    deinit {
        timerCancellable?.cancel()
        smoothingTimerCancellable?.cancel()
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
        case .failure(let error):
            AppLogger.sampler.error("Sampling failed: \(error.description, privacy: .public)")
        }

        if pendingSampleKinds.isEmpty {
            isSampling = false
        } else {
            let kinds = pendingSampleKinds
            pendingSampleKinds.removeAll()
            runSampling(kinds: kinds)
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
        let clamped = min(100.0, max(0.0, load))
        return (clamped / 2.0).rounded() * 2.0
    }

    private func ensureSmoothingTimer() {
        guard smoothingTimerCancellable == nil else { return }
        smoothingTimerCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
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
        memoryPressure: MemoryPressureLevel = .normal
    ) -> Double {
        let cpu = min(100, max(0, cpuValue))
        let gpu = min(100, max(0, gpuValue))
        let memory = memoryPressureScore(memoryPressure)
        return cpu * 0.4 + gpu * 0.4 + memory * 0.2
    }

    static func memoryPressureScore(_ pressure: MemoryPressureLevel) -> Double {
        switch pressure {
        case .normal:
            return 0
        case .warning:
            return 70
        case .critical:
            return 100
        case .unknown:
            return 0
        }
    }

    static func loadLevel(for load: Double) -> MenuBarComputeLoadLevel {
        switch load {
        case ..<35: return .idle
        case ..<65: return .working
        case ..<85: return .busy
        default: return .stressed
        }
    }

    static func smoothedDisplayValue(
        current: Double,
        target: Double,
        maxStep: Double = MonitorConstants.menuBarLoadSmoothStep
    ) -> Double {
        let clampedCurrent = min(100, max(0, current))
        let clampedTarget = min(100, max(0, target))
        let delta = clampedTarget - clampedCurrent

        if abs(delta) <= maxStep {
            return clampedTarget
        }

        return clampedCurrent + (delta > 0 ? maxStep : -maxStep)
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
            .storage: 10, .network: 1, .battery: 5
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
