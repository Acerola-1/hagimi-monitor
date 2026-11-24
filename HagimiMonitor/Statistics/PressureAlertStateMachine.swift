import Foundation

/// 压力告警状态机:输入两路实时档位与时刻,输出「未读红点」与「该发哪条通知」。
/// 纯逻辑无副作用,单测直接喂档位序列。
///
/// 语义(与产品约定一致):
/// - 红点门槛与统计页「压力情况」同口径(见 `isAlertLevel`):达到门槛即进入
///   episode,episode 内未读 → 红点亮;跌回门槛以下即 episode 结束。
/// - 已读按入口独立(见 `Entry`):点开面板只清菜单栏那处红点,查看「数据统计」
///   页才清全部;档位升级重新点亮全部入口。
/// - 档位在 episode 内升高 = 升级:重新置未读;升到严重档时持续计时从升级时刻起算。
/// - episode 结束(档位回落)= 未读一并清除——告警过去后红点自动消失。
/// - 通知只在严重档发出且需持续满门槛,同一 episode 同一档位只发一次。
/// - nil(该维度本帧无有效观测)不改变任何状态:既不判恢复也不外推;
///   断档超过阈值后严重档计时重新起算,跨睡眠/停摆不累计。
struct PressureAlertStateMachine: Sendable {
    enum Kind: Sendable {
        case memory
        case thermal
    }

    /// 红点入口:已读按入口独立——用户点了哪个入口,就清哪个入口的红点。
    enum Entry: Hashable, Sendable {
        /// 菜单栏负载环 / 指标图标:点开面板即视为看过。
        case menuBar
        /// 面板右上角的数据统计入口:点它进统计页,随页面被查看而清
        /// (与统计页同侧;页面查看会清全部入口)。
        case statisticsEntry
    }

    /// 本帧新产生的一条通知。
    struct Alert: Equatable, Sendable {
        let kind: Kind
        /// 触发的原生档位(内存 2;热 2/3)。
        let level: Int
        /// 递增投递序号，确保旧请求的异步失败回调不会误撤销更新的同档通知。
        let deliveryID: UInt64
    }

    private struct KindState: Sendable {
        var episodeID: UInt64 = 0
        /// episode 内到过的最高档;0 = 无 episode。
        var peakLevel = 0
        /// 本 episode 内已被哪些入口看过;新 episode 与升级时清空(重新点亮全部)。
        var readEntries: Set<Entry> = []
        var severeSince: Date?
        var confirmedLevel = 0
        var lastConfirmedAt: Date?
        var pending: [UInt64: Delivery] = [:]

        /// 待投递也占用当前档位，避免系统回调前重复提交同档请求。
        var reservedLevel: Int {
            pending.values.reduce(confirmedLevel) { level, delivery in
                delivery.episodeID == episodeID ? max(level, delivery.level) : level
            }
        }

        var lastReservedAt: Date? {
            pending.values.lazy.map(\.submittedAt).reduce(lastConfirmedAt) { last, submittedAt in
                max(last ?? submittedAt, submittedAt)
            }
        }
    }

    private struct Delivery: Sendable {
        let episodeID: UInt64
        let level: Int
        let submittedAt: Date
    }

    private var memory = KindState()
    private var thermal = KindState()
    private var lastFrameAt: Date?
    /// 单调递增投递编号，不随 reset() 清零，避免重置前在途请求撞上重置后的新序号。
    private var nextDeliveryID: UInt64 = 0

    /// 该入口的红点是否该亮:存在进行中且尚未被这个入口看过的告警。
    func isUnread(_ entry: Entry) -> Bool {
        [memory, thermal].contains { $0.peakLevel > 0 && !$0.readEntries.contains(entry) }
    }

    /// 标记某个入口已读(点开了对应入口)。
    mutating func markRead(_ entry: Entry) {
        memory.readEntries.insert(entry)
        thermal.readEntries.insert(entry)
    }

    /// 全部入口标记已读(用户查看了统计页)。
    mutating func markAllRead() {
        markRead(.menuBar)
        markRead(.statisticsEntry)
    }

    /// 清空全部状态(记录开关关闭时静音)。
    mutating func reset() {
        memory = KindState()
        thermal = KindState()
        lastFrameAt = nil
    }

    /// 清空单个维度的状态(分项开关关闭时静音该维度，含冷却时间)。
    mutating func reset(_ kind: Kind) {
        self[kind] = KindState()
    }

