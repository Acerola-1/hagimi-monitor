import Foundation

/// 同期系统压力快照，供应用告警通知结合系统承压证据进行发送决策。
nonisolated struct SystemPressureSnapshot: Sendable, Equatable {
    /// 内存压力档位（0 正常，1 警告，2 严重…）。
    var memoryLevel: Int
    /// 热压力档位。
    var thermalLevel: Int
    /// 两项观测是否有效。无效表示没有可靠证据，不能据此判定「压力正常」。
    var hasValidObservation: Bool

    init(memoryLevel: Int = 0, thermalLevel: Int = 0, hasValidObservation: Bool = false) {
        self.memoryLevel = memoryLevel
        self.thermalLevel = thermalLevel
        self.hasValidObservation = hasValidObservation
    }

    static let unknown = SystemPressureSnapshot()

    /// 同期是否存在有效压力（任一路达到警告及以上）。
    var hasElevatedPressure: Bool {
        hasValidObservation && (memoryLevel >= 1 || thermalLevel >= 1)
    }

    /// 同期压力的严重度：0 正常、1 警告、2 及以上严重。
    var severity: Int {
        max(memoryLevel, thermalLevel)
    }
}

/// 应用高占用通知的决策策略。
nonisolated enum AppAlertNotificationPolicy: Sendable {

    enum Decision: Sendable, Equatable {
        /// 发送新通知。
        case send(tier: Int)
        /// 同一事件内严重度升级，发送更新。
        case update(tier: Int)
        /// 不发送。
        case skip(reason: SkipReason)
    }

    enum SkipReason: Sendable, Equatable {
        /// 用户关闭了通知总开关。
        case notificationsDisabled
        /// 未达到持续资格。
        case belowSustainThreshold
        /// 同期没有有效的系统压力证据。
        case noConcurrentSystemPressure
        /// 同一事件内已经通知过且严重度未升级。
        case alreadyNotified
    }

    /// 判定是否发送。
    ///
    /// - Parameters:
    ///   - notificationsEnabled: 用户的通知总开关。
    ///   - isConfirmed: 事件是否已达到持续资格。
    ///   - systemPressure: 同期的系统压力证据。
    ///   - tier: 本次事件的严重度档位（由指标与超出程度决定）。
    ///   - alreadyNotifiedTier: 该应用本次事件内已通知过的档位；未通知过为 nil。
    static func decide(
        notificationsEnabled: Bool,
        isConfirmed: Bool,
        systemPressure: SystemPressureSnapshot,
        tier: Int,
        alreadyNotifiedTier: Int?
    ) -> Decision {
        guard notificationsEnabled else { return .skip(reason: .notificationsDisabled) }
        guard isConfirmed else { return .skip(reason: .belowSustainThreshold) }
        // 仅在存在同期有效系统压力时发送通知。
        guard systemPressure.hasElevatedPressure else {
            return .skip(reason: .noConcurrentSystemPressure)
        }
        guard let previous = alreadyNotifiedTier else { return .send(tier: tier) }
        // 仅在严重度升级时发送更新通知。
        guard tier > previous else { return .skip(reason: .alreadyNotified) }
        return .update(tier: tier)
    }

    /// 事件严重度档位，由指标超出程度计算。
    static func tier(metric: ProcessAlertEpisode.Metric, rawValue: Double) -> Int {
        let definition: StatisticsMetricDefinition.Metric = switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        }
        guard let threshold = StatisticsMetricDefinition.attentionThreshold(
            for: definition,
            physicalMemoryBytes: metric == .memory ? StatisticsMetricDefinition.physicalMemoryBytes() : nil
        ), threshold.value > 0 else {
            return 1
        }
        // 超出门槛 2 倍以上计为更高档位。
        return rawValue >= threshold.value * 2 ? 2 : 1
    }
}
