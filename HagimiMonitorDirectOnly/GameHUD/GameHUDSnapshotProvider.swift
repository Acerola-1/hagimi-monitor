import Foundation
import Combine

/// Game HUD 硬件指标条目的一次读取结果。
///
/// `value` 为 nil 表示本机有该能力但本次采样未产出真实读数:HUD 保留行
/// 并显示 `—`,不填假零值。能力缺失(沙盒渠道无 SMC 温度等)则整个条目
/// 不进目录,与「临时缺值」分开(见 spec:指标目录和数据语义)。
nonisolated struct GameHUDReading: Equatable, Sendable {
    /// Game HUD 目录 ID;映射到主面板采样 ID 的规则在 catalog。
    let metricID: String
    /// 模块归属,用于从快照定位采样来源与着色。
    let kind: MonitorKind
    /// 格式化后的显示文本(已含单位);nil = 本次采样无真实读数,显示 `—`。
    let value: String?
    /// 曲线输入(0~100 百分比口径);无百分比语义的条目为 nil,不画曲线。
    let percent: Double?
}

/// 一次快照内全部已勾选条目的集合。
nonisolated struct GameHUDSnapshot: Equatable, Sendable {
    let readings: [GameHUDReading]
    let date: Date

    static let empty = GameHUDSnapshot(readings: [], date: Date(timeIntervalSince1970: 0))

    static func == (lhs: GameHUDSnapshot, rhs: GameHUDSnapshot) -> Bool {
        lhs.readings == rhs.readings
    }
}

/// Game HUD 的硬件数据源:从 `MonitorStore` 的**未过滤**采样结果取数。
///
/// 主面板行显隐由 `MonitorStore.modules`(`settings.isVisible` 过滤)承担,
/// Game HUD 的勾选与主面板显隐互相独立,故直接消费 `allModules`。本协议
/// 只读快照,不新增硬件采样器、不改采样频率;HUD 隐藏期订阅方不取快照,
/// 不产生仅为 HUD 服务的重绘(见 spec:生命周期和性能)。
protocol GameHUDSnapshotProviding: AnyObject {
    /// 当前最近一次采样结果(未经主面板显隐过滤)。
    func currentSnapshot(enabledIDs: Set<GameHUDMetricID>) -> GameHUDSnapshot
    /// 采样结果更新时发布;发布方在主线程。
    var snapshotPublisher: AnyPublisher<GameHUDSnapshot, Never> { get }
}

/// CPU 占用的取数口径:优先整机总值,缺失时以 `system`+`user` 同口径合成。
/// 两个 ID 都是真实采样值,合成不引入额外估算。
nonisolated func gameHUDCPUPercent(from cpu: MonitorModule) -> Double? {
    if let system = cpu.metrics.first(where: { $0.name == "system" })?.numericValue,
       let user = cpu.metrics.first(where: { $0.name == "user" })?.numericValue {
        return min(100, max(0, system + user))
    }
    return nil
}

/// `GameHUDSnapshotProviding` 的默认实现:桥接 `MonitorStore` 的未过滤
/// 采样结果。订阅方(HUD 视图)只应在 HUD 可见时订阅;发布频率与主采样
/// 管线一致(不新增采样器),隐藏期无订阅即无额外重绘。
@MainActor
final class GameHUDSnapshotProvider: ObservableObject, GameHUDSnapshotProviding {
    private let store: MonitorStore
    private let subject = PassthroughSubject<GameHUDSnapshot, Never>()
    private(set) var activeSubscribers: Int = 0

    /// 上一次发布的快照。发布前与旧值比较,读数未变时不重发,避免空转
    /// 触发 HUD 视图树重算(对齐 applySamplingSuccess 的跳过语义)。
    private var lastSnapshot: GameHUDSnapshot?

