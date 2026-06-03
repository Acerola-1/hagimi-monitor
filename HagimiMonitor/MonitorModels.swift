import Foundation
import SwiftUI
import Combine
import OSLog

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

    var tint: Color {
        switch self {
        case .calm:
            Color(red: 0.18, green: 0.55, blue: 0.36)
        case .warning:
            Color(red: 0.86, green: 0.54, blue: 0.12)
        case .critical:
            Color(red: 0.82, green: 0.20, blue: 0.18)
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
            if metrics.first(where: { $0.name == "类型" })?.value == "外接电源" {
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
                MonitorMetric(name: String(localized: "metric.current"), value: "--"),
                MonitorMetric(name: String(localized: "metric.average"), value: "--"),
                MonitorMetric(name: String(localized: "metric.peak"), value: "--")
            ],
            samples: Array(repeating: 0, count: 28)
        )
    }
}

final class MonitorStore: ObservableObject {
    let settings: MonitorSettings

    @Published private(set) var modules: [MonitorModule]
    @Published var selectedKind: MonitorKind = .cpu
    @Published private(set) var menuBarFrame = 0

    private var allModules: [MonitorModule]
    private let refreshSchedule = MonitorRefreshSchedule()
    private var timerCancellable: AnyCancellable?
    private var animationTimerCancellable: AnyCancellable?
    private let sampler = SystemMonitorSampler()
    private var cancellables: Set<AnyCancellable> = []

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
        animationTimerCancellable = Timer.publish(every: MonitorConstants.animationInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceAnimation()
            }
    }

    deinit {
        timerCancellable?.cancel()
        animationTimerCancellable?.cancel()
        cancellables.removeAll()
    }

    var selectedModule: MonitorModule {
        allModules.first { $0.kind == selectedKind }
            ?? allModules.first
            ?? MonitorModule.placeholder(kind: selectedKind)
    }

    var catModule: MonitorModule {
        allModules.max { catPriority($0) < catPriority($1) }
            ?? MonitorModule.placeholder(kind: .cpu)
    }

    var catLine: String {
        CatDialogueEngine.line(for: catModule, modules: allModules)
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
        let result = sampler.sample(kinds: kinds, previousModules: allModules)
        switch result {
        case .success(let snapshot):
            allModules = snapshot.modules
            modules = visibleModules(from: allModules)
        case .failure(let error):
            AppLogger.sampler.error("Sampling failed: \(error.description, privacy: .public)")
        }
    }

    private func advanceAnimation() {
        let cpuValue = allModules.first { $0.kind == .cpu }?.value ?? 0
        let stride = cpuValue >= 75 ? 2 : 1
        if cpuValue >= 8 {
            menuBarFrame = (menuBarFrame + stride) % 5
            AppLogger.ui.debug("Animation frame advanced to \(self.menuBarFrame), stride: \(stride)")
        }
    }

    private func catPriority(_ module: MonitorModule) -> Double {
        let base: Double
        switch module.severity {
        case .calm:
            base = 0
        case .warning:
            base = 100
        case .critical:
            base = 200
        }

        if module.kind == .battery {
            return base + (100 - module.value)
        }
        return base + module.value
    }

    private func visibleModules(from modules: [MonitorModule]) -> [MonitorModule] {
        modules.filter { settings.isVisible($0.kind) }
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

enum CatDialogueEngine {
    static func line(for module: MonitorModule, modules: [MonitorModule]) -> String {
        guard module.severity != .calm else {
            let average = modules.isEmpty ? 0 : modules.map(\.value).reduce(0, +) / Double(modules.count)
            if average > 35 {
                return String(localized: "dialogue.calm.busy")
            }
            return String(localized: "dialogue.calm.quiet")
        }

        switch module.kind {
        case .cpu:
            return String(localized: "dialogue.cpu")
        case .gpu:
            return String(localized: "dialogue.gpu")
        case .memory:
            return String(localized: "dialogue.memory")
        case .storage:
            return String(localized: "dialogue.storage")
        case .network:
            return String(localized: "dialogue.network")
        case .battery:
            return String(localized: "dialogue.battery")
        }
    }
}
