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

    let id: UUID
    let appKey: String
    let name: String
    let metric: Metric
    let startedAt: Date
    var lastSeenAt: Date
    var endedAt: Date?
    var peakUsage: Double
    var averageUsage: Double
    var durationMinutes: Int
    var state: State
    var tier1Minutes: Int
    var tier2Minutes: Int
    var tier3Minutes: Int
    var iconPNG: Data?
    var notified: Bool

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
        durationMinutes: Int,
        state: State = .ongoing,
        tier1Minutes: Int = 0,
        tier2Minutes: Int = 0,
        tier3Minutes: Int = 0,
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
        self.durationMinutes = durationMinutes
        self.state = state
        self.tier1Minutes = tier1Minutes
        self.tier2Minutes = tier2Minutes
        self.tier3Minutes = tier3Minutes
        self.iconPNG = iconPNG
        self.notified = notified
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
    private var cancellables = Set<AnyCancellable>()
    private var isNotificationsEnabled = false
    private var isStatisticsEnabled = true

    /// 高负载持续判定门槛（分钟数）：连续达到门槛即判定为长期高负载
    static let sustainedThresholdMinutes = 2

    private init() {
        // 若设置了仿真测试环境变量，自动载入 WindowServer 示例场景
        if ProcessInfo.processInfo.environment["HAGIMI_ALERT_FIXTURE"] != nil {
            simulateWindowServerDemo()
        }
    }

    /// 绑定设置项
    func attach(to store: MonitorStore) {
        store.settings.$statisticsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.isStatisticsEnabled = enabled
                if !enabled { self?.reset() }
            }
            .store(in: &cancellables)

        store.settings.$alertNotificationsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.isNotificationsEnabled = enabled
            }
            .store(in: &cancellables)
    }

    func reset() {
        episodes.removeAll()
        activeAlerts.removeAll()
    }

    /// 摄入一拍进程采样（由主线程定时器调用，通常为 60s 周期）
    func ingest(
        cpu: [(name: String, pid: pid_t, usage: Double)],
        memory: [(name: String, pid: pid_t, bytes: Double)],
        gpu: [(name: String, pid: pid_t, usage: Double)],
        network: [(name: String, pid: pid_t, downBytes: Double, upBytes: Double)],
        at date: Date,
        iconProvider: ((String, pid_t) -> Data?)? = nil
    ) {
        guard isStatisticsEnabled else { return }

        // 1. GPU 长期高占用判定 (阈值 >= 40%)
        for entry in gpu where entry.usage >= 40.0 {
            updateEpisode(
                appKey: entry.name,
                name: entry.name,
                metric: .gpu,
                usage: entry.usage,
                at: date,
                tier1Threshold: 20.0,
                tier2Threshold: 40.0,
                tier3Threshold: 70.0,
                pid: entry.pid,
                iconProvider: iconProvider
            )
        }

        // 2. CPU 长期高占用判定 (阈值 >= 60%)
        for entry in cpu where entry.usage >= 60.0 {
            updateEpisode(
                appKey: entry.name,
                name: entry.name,
                metric: .cpu,
                usage: entry.usage,
                at: date,
                tier1Threshold: 30.0,
                tier2Threshold: 50.0,
                tier3Threshold: 80.0,
                pid: entry.pid,
                iconProvider: iconProvider
            )
        }

        // 3. 内存过高判定 (阈值 >= 3.5 GB)
        for entry in memory where entry.bytes >= 3.5 * 1_073_741_824 {
            let usageMB = entry.bytes / 1_048_576
            updateEpisode(
                appKey: entry.name,
                name: entry.name,
                metric: .memory,
                usage: usageMB,
                at: date,
                tier1Threshold: 1024,
                tier2Threshold: 2048,
                tier3Threshold: 4096,
                pid: entry.pid,
                iconProvider: iconProvider
            )
        }

        // 4. 网络过高判定 (持续 >= 20 MB/s)
        for entry in network {
            let rateMB = (entry.downBytes + entry.upBytes) / 1_048_576
            if rateMB >= 20.0 {
                updateEpisode(
                    appKey: entry.name,
                    name: entry.name,
                    metric: .network,
                    usage: rateMB,
                    at: date,
                    tier1Threshold: 5.0,
                    tier2Threshold: 20.0,
                    tier3Threshold: 50.0,
                    pid: entry.pid,
                    iconProvider: iconProvider
                )
            }
        }

        // 检查已恢复的事件（超过 2.5 分钟没有新高负载上报的 episode）
        var toRemoveKeys: [String] = []
        for (key, var ep) in episodes where ep.state == .ongoing {
            if date.timeIntervalSince(ep.lastSeenAt) > 150 {
                ep.state = .recovered
                ep.endedAt = ep.lastSeenAt
                recentAlerts.insert(ep, at: 0)
                if recentAlerts.count > 20 { recentAlerts.removeLast() }
                toRemoveKeys.append(key)
            }
        }
        for k in toRemoveKeys {
            episodes.removeValue(forKey: k)
        }

        refreshActiveList()
    }

    private func updateEpisode(
        appKey: String,
        name: String,
        metric: ProcessAlertEpisode.Metric,
        usage: Double,
        at date: Date,
        tier1Threshold: Double,
        tier2Threshold: Double,
        tier3Threshold: Double,
        pid: pid_t,
        iconProvider: ((String, pid_t) -> Data?)?
    ) {
        let key = "\(appKey)-\(metric.rawValue)"
        if var ep = episodes[key] {
            ep.lastSeenAt = date
            ep.durationMinutes += 1
            ep.peakUsage = max(ep.peakUsage, usage)
            ep.averageUsage = (ep.averageUsage * Double(ep.durationMinutes - 1) + usage) / Double(ep.durationMinutes)

            if usage >= tier3Threshold {
                ep.tier3Minutes += 1
            } else if usage >= tier2Threshold {
                ep.tier2Minutes += 1
            } else if usage >= tier1Threshold {
                ep.tier1Minutes += 1
            }

            if ep.iconPNG == nil {
                if let icon = iconProvider?(name, pid) {
                    ep.iconPNG = icon
                } else {
                    ep.iconPNG = ProcessIconCache.fullSizePNG(forPID: pid, sidePixels: 128)
                }
            }

            // 达到持续门槛且未发通知时，发送一次通知
            if ep.durationMinutes >= Self.sustainedThresholdMinutes && !ep.notified && isNotificationsEnabled {
                ep.notified = true
                sendNotification(for: ep)
            }
            episodes[key] = ep
        } else {
            let icon = iconProvider?(name, pid) ?? ProcessIconCache.fullSizePNG(forPID: pid, sidePixels: 128)
            var t1 = 0, t2 = 0, t3 = 0
            if usage >= tier3Threshold { t3 = 1 }
            else if usage >= tier2Threshold { t2 = 1 }
            else if usage >= tier1Threshold { t1 = 1 }

            let created = ProcessAlertEpisode(
                appKey: appKey,
                name: name,
                metric: metric,
                startedAt: date,
                lastSeenAt: date,
                peakUsage: usage,
                averageUsage: usage,
                durationMinutes: 1,
                state: .ongoing,
                tier1Minutes: t1,
                tier2Minutes: t2,
                tier3Minutes: t3,
                iconPNG: icon,
                notified: false
            )
            episodes[key] = created
        }
    }

    private func refreshActiveList() {
        activeAlerts = episodes.values
            .filter { $0.state == .ongoing && $0.durationMinutes >= Self.sustainedThresholdMinutes }
            .sorted { $0.durationMinutes > $1.durationMinutes }
    }

    /// 发送高负载进程通知
    private func sendNotification(for episode: ProcessAlertEpisode) {
        let content = UNMutableNotificationContent()
        let metricText: String
        switch episode.metric {
        case .cpu: metricText = "CPU"
        case .gpu: metricText = "GPU"
        case .memory: metricText = String(localized: "stats.process.metric.mem", defaultValue: "内存")
        case .network: metricText = String(localized: "stats.process.metric.net", defaultValue: "网络")
        }

        let titleFormat = String(localized: "alert.process.highload.title", defaultValue: "高负载进程提醒 · %@")
        content.title = String(format: titleFormat, episode.name)
        let usageText = episode.metric == .memory ? "\(Int(episode.averageUsage)) MB" : String(format: "%.1f%%", episode.averageUsage)
        let bodyFormat = String(localized: "alert.process.highload.body", defaultValue: "「%@」已持续 %d 分钟占用 %@ %@，正在产生持续系统压力。")
        content.body = String(format: bodyFormat, episode.name, episode.durationMinutes, metricText, usageText)
        content.sound = .default
        content.categoryIdentifier = PressureAlertCenter.notificationCategory

        let request = UNNotificationRequest(
            identifier: "hagimi-process-\(episode.appKey)-\(episode.metric.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.sampler.error("发送进程高负载告警失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 演示或测试用的仿真高负载案例（包含 WindowServer GPU 与 Safari 内存+CPU 多指标合并）
    func simulateWindowServerDemo() {
        let now = Date()
        let wsEpisode = ProcessAlertEpisode(
            appKey: "WindowServer",
            name: "WindowServer",
            metric: .gpu,
            startedAt: now.addingTimeInterval(-35 * 60),
            lastSeenAt: now,
            peakUsage: 67.9,
            averageUsage: 57.9,
            durationMinutes: 35,
            state: .ongoing,
            tier1Minutes: 10,
            tier2Minutes: 25,
            tier3Minutes: 0,
            iconPNG: nil,
            notified: true
        )
        let safariIcon = ProcessIconCache.fullSizePNG(forBundleIdentifier: "com.apple.Safari", sidePixels: 128)
        let safariMem = ProcessAlertEpisode(
            appKey: "com.apple.Safari",
            name: "Safari 浏览器",
            metric: .memory,
            startedAt: now.addingTimeInterval(-15 * 60),
            lastSeenAt: now,
            peakUsage: 8468.0,
            averageUsage: 8301.0,
            durationMinutes: 15,
            state: .ongoing,
            tier1Minutes: 0,
            tier2Minutes: 0,
            tier3Minutes: 15,
            iconPNG: safariIcon,
            notified: true
        )
        let safariCpu = ProcessAlertEpisode(
            appKey: "com.apple.Safari",
            name: "Safari 浏览器",
            metric: .cpu,
            startedAt: now.addingTimeInterval(-12 * 60),
            lastSeenAt: now,
            peakUsage: 81.2,
            averageUsage: 74.5,
            durationMinutes: 12,
            state: .ongoing,
            tier1Minutes: 2,
            tier2Minutes: 7,
            tier3Minutes: 3,
            iconPNG: safariIcon,
            notified: true
        )
        episodes["WindowServer-gpu"] = wsEpisode
        episodes["com.apple.Safari-memory"] = safariMem
        episodes["com.apple.Safari-cpu"] = safariCpu
        refreshActiveList()
    }
}
