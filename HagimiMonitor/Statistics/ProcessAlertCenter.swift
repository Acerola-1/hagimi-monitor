import AppKit
import Combine
import Foundation
import OSLog
import UserNotifications

/// 进程高负载事件模型。
nonisolated struct ProcessAlertEpisode: Identifiable, Equatable, Sendable {
    nonisolated enum Metric: String, Codable, Sendable {
        case cpu
        case gpu
        case memory
        case network
    }

    nonisolated enum State: String, Codable, Sendable {
        case ongoing
        case recovered
        case interrupted
    }

    /// 结束原因，区分确认恢复与观测中断。
    nonisolated enum EndReason: String, Codable, Sendable {
        case recovered
        case observationGap
        case notObserved
        case sourceFailure
        case processExited
        case suspended
        case replaced
    }

    let id: UUID
    let appKey: String
    let name: String
    let metric: Metric
    let startedAt: Date
    var lastSeenAt: Date
    var endedAt: Date?
    var peakUsage: Double
    var averageUsage: Double
    /// 本连续段内累计的有效高占用秒数，由有效覆盖区间累加推导。
    var continuousHighSeconds: TimeInterval
    /// 首末观测时间跨度。
    var eventSpanSeconds: TimeInterval
    /// 高占用采样观测次数。
    var observationCount: Int
    /// 有效覆盖分段，供按查询范围精确裁剪时长与均值。
    var segments: [AppResourceEventStateMachine.CoveredSegment]
    var endReason: EndReason?
    var state: State
    /// 各档位在有效覆盖内的累计秒数。
    var tier1Seconds: TimeInterval
    var tier2Seconds: TimeInterval
    var tier3Seconds: TimeInterval
    var iconPNG: Data?
    var notified: Bool

    /// 展示用分钟数，由持续高占用秒数换算。
    var durationMinutes: Int {
        Int((continuousHighSeconds / 60).rounded())
    }

    init(
        id: UUID = UUID(),
        appKey: String,
        name: String,
        metric: Metric,
        startedAt: Date,
        lastSeenAt: Date,
        endedAt: Date? = nil,
        peakUsage: Double,
        averageUsage: Double,
        continuousHighSeconds: TimeInterval = 0,
        eventSpanSeconds: TimeInterval = 0,
        observationCount: Int = 0,
        segments: [AppResourceEventStateMachine.CoveredSegment] = [],
        endReason: EndReason? = nil,
        state: State = .ongoing,
        tier1Seconds: TimeInterval = 0,
        tier2Seconds: TimeInterval = 0,
        tier3Seconds: TimeInterval = 0,
        iconPNG: Data? = nil,
        notified: Bool = false
    ) {
        self.id = id
        self.appKey = appKey
        self.name = name
        self.metric = metric
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.endedAt = endedAt
        self.peakUsage = peakUsage
        self.averageUsage = averageUsage
        self.continuousHighSeconds = continuousHighSeconds
        self.eventSpanSeconds = eventSpanSeconds
        self.observationCount = observationCount
        self.segments = segments
        self.endReason = endReason
        self.state = state
        self.tier1Seconds = tier1Seconds
        self.tier2Seconds = tier2Seconds
        self.tier3Seconds = tier3Seconds
        self.iconPNG = iconPNG
        self.notified = notified
    }
}

extension ProcessAlertEpisode {
    /// 使用状态机当前状态刷新展示字段。
    mutating func updated(from state: AppResourceEventStateMachine.State, at date: Date) {
        lastSeenAt = max(lastSeenAt, date)
        peakUsage = state.peakUsage
        averageUsage = state.averageUsage
        continuousHighSeconds = state.continuousHighSeconds
        observationCount = state.highObservationCount
        segments = state.segments
        if let started = state.startedAt {
            eventSpanSeconds = date.timeIntervalSince(started)
        }
    }
}