    mutating func ingest(
        memoryLevel: Int?,
        thermalLevel: Int?,
        at date: Date,
        sustain: TimeInterval,
        breakThreshold: TimeInterval,
        cooldown: TimeInterval = 0
    ) -> [Alert] {
        let resumesAfterBreak = lastFrameAt.map { date.timeIntervalSince($0) > breakThreshold } ?? false
        lastFrameAt = date

        var alerts: [Alert] = []
        advance(.memory, level: memoryLevel, at: date, sustain: sustain,
                resumesAfterBreak: resumesAfterBreak, cooldown: cooldown, alerts: &alerts)
        advance(.thermal, level: thermalLevel, at: date, sustain: sustain,
                resumesAfterBreak: resumesAfterBreak, cooldown: cooldown, alerts: &alerts)
        return alerts
    }

    /// 红点门槛(episode 判定),与统计页的「压力情况」口径一致:
    /// 内存 warning(1)及以上;热 serious(2)及以上——轻微热压力在设置页不计为
    /// 压力情况,高负载下的日常波动也不该亮灯,点进去必须能看到对应的那条告警。
    static func isAlertLevel(_ kind: Kind, level: Int) -> Bool {
        switch kind {
        case .memory: level >= 1
        case .thermal: level >= 2
        }
    }

    /// 严重档 = 通知门槛:内存 2=严重;热 2=严重、3=临界。
    /// 内存警告档只亮红点不发通知——它比任务中断更常见,不值得打扰。
    static func isSevere(level: Int) -> Bool {
        level >= 2
    }

    private mutating func advance(
        _ kind: Kind,
        level: Int?,
        at date: Date,
        sustain: TimeInterval,
        resumesAfterBreak: Bool,
        cooldown: TimeInterval,
        alerts: inout [Alert]
    ) {
        guard let level else { return }
        var state = self[kind]
        defer { self[kind] = state }

        // 恢复时清除本事件状态。保留已确认时间和在途请求，供跨事件冷却使用。
        guard Self.isAlertLevel(kind, level: level) else {
            if state.peakLevel > 0 {
                state.episodeID &+= 1
                state.peakLevel = 0
                state.readEntries.removeAll()
                state.severeSince = nil
                state.confirmedLevel = 0
            }
            return
        }

        if level > state.peakLevel {
            state.peakLevel = level
            // 升级(含新 episode):全部入口重新点亮。
            state.readEntries = []
            state.severeSince = Self.isSevere(level: level) ? date : nil
        }
        if resumesAfterBreak, Self.isSevere(level: level) {
            state.severeSince = date
        }

        if Self.isSevere(level: level) {
            // 同一 episode 内短暂跌出 severe 再回升时(peak 不再增长、
            // resumesAfterBreak 也不触发),必须重启持续计时,否则
            // severeSince 恒为 nil,本 episode 内通知永远不会再发。
            if state.severeSince == nil {
                state.severeSince = date
            }
        } else {
            state.severeSince = nil
            return
        }
        guard let since = state.severeSince, date.timeIntervalSince(since) >= sustain else { return }
        // 同 episode 内只向更高严重度升级通知，避免从临界降回严重时再次弹出通知。
        let reservedLevel = state.reservedLevel
        guard level > reservedLevel else { return }
        // 跨事件冷却：同一 episode 内的严重度升级不受冷却限制，新 episode 在冷却期内不发通知。
        if reservedLevel == 0, cooldown > 0,
           let lastReservedAt = state.lastReservedAt,
           date.timeIntervalSince(lastReservedAt) < cooldown {
            return
        }
        nextDeliveryID &+= 1
        let deliveryID = nextDeliveryID
        state.pending[deliveryID] = Delivery(episodeID: state.episodeID, level: level, submittedAt: date)
        alerts.append(Alert(kind: kind, level: level, deliveryID: deliveryID))
    }

    /// 投递回调只确认或释放自己的请求。当前档位失去投递占用时，重新等待持续门槛再重试。
    mutating func completeNotification(for alert: Alert, delivered: Bool, at date: Date) {
        var state = self[alert.kind]
        guard let delivery = state.pending.removeValue(forKey: alert.deliveryID) else { return }
        let isCurrentEpisode = delivery.episodeID == state.episodeID
        if delivered {
            state.lastConfirmedAt = max(state.lastConfirmedAt ?? delivery.submittedAt, delivery.submittedAt)
            if isCurrentEpisode {
                state.confirmedLevel = max(state.confirmedLevel, delivery.level)
            }
        } else if isCurrentEpisode, state.severeSince != nil, delivery.level > state.reservedLevel {
            state.severeSince = date
        }
        self[alert.kind] = state
    }

    private subscript(kind: Kind) -> KindState {
        get { kind == .memory ? memory : thermal }
        set {
            switch kind {
            case .memory: memory = newValue
            case .thermal: thermal = newValue
            }
        }
    }
}
