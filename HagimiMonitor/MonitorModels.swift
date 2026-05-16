import Foundation
import SwiftUI
import Combine

enum MonitorSeverity {
    case calm
    case warning
    case critical

    var title: String {
        switch self {
        case .calm:
            "正常"
        case .warning:
            "接近阈值"
        case .critical:
            "需要注意"
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
            "CPU"
        case .gpu:
            "GPU"
        case .memory:
            "内存"
        case .storage:
            "存储"
        case .network:
            "网络"
        case .battery:
            "电源"
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
            if value >= 88 { return .critical }
            if value >= 72 { return .warning }
            return .calm
        case .network:
            if value >= 85 { return .warning }
            return .calm
        case .battery:
            if metrics.first(where: { $0.name == "类型" })?.value == "外接电源" {
                return .calm
            }
            if value <= 12 { return .critical }
            if value <= 25 { return .warning }
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
                MonitorMetric(name: "当前", value: "--"),
                MonitorMetric(name: "平均", value: "--"),
                MonitorMetric(name: "峰值", value: "--")
            ],
            samples: Array(repeating: 0, count: 24)
        )
    }
}

final class MonitorStore: ObservableObject {
    @Published private(set) var modules: [MonitorModule]
    @Published var selectedKind: MonitorKind = .cpu
    @Published private(set) var menuBarFrame = 0

    private let refreshSchedule = MonitorRefreshSchedule()
    private var timer: Timer?
    private var animationTimer: Timer?
    private let sampler = SystemMonitorSampler()

    init() {
        modules = MonitorKind.allCases.map(MonitorModule.placeholder)
        advance(kinds: MonitorKind.allCases)
        refreshSchedule.markRefreshed(MonitorKind.allCases, at: Date())
        timer = Timer.scheduledTimer(withTimeInterval: refreshSchedule.tickInterval, repeats: true) { [weak self] _ in
            self?.advance()
        }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.advanceAnimation()
        }
    }

    deinit {
        timer?.invalidate()
        animationTimer?.invalidate()
    }

    var selectedModule: MonitorModule {
        modules.first { $0.kind == selectedKind }
            ?? modules.first
            ?? MonitorModule.placeholder(kind: selectedKind)
    }

    var catModule: MonitorModule {
        modules.max { catPriority($0) < catPriority($1) }
            ?? MonitorModule.placeholder(kind: .cpu)
    }

    var catLine: String {
        CatDialogueEngine.line(for: catModule, modules: modules)
    }

    private func advance() {
        let kinds = refreshSchedule.dueKinds(at: Date())
        guard !kinds.isEmpty else {
            return
        }
        advance(kinds: kinds)
    }

    private func advance(kinds: some Sequence<MonitorKind>) {
        modules = sampler.sample(kinds: kinds, previousModules: modules).modules
    }

    private func advanceAnimation() {
        let cpuValue = modules.first { $0.kind == .cpu }?.value ?? 0
        let stride = cpuValue >= 75 ? 2 : 1
        if cpuValue >= 8 {
            menuBarFrame = (menuBarFrame + stride) % 5
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
}

private final class MonitorRefreshSchedule {
    let tickInterval: TimeInterval

    private let intervals: [MonitorKind: TimeInterval]
    private var lastRefreshDates: [MonitorKind: Date] = [:]

    init(
        tickInterval: TimeInterval = 2,
        intervals: [MonitorKind: TimeInterval] = Dictionary(
            uniqueKeysWithValues: MonitorKind.allCases.map { ($0, 2) }
        )
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
                return "我在盯着这些数字，今天机器有点忙。"
            }
            return "现在很安静，我可以趴在菜单栏晒太阳。"
        }

        switch module.kind {
        case .cpu:
            return "你在搞什么，我感觉我在飞速运转。"
        case .gpu:
            return "画面那边有点烫，我的尾巴都在冒电光。"
        case .memory:
            return "我的脑袋要被塞满了，先关两个东西吧。"
        case .storage:
            return "我的肚子快塞不下了，嗝。"
        case .network:
            return "网线在狂奔，我的胡须都被风吹歪了。"
        case .battery:
            return "我好饿，需要充电，不然要趴下了。"
        }
    }
}