/// 按应用合并的进程高负载聚合组模型（解决同一应用同时触发多项指标时的展示集中度）
nonisolated struct ProcessAppAlertGroup: Identifiable, Equatable, Sendable {
    var id: String { appKey }
    let appKey: String
    let name: String
    let iconPNG: Data?
    var episodes: [ProcessAlertEpisode]

    var worstState: ProcessAlertEpisode.State {
        episodes.contains { $0.state == .ongoing } ? .ongoing : .recovered
    }

    var maxDurationMinutes: Int {
        episodes.map(\.durationMinutes).max() ?? 0
    }
}

/// 进程长期高负载监测与告警中心:
/// 追踪导致系统严重压力负担的 App 或系统进程（如 WindowServer、dasd 等），
/// 统计其持续占用时长、峰值、均值及档位时间分布，驱动设置页状态展示与系统通知。
final class ProcessAlertCenter: ObservableObject {
    static let shared = ProcessAlertCenter()

    /// 当前进行中或最近发生的高负载事件
    @Published private(set) var activeAlerts: [ProcessAlertEpisode] = []
    /// 历史已恢复的告警记录
    @Published private(set) var recentAlerts: [ProcessAlertEpisode] = []

    /// 按应用合并后的活跃高负载警报组
    var activeAppGroups: [ProcessAppAlertGroup] {
        let grouped = Dictionary(grouping: activeAlerts, by: \.appKey)
        return grouped.map { (key, eps) in
            let sortedEps = eps.sorted { $0.durationMinutes > $1.durationMinutes }
            let name = sortedEps.first?.name ?? key
            let icon = sortedEps.first(where: { $0.iconPNG != nil })?.iconPNG
            return ProcessAppAlertGroup(appKey: key, name: name, iconPNG: icon, episodes: sortedEps)
        }.sorted { $0.maxDurationMinutes > $1.maxDurationMinutes }
    }

    private var episodes: [String: ProcessAlertEpisode] = [:]
    /// 每个 (应用, 指标) 的状态机累积状态。与展示模型分开保存，
    /// 因为加权均值需要 Σ(值 × 有效秒数)，仅靠公开字段无法还原。
    private var states: [String: AppResourceEventStateMachine.State] = [:]
    /// 本拍实际出现的 (应用, 指标)。用于在采样成功后判断哪些指标本次未提供。
    private var observedKeys = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var isNotificationsEnabled = false
    private var isHighLoadAppAlertEnabled = true
    private var isStatisticsEnabled = true
    /// 忽略名单：白名单内的应用不推送通知也不出现在活跃提示中，但仍计入历史统计。
    private var ignoredApps: [AlertIgnoredApp] = []
    /// 同期系统压力证据，由 PressureAlertCenter 的最新档位更新。
    /// 没有有效观测时保持 unknown，通知策略据此不发系统通知。
    private var systemPressure: SystemPressureSnapshot = .unknown
    /// 已通知档位，按 (应用, 指标) 记录，用于同事件内的升级判断与去重。
    private var notifiedTiers: [String: Int] = [:]
    /// 跨事件通知冷却记录，按 (应用, 指标) 保存上次成功通知时刻。
    private var lastNotifiedAt: [String: Date] = [:]
    /// 通知发送器可注入：验证失败重试与「不虚记成功」时用替身，正式运行走系统通知中心。
    private let notificationDispatcher: AppAlertNotificationDispatcher
    /// 确认事件的持久化钩子。由持有进程库的调用方设置；未设置时事件只存在于内存。
    var eventPersister: ((PersistedAppEvent) -> Void)?

    /// 高负载持续判定门槛（秒）：连续有效覆盖达到门槛才确认事件。
    static let sustainedThresholdSeconds = AppResourceEventStateMachine.defaultSustainedSeconds
    /// 跨事件通知冷却时间（秒）：默认 15 分钟。
    static let notificationCooldown: TimeInterval = 15 * 60
    /// 兼容既有调用的分钟表示。
    static var sustainedThresholdMinutes: Int { Int(sustainedThresholdSeconds / 60) }

    init(notificationDispatcher: AppAlertNotificationDispatcher = AppAlertNotificationDispatcher()) {
        self.notificationDispatcher = notificationDispatcher
    }