    var snapshotPublisher: AnyPublisher<GameHUDSnapshot, Never> {
        subject
            .handleEvents(
                receiveSubscription: { [weak self] _ in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            self?.activeSubscribers += 1
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.activeSubscribers += 1
                        }
                    }
                },
                receiveCancel: { [weak self] in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated {
                            self?.activeSubscribers = max(0, (self?.activeSubscribers ?? 1) - 1)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.activeSubscribers = max(0, (self?.activeSubscribers ?? 1) - 1)
                        }
                    }
                }
            )
            .eraseToAnyPublisher()
    }

    init(store: MonitorStore) {
        self.store = store
    }

    /// 从 `allModules`(未经主面板显隐过滤)读取当前已勾选条目的读数。
    /// 只读已发布的采样结果,不触发采样。
    func currentSnapshot(enabledIDs: Set<GameHUDMetricID>) -> GameHUDSnapshot {
        GameHUDSnapshot(readings: Self.readings(enabledIDs: enabledIDs, in: store.allModulesForHUD), date: Date())
    }

    /// 由 `MonitorStore.applySamplingSuccess` 在每轮采样应用后调用。
    /// 无活跃订阅、无勾选或读数与上一次完全一致时不执行重构或发布。
    func publishIfChanged(enabledIDs: Set<GameHUDMetricID>) {
        guard activeSubscribers > 0 else { return }
        let ids = GameHUDMetricCatalog.readableIDs(from: enabledIDs)
        guard !ids.isEmpty else { return }
        let snapshot = GameHUDSnapshot(readings: Self.readings(enabledIDs: ids, in: store.allModulesForHUD), date: Date())
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        subject.send(snapshot)
    }

    /// 单条指标读取。找到模块但本次采样缺值 → value=nil(显示 —);
    /// 模块整个缺失(未采样过/采样失败占位)同样按缺值处理,不伪造成 0。
    nonisolated static func readings(enabledIDs: Set<GameHUDMetricID>, in modules: [MonitorModule]) -> [GameHUDReading] {
        let ordered = GameHUDMetricCatalog.availableEntries()
            .filter { enabledIDs.contains($0.id) && $0.id != .fps && $0.id != .averageFPS && $0.id != .onePercentLow && $0.id != .frameTime }
        return ordered.map { entry in
            let module = modules.first { $0.kind == entry.kind }
            return GameHUDReading(
                metricID: entry.id.rawValue,
                kind: entry.kind,
                value: displayValue(for: entry.id, module: module),
                percent: percentValue(for: entry.id, module: module)
            )
        }
    }

    // MARK: - 逐条读取

    private nonisolated static func displayValue(for id: GameHUDMetricID, module: MonitorModule?) -> String? {
        guard let module, !module.isPlaceholder else { return nil }
        switch id {
        case .fps, .averageFPS, .onePercentLow, .frameTime:
            return nil
        case .cpuUsage:
            guard let cpu = gameHUDCPUPercent(from: module) else { return nil }
            return percent(cpu)
        case .gpuRender:
            return modulePercentString(module, "render")
        case .gpuTiler:
            return modulePercentString(module, "tiler")
        case .cpuPower:
            let m = module.metrics.first(where: { $0.name == "cpu-power" })
            return (m?.value == nil || m?.value == "--") ? nil : m?.value
        case .gpuPower:
            let m = module.metrics.first(where: { $0.name == "gpu-power" })
            return (m?.value == nil || m?.value == "--") ? nil : m?.value
        case .fanSpeed:
            if let maxRPM = module.fans?.map(\.currentRPM).max(), maxRPM > 0 {
                return "\(maxRPM) RPM"
            }
            if module.value > 0 {
                return "\(Int(module.value)) RPM"
            }
            let summary = module.summary
            return (summary.isEmpty || summary == "—") ? nil : summary
        case .memoryUsed:
            return module.metrics.first { $0.name == "used" }?.value
        case .gpuMemory:
            return module.metrics.first { $0.name == "gpu-memory" }?.value
        case .systemPower:
            return module.metrics.first { $0.name == "power" }?.value
        case .cpuTemperature:
            guard let temp = module.metrics.first(where: { $0.name == "temperature" })?.value else { return nil }
            let thermalLevel: String
            let rawLevel = module.metrics.first(where: { $0.name == "thermal-pressure" })?.value
            switch rawLevel {
            case "normal":
                thermalLevel = String(localized: "thermal-pressure.normal")
            case "fair":
                thermalLevel = String(localized: "thermal-pressure.fair")
            case "serious":
                thermalLevel = String(localized: "thermal-pressure.serious")
            case "critical":
                thermalLevel = String(localized: "thermal-pressure.critical")
            default:
                switch ProcessInfo.processInfo.thermalState {
                case .nominal:
                    thermalLevel = String(localized: "thermal-pressure.normal")
                case .fair:
                    thermalLevel = String(localized: "thermal-pressure.fair")
                case .serious:
                    thermalLevel = String(localized: "thermal-pressure.serious")
                case .critical:
                    thermalLevel = String(localized: "thermal-pressure.critical")
                @unknown default:
                    thermalLevel = String(localized: "thermal-pressure.normal")
                }
            }
            return "\(thermalLevel) · \(temp)"
        }
    }

    private nonisolated static func percentValue(for id: GameHUDMetricID, module: MonitorModule?) -> Double? {
        guard let module, !module.isPlaceholder else { return nil }
        switch id {
        case .cpuUsage:
            return gameHUDCPUPercent(from: module)
        case .gpuRender:
            return module.metrics.first { $0.name == "render" }?.numericValue
        case .gpuTiler:
            return module.metrics.first { $0.name == "tiler" }?.numericValue
        case .fps, .averageFPS, .onePercentLow, .frameTime, .memoryUsed, .gpuMemory, .systemPower, .cpuTemperature, .cpuPower, .gpuPower, .fanSpeed:
            return nil
        }
    }

    private nonisolated static func modulePercentString(_ module: MonitorModule, _ name: String) -> String? {
        guard let metric = module.metrics.first(where: { $0.name == name }) else { return nil }
        guard let numeric = metric.numericValue else { return metric.value == "--" ? nil : metric.value }
        return percent(numeric)
    }
}