    /// 绑定设置项
    func attach(to store: MonitorStore) {
        store.settings.$statisticsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.isStatisticsEnabled = enabled
                // 关闭记录时将进行中的事件标记为中断。
                if !enabled { self?.interruptAll(reason: .suspended) }
            }
            .store(in: &cancellables)

        store.settings.$alertNotificationsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.isNotificationsEnabled = enabled
            }
            .store(in: &cancellables)

        store.settings.$alertHighLoadAppEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.isHighLoadAppAlertEnabled = enabled
            }
            .store(in: &cancellables)

        store.settings.$alertIgnoredApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.updateIgnoredApps(apps)
            }
            .store(in: &cancellables)

        // 同期系统压力状态提取：订阅未过滤的全量采样快照，不受面板模块显隐影响。
        store.allModulesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modules in
                guard let self else { return }
                let levels = PressureAlertCenter.levels(from: modules)
                self.updateSystemPressure(SystemPressureSnapshot(
                    memoryLevel: levels.memory ?? 0,
                    thermalLevel: levels.thermal ?? 0,
                    hasValidObservation: levels.memory != nil || levels.thermal != nil
                ))
            }
            .store(in: &cancellables)
    }

    func reset() {
        episodes.removeAll()
        states.removeAll()
        observedKeys.removeAll()
        notifiedTiers.removeAll()
        lastNotifiedAt.removeAll()
        activeAlerts.removeAll()
    }

    /// 更新忽略应用白名单并立即刷新活跃提示列表。
    func updateIgnoredApps(_ apps: [AlertIgnoredApp]) {
        ignoredApps = apps
        refreshActiveList()
    }

    /// 更新通知总开关与分项开关（供单测直接驱动）。
    func updateNotificationPreferences(enabled: Bool, highLoadAppEnabled: Bool = true) {
        isNotificationsEnabled = enabled
        isHighLoadAppAlertEnabled = highLoadAppEnabled
    }

    func isAppIgnored(appKey: String, name: String) -> Bool {
        ignoredApps.contains { $0.matches(appKey: appKey, name: name) }
    }

    /// 更新同期系统压力证据快照。
    func updateSystemPressure(_ snapshot: SystemPressureSnapshot) {
        systemPressure = snapshot
    }

    /// 关注应用上限。定向复查只追踪少量活跃关注应用，不扩大采样范围。
    static let targetedRecheckLimit = 5

    /// 当前应在下一拍定向复查的应用（超过上限时仅保留最近活跃的应用）。
    func applicationsNeedingRecheck() -> [(appKey: String, metric: ProcessAlertEpisode.Metric)] {
        let running = episodes.values
            .filter { $0.state == .ongoing }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
            .prefix(Self.targetedRecheckLimit)
        return running.map { ($0.appKey, $0.metric) }
    }

    /// 记录复查失败，由状态机在超时后统一判定中断。
    func noteRecheckFailure(appKey: String, metric: ProcessAlertEpisode.Metric, at date: Date) {
        let key = Self.stateKey(appKey: appKey, metric: metric)
        guard states[key]?.isRunning == true else { return }
        _ = date
    }

    /// 睡眠、关闭记录或重启前，把进行中的事件以中断结束。
    func interruptAll(reason: ProcessAlertEpisode.EndReason, at date: Date = Date()) {
        let keys = Array(states.keys)
        for key in keys {
            guard let episode = episodes[key], episode.state == .ongoing else { continue }
            finalize(key: key, reason: reason, at: date)
        }
        refreshActiveList()
    }

    /// 摄入一拍进程采样（网络单位为 B/s）。
    func ingest(
        cpu: [(name: String, pid: pid_t, usage: Double)],
        memory: [(name: String, pid: pid_t, bytes: Double)],
        gpu: [(name: String, pid: pid_t, usage: Double)],
        network: [(name: String, pid: pid_t, downBytes: Double, upBytes: Double)],
        at date: Date,
        providedMetrics: Set<ProcessAlertEpisode.Metric>? = nil,
        iconProvider: ((String, String, pid_t) -> Data?)? = nil
    ) {
        guard isStatisticsEnabled else { return }

        // 门槛与档位统一来自 StatisticsMetricDefinition,调用点不再各写一套数字。
        let physicalMemory = StatisticsMetricDefinition.physicalMemoryBytes()
        let logicalCores = StatisticsMetricDefinition.logicalCoreCount()
        // 本拍实际提供的 (应用, 指标)。空数组不是「已恢复」的证据。
        observedKeys.removeAll()

        let effectiveProvided: Set<ProcessAlertEpisode.Metric>
        if let providedMetrics {
            effectiveProvided = providedMetrics
        } else if !network.isEmpty && cpu.isEmpty && memory.isEmpty && gpu.isEmpty {
            effectiveProvided = [.network]
        } else {
            var inferred: Set<ProcessAlertEpisode.Metric> = [.cpu, .memory, .gpu]
            if !network.isEmpty { inferred.insert(.network) }
            effectiveProvided = inferred
        }

        // 各维度独立分批更新。
        if let threshold = StatisticsMetricDefinition.attentionThreshold(for: .gpu) {
            ingestBatch(
                entries: gpu.map { (name: $0.name, pid: $0.pid, value: $0.usage) },
                metric: .gpu,
                threshold: threshold.value,
                at: date,
                iconProvider: iconProvider
            )
        }

        // CPU 门槛按逻辑核数自适应，以单逻辑核 100% 为基准。
        if let threshold = StatisticsMetricDefinition.attentionThreshold(for: .cpu, logicalCoreCount: logicalCores) {
            ingestBatch(
                entries: cpu.map { (name: $0.name, pid: $0.pid, value: $0.usage) },
                metric: .cpu,
                threshold: threshold.value,
                at: date,
                iconProvider: iconProvider
            )
        }

        // 内存门槛 = max(3.5 GiB, 物理容量 × 20%)，原始值为字节。
        if let threshold = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: physicalMemory) {
            ingestBatch(
                entries: memory.map { (name: $0.name, pid: $0.pid, value: $0.bytes) },
                metric: .memory,
                threshold: threshold.value,
                at: date,
                iconProvider: iconProvider
            )
        }

        // 网络门槛 20 MiB/s，输入单位为 B/s。
        if let threshold = StatisticsMetricDefinition.attentionThreshold(for: .network) {
            ingestBatch(
                entries: network.map { (name: $0.name, pid: $0.pid, value: $0.downBytes + $0.upBytes) },
                metric: .network,
                threshold: threshold.value,
                at: date,
                iconProvider: iconProvider
            )
        }

        // 对未出现在本拍有效指标结果中的关注事件标记为观测未知。
        settleUnobservedMetrics(at: date, providedMetrics: effectiveProvided)

        refreshActiveList()
    }

    /// 优先将存活进程解析为与 StatisticsProcessStore 同源的稳定身份键，
    /// 解析失败或为测试假 PID 时回退为进程显示名称。
    static func resolveAppKey(name: String, pid: pid_t) -> String {
        guard pid > 0 else { return name }
        let identity = AppIdentityResolver.resolve(pid: pid, name: name)
        return identity.isStableAcrossLaunches ? identity.storageKey : name
    }

    /// 处理单个指标批次，按门槛转换为高/低观测信号。
    private func ingestBatch(
        entries: [(name: String, pid: pid_t, value: Double)],
        metric: ProcessAlertEpisode.Metric,
        threshold: Double,
        at date: Date,
        iconProvider: ((String, String, pid_t) -> Data?)?
    ) {
        var mergedByKey: [String: (appKey: String, name: String, pid: pid_t, value: Double)] = [:]
        var orderedKeys: [String] = []
        for entry in entries {
            let appKey = Self.resolveAppKey(name: entry.name, pid: entry.pid)
            if let existing = mergedByKey[appKey] {
                if entry.value > existing.value {
                    mergedByKey[appKey] = (appKey, entry.name, entry.pid, entry.value)
                }
            } else {
                orderedKeys.append(appKey)
                mergedByKey[appKey] = (appKey, entry.name, entry.pid, entry.value)
            }
        }
        for appKey in orderedKeys {
            guard let item = mergedByKey[appKey] else { continue }
            let key = Self.stateKey(appKey: item.appKey, metric: metric)
            observedKeys.insert(key)
            let signal: AppResourceEventStateMachine.Signal = item.value >= threshold
                ? .high(value: item.value)
                : .low(value: item.value)
            consume(signal, key: key, appKey: item.appKey, name: item.name,
                    metric: metric, at: date, pid: item.pid, iconProvider: iconProvider)
        }
    }

    /// 对未出现在本拍该指标结果中的关注事件发送未知信号。
    private func settleUnobservedMetrics(at date: Date, providedMetrics: Set<ProcessAlertEpisode.Metric>) {
        let runningKeys = states.compactMap { $0.value.isRunning ? $0.key : nil }
        for key in runningKeys where !observedKeys.contains(key) {
            guard let episode = episodes[key], providedMetrics.contains(episode.metric) else { continue }
            consume(.unknown, key: key, appKey: episode.appKey,
                    name: episode.name, metric: episode.metric, at: date,
                    pid: 0, iconProvider: nil)
        }
    }

    /// 把一次信号交给状态机，并把结果同步到展示模型。
    private func consume(
        _ signal: AppResourceEventStateMachine.Signal,
        key: String,
        appKey: String,
        name: String,
        metric: ProcessAlertEpisode.Metric,
        at date: Date,
        pid: pid_t,
        iconProvider: ((String, String, pid_t) -> Data?)?
    ) {
        let transition = AppResourceEventStateMachine.reduce(
            state: states[key] ?? .init(),
            observation: AppResourceEventStateMachine.Observation(signal: signal, at: date),
            sustainedSeconds: Self.sustainedThresholdSeconds
        )
        states[key] = transition.state

        let observedSecondsBefore = episodes[key]?.continuousHighSeconds ?? 0
        switch signal {
        case .high(let value):
            let isNew = episodes[key] == nil
            var episode = episodes[key] ?? ProcessAlertEpisode(
                appKey: appKey,
                name: name,
                metric: metric,
                startedAt: date,
                lastSeenAt: date,
                peakUsage: value,
                averageUsage: value
            )
            episode.updated(from: transition.state, at: date)
            if isNew || episode.iconPNG == nil {
                episode.iconPNG = iconProvider?(appKey, name, pid)
                    ?? ProcessIconCache.fullSizePNG(forPID: pid, sidePixels: 128)
            }
            // 档位时长按有效覆盖秒数累加。
            let bandIndex = Self.bandIndex(metric: metric, rawValue: value)
            let delta = transition.state.continuousHighSeconds - observedSecondsBefore
            if delta > 0 {
                switch bandIndex {
                case 3: episode.tier3Seconds += delta
                case 2: episode.tier2Seconds += delta
                case 1: episode.tier1Seconds += delta
                default: break
                }
            }
            // 评估通知策略并决定是否发送。
            let tier = AppAlertNotificationPolicy.tier(metric: metric, rawValue: value)
            let ignored = isAppIgnored(appKey: appKey, name: name)
            let inCooldown = lastNotifiedAt[key].map { date.timeIntervalSince($0) < Self.notificationCooldown } ?? false
            let decision = AppAlertNotificationPolicy.decide(
                notificationsEnabled: isNotificationsEnabled && isHighLoadAppAlertEnabled && !ignored,
                isConfirmed: transition.state.isConfirmed,
                systemPressure: systemPressure,
                tier: tier,
                alreadyNotifiedTier: notifiedTiers[key],
                inCooldown: inCooldown
            )
            switch decision {
            case .send(let tier), .update(let tier):
                notifiedTiers[key] = tier
                lastNotifiedAt[key] = date
                episode.notified = true
                sendNotification(for: episode, sentAt: date)
            case .skip:
                break
            }
            episodes[key] = episode

        case .low:
            if let episode = episodes[key] {
                var updated = episode
                updated.updated(from: transition.state, at: date)
                episodes[key] = updated
            }

        case .unknown:
            // 未观测时段不推进 lastSeenAt 与 eventSpanSeconds。
            break

        case .ended:
            break
        }

        if let outcome = transition.finishedEvent {
            record(outcome: outcome, key: key, appKey: appKey, name: name,
                   metric: metric, iconPNG: episodes[key]?.iconPNG)
            states[key] = nil
            episodes[key] = nil
            notifiedTiers[key] = nil
        }
    }

    /// 用状态机的真实统计覆盖展示模型里的时长字段。
    private func record(
        outcome: AppResourceEventStateMachine.Outcome,
        key: String,
        appKey: String,
        name: String,
        metric: ProcessAlertEpisode.Metric,
        iconPNG: Data?
    ) {
        let episode = ProcessAlertEpisode(
            id: episodes[key]?.id ?? UUID(),
            appKey: appKey,
            name: name,
            metric: metric,
            startedAt: outcome.startedAt,
            lastSeenAt: outcome.endedAt,
            endedAt: outcome.endedAt,
            peakUsage: outcome.peakUsage,
            averageUsage: outcome.averageUsage,
            continuousHighSeconds: outcome.continuousHighSeconds,
            eventSpanSeconds: outcome.eventSpanSeconds,
            observationCount: outcome.highObservationCount,
            segments: outcome.segments,
            endReason: outcome.reason,
            state: outcome.reason == .recovered ? .recovered : .interrupted,
            tier1Seconds: episodes[key]?.tier1Seconds ?? 0,
            tier2Seconds: episodes[key]?.tier2Seconds ?? 0,
            tier3Seconds: episodes[key]?.tier3Seconds ?? 0,
            iconPNG: iconPNG,
            notified: episodes[key]?.notified ?? false
        )
        recentAlerts.insert(episode, at: 0)
        if recentAlerts.count > 20 { recentAlerts.removeLast() }
        // 持久化确认事件。
        eventPersister?(PersistedAppEvent(
            eventID: episode.id.uuidString,
            appKey: episode.appKey,
            name: episode.name,
            metric: episode.metric.rawValue,
            startedAt: episode.startedAt,
            endedAt: episode.endedAt ?? outcome.endedAt,
            lastEffectiveAt: outcome.endedAt,
            continuousHighSeconds: episode.continuousHighSeconds,
            eventSpanSeconds: episode.eventSpanSeconds,
            averageUsage: episode.averageUsage,
            peakUsage: episode.peakUsage,
            observationCount: episode.observationCount,
            segments: episode.segments,
            state: episode.state.rawValue,
            endReason: episode.endReason?.rawValue,
            notified: episode.notified
        ))
    }

    /// 以给定原因结束一个进行中的事件（睡眠/关闭/重启/进程退出）。
    private func finalize(key: String, reason: ProcessAlertEpisode.EndReason, at date: Date) {
        let transition = AppResourceEventStateMachine.reduce(
            state: states[key] ?? .init(),
            observation: AppResourceEventStateMachine.Observation(signal: .ended(reason: reason), at: date),
            sustainedSeconds: Self.sustainedThresholdSeconds
        )
        if let outcome = transition.finishedEvent {
            record(
                outcome: outcome,
                key: key,
                appKey: episodes[key]?.appKey ?? "",
                name: episodes[key]?.name ?? "",
                metric: episodes[key]?.metric ?? .cpu,
                iconPNG: episodes[key]?.iconPNG
            )
        }
        states[key] = nil
        episodes[key] = nil
        notifiedTiers[key] = nil
    }

    /// 档位下标(1...3),低于首档返回 0。边界来自共享指标定义。
    private static func bandIndex(metric: ProcessAlertEpisode.Metric, rawValue: Double) -> Int {
        let definition: StatisticsMetricDefinition.Metric
        switch metric {
        case .cpu: definition = .cpu
        case .gpu: definition = .gpu
        case .memory: definition = .memory
        case .network: definition = .network
        }
        guard let band = StatisticsMetricDefinition.band(for: definition, rawValue: rawValue) else { return 0 }
        let boundaries: [Double]
        switch definition {
        case .cpu: boundaries = StatisticsMetricDefinition.cpuBandBoundaries
        case .gpu: boundaries = StatisticsMetricDefinition.gpuBandBoundaries
        case .memory: boundaries = StatisticsMetricDefinition.memoryBands.map(\.lowerBound)
        case .network: boundaries = StatisticsMetricDefinition.networkBandBoundaries.map { $0 * StatisticsMetricDefinition.mebibyte }
        }
        return (boundaries.firstIndex(of: band.lowerBound) ?? 0) + 1
    }

    private func refreshActiveList() {
        // 仅将达到持续门槛且未在忽略名单中的进行中事件展示在活跃列表中。
        activeAlerts = episodes.values
            .filter {
                $0.state == .ongoing
                    && $0.continuousHighSeconds >= Self.sustainedThresholdSeconds
                    && !isAppIgnored(appKey: $0.appKey, name: $0.name)
            }
            .sorted { $0.continuousHighSeconds > $1.continuousHighSeconds }
    }

    /// 异步发送高负载进程通知。
    private func sendNotification(for episode: ProcessAlertEpisode, sentAt: Date) {
        let content = makeNotificationContent(for: episode)
        let key = Self.stateKey(appKey: episode.appKey, metric: episode.metric)
        let dispatcher = notificationDispatcher
        Task { [weak self] in
            let result = await dispatcher.dispatch(
                identifier: content.identifier,
                title: content.title,
                body: content.body
            )
            guard let self else { return }
            await MainActor.run {
                if !result.shouldMarkNotified {
                    // 发送未成功时清空已记录档位与本次冷却时间，允许后续重试。
                    self.notifiedTiers[key] = nil
                    if self.lastNotifiedAt[key] == sentAt {
                        self.lastNotifiedAt[key] = nil
                    }
                }
            }
        }
    }

    private func makeNotificationContent(
        for episode: ProcessAlertEpisode
    ) -> (identifier: String, title: String, body: String) {
        let titleFormat: String
        switch episode.metric {
        case .memory:
            titleFormat = String(localized: "alert.process.highload.memory.title", defaultValue: "%@ 内存占用偏高")
        case .cpu:
            titleFormat = String(localized: "alert.process.highload.cpu.title", defaultValue: "%@ 的 CPU 占用偏高")
        case .gpu:
            titleFormat = String(localized: "alert.process.highload.gpu.title", defaultValue: "%@ 的 GPU 占用偏高")
        case .network:
            titleFormat = String(localized: "alert.process.highload.network.title", defaultValue: "%@ 网络流量偏高")
        }
        let bodyFormat = String(
            localized: "alert.process.highload.body",
            defaultValue: "已持续 %@，平均约 %@。"
        )
        let copy = Self.highLoadNotificationCopy(
            name: episode.name,
            duration: StatisticsDisplayFormat.duration(episode.continuousHighSeconds),
            usage: Self.notificationUsageText(
                StatisticsDisplayFormat.applicationObservationValue(episode.averageUsage, metric: episode.metric)
            ),
            titleFormat: titleFormat,
            bodyFormat: bodyFormat
        )
        return (Self.notificationIdentifier(appKey: episode.appKey, metric: episode.metric), copy.title, copy.body)
    }

    /// 高负载通知。标题说哪一项偏高，正文把持续时间和平均值分开，
    /// 避免读成这段时间一直停在某个固定用量。
    /// 时长已经是带单位的字符串，两个占位符都是 `%@`。
    static func highLoadNotificationCopy(
        name: String,
        duration: String,
        usage: String,
        titleFormat: String,
        bodyFormat: String
    ) -> (title: String, body: String) {
        (
            String(format: titleFormat, name),
            String(format: bodyFormat, duration, usage)
        )
    }

    /// 「4.0 GB」在「平均约」后面读起来像精确到小数。整数部分已经够用时去掉 `.0`。
    static func notificationUsageText(_ text: String) -> String {
        text.replacingOccurrences(of: ".0 ", with: " ")
    }

    static func stateKey(appKey: String, metric: ProcessAlertEpisode.Metric) -> String {
        "\(appKey)-\(metric.rawValue)"
    }

    static func notificationIdentifier(appKey: String, metric: ProcessAlertEpisode.Metric) -> String {
        "hagimi-process-\(appKey)-\(metric.rawValue)"
    }

}
