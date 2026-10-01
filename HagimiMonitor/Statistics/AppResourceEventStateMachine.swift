import Foundation

/// 应用资源高占用事件的纯状态机。
///
/// 基于有效覆盖区间累计高占用时长：相邻有效观测之间的间隔计入覆盖时间，
/// 超过 maxGap 视为连续性丢失并判定为中断；恢复需由低于门槛的有效观测确认。
/// 时间参数由调用方注入，支持确定性测试。
nonisolated enum AppResourceEventStateMachine {

    /// 单次观测的性质。
    enum Signal: Sendable, Equatable {
        /// 有效的高于门槛观测。
        case high(value: Double)
        /// 有效且可靠地低于门槛的观测。
        case low(value: Double)
        /// 未入榜、采样失败或来源暂时不可用：既不是高也不是低。
        case unknown
        /// 明确的结束（进程退出、睡眠、关闭记录、重启、PID 复用）。
        case ended(reason: EndReason)
    }

    /// 单次观测的输入。
    struct Observation: Sendable, Equatable {
        let signal: Signal
        let at: Date
        /// 来源给出的真实覆盖区间；瞬时样本为 nil，此时只能靠相邻观测间隔估算。
        let coveredInterval: DateInterval?

        init(signal: Signal, at: Date, coveredInterval: DateInterval? = nil) {
            self.signal = signal
            self.at = at
            self.coveredInterval = coveredInterval
        }
    }

    /// 结束原因，共用 ProcessAlertEpisode.EndReason 定义。
    typealias EndReason = ProcessAlertEpisode.EndReason

    /// 默认允许的观测最大间隔（秒）：用于瞬时证据。
    /// 有明确覆盖区间的来源不受此限制，直接采用区间长度。
    static let defaultMaxGapSeconds: TimeInterval = 90

    /// 默认持续资格（秒）：连续有效高占用达到该值才算确认事件。
    static let defaultSustainedSeconds: TimeInterval = 120

    /// 一段被有效覆盖的高占用区间，供跨范围查询时按区间精确裁剪时长与均值。
    struct CoveredSegment: Sendable, Equatable {
        let start: Date
        let end: Date
        /// 该段的均值（同段内按有效秒数加权）。
        let averageValue: Double

        var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    /// 一个指标的事件累积状态。
    struct State: Sendable, Equatable {
        /// 当前连续段是否为高占用中。
        var isRunning = false
        /// 本连续段内累计的有效高占用秒数。
        var continuousHighSeconds: TimeInterval = 0
        /// 事件跨度起点（首次有效高值时刻）。
        var startedAt: Date?
        /// 最后一次有效高值观测的覆盖终点，用于确定结束端点。
        var lastHighAt: Date?
        /// 加权均值用的分子：Σ(值 × 有效秒数)。
        var weightedSum: Double = 0
        /// 加权均值用的分母：Σ(有效秒数)。
        var weightedSeconds: TimeInterval = 0
        var peakUsage: Double = 0
        /// 高占用观测次数。
        var highObservationCount = 0
        /// 有效覆盖分段，供按范围精确裁剪。
        var segments: [CoveredSegment] = []
        /// 各档位在有效覆盖内的秒数（下标 1...3 对应档位 1–3）。
        var tierSeconds: [TimeInterval] = [0, 0, 0, 0]
        /// 是否已确认（达到持续资格）。
        var isConfirmed = false

        var averageUsage: Double {
            weightedSeconds > 0 ? weightedSum / weightedSeconds : 0
        }
    }

    /// 一次状态转换的结果。
    struct Transition: Sendable, Equatable {
        var state: State
        /// 本次确认结束（达到过持续资格）时产生的事件。
        var finishedEvent: Outcome?
        /// 状态是否因此改变（用于决定是否发布）。
        var didChange: Bool
    }

    /// 结束的事件摘要。
    struct Outcome: Sendable, Equatable {
        let startedAt: Date
        let endedAt: Date
        let reason: EndReason
        let continuousHighSeconds: TimeInterval
        /// 首末观测时间跨度。
        let eventSpanSeconds: TimeInterval
        let averageUsage: Double
        let peakUsage: Double
        let highObservationCount: Int
        /// 是否曾达到持续资格。
        let wasConfirmed: Bool
        /// 有效覆盖分段。
        var segments: [CoveredSegment] = []
        /// 各档位有效秒数（下标 1...3）。
        var tierSeconds: [TimeInterval] = [0, 0, 0, 0]
    }

    /// 消费一次观测。
    ///
    /// - Parameters:
    ///   - state: 该 (应用, 指标) 的当前状态；首次传 `.init()`。
    ///   - observation: 本次观测。
    ///   - maxGapSeconds: 允许的观测最大间隔，仅对无明确区间的瞬时证据生效。
    ///   - sustainedSeconds: 持续资格门槛。
    static func reduce(
        state: State,
        observation: Observation,
        maxGapSeconds: TimeInterval = defaultMaxGapSeconds,
        sustainedSeconds: TimeInterval = defaultSustainedSeconds
    ) -> Transition {
        switch observation.signal {
        case .high(let value):
            return handleHigh(
                state: state,
                value: value,
                observation: observation,
                maxGapSeconds: maxGapSeconds,
                sustainedSeconds: sustainedSeconds
            )

        case .low:
            // 确认恢复，结束端点取最后一次有效高占用观测时刻。
            return finish(
                state: state,
                at: state.lastHighAt ?? observation.at,
                reason: .recovered,
                spanEnd: state.lastHighAt ?? observation.at
            )

        case .unknown:
            guard state.isRunning else { return Transition(state: state, finishedEvent: nil, didChange: false) }
            // 未知不累计秒数；超过允许间隔判定为中断。
            guard let lastHigh = state.lastHighAt,
                  observation.at.timeIntervalSince(lastHigh) > maxGapSeconds else {
                return Transition(state: state, finishedEvent: nil, didChange: false)
            }
            return finish(state: state, at: lastHigh, reason: .observationGap, spanEnd: lastHigh)

        case .ended(let reason):
            guard state.isRunning else { return Transition(state: state, finishedEvent: nil, didChange: false) }
            let end = state.lastHighAt ?? observation.at
            return finish(state: state, at: end, reason: reason, spanEnd: end)
        }
    }

    private static func handleHigh(
        state: State,
        value: Double,
        observation: Observation,
        maxGapSeconds: TimeInterval,
        sustainedSeconds: TimeInterval
    ) -> Transition {
        var next = state
        var finished: Outcome?

        if state.isRunning, let lastHigh = state.lastHighAt {
            // 与上一有效高观测的间隔：有明确区间就用区间长度，否则用观测间隔估算。
            let gap: TimeInterval
            if let interval = observation.coveredInterval {
                gap = interval.duration
            } else {
                gap = observation.at.timeIntervalSince(lastHigh)
            }

            if gap > maxGapSeconds {
                // 连续性丢失：旧事件判定为中断，本次观测开启新基线。
                let outcome = makeOutcome(state: state, endedAt: lastHigh, reason: .observationGap,
                                          spanStart: state.startedAt ?? lastHigh)
                finished = outcome?.wasConfirmed == true ? outcome : nil
                next = State()
                next.isRunning = true
                next.startedAt = observation.at
                next.lastHighAt = observation.at
                next.isConfirmed = false
                // 首个样本不计入前序覆盖时长。
                return accumulate(&next, value: value, at: observation.at, seconds: 0,
                                  sustainedSeconds: sustainedSeconds, didChange: true, finished: finished)
            }

            let contribution = min(max(0, gap), maxGapSeconds)
            return accumulate(&next, value: value, at: observation.at, seconds: contribution,
                              sustainedSeconds: sustainedSeconds, didChange: true, finished: nil)
        }

        // 建立新事件基线。
        next.isRunning = true
        next.startedAt = observation.at
        next.lastHighAt = observation.at
        next.isConfirmed = false
        return accumulate(&next, value: value, at: observation.at, seconds: 0,
                          sustainedSeconds: sustainedSeconds, didChange: true, finished: nil)
    }

    private static func accumulate(
        _ state: inout State,
        value: Double,
        at date: Date,
        seconds: TimeInterval,
        sustainedSeconds: TimeInterval,
        didChange: Bool,
        finished: Outcome?
    ) -> Transition {
        state.highObservationCount += 1
        state.peakUsage = max(state.peakUsage, value)
        // 推进最后有效高观测时刻。
        state.lastHighAt = max(state.lastHighAt ?? .distantPast, date)
        if seconds > 0 {
            state.continuousHighSeconds += seconds
            // 按覆盖时长加权计入均值。
            state.weightedSum += value * seconds
            state.weightedSeconds += seconds
        }
        if seconds > 0 {
            // 分段记录本次覆盖区间，供范围内精确裁剪。
            state.segments.append(CoveredSegment(
                start: date.addingTimeInterval(-seconds),
                end: date,
                averageValue: value
            ))
        }
        if state.continuousHighSeconds >= sustainedSeconds {
            state.isConfirmed = true
        }
        return Transition(state: state, finishedEvent: finished, didChange: didChange)
    }

    private static func finish(
        state: State,
        at end: Date,
        reason: EndReason,
        spanEnd: Date
    ) -> Transition {
        let outcome = makeOutcome(state: state, endedAt: end, reason: reason,
                                  spanStart: state.startedAt ?? end)
        var cleared = State()
        cleared.isRunning = false
        // 保留已经产生过的统计值，便于调用方在确认结束前读取最终均值/峰值。
        cleared.continuousHighSeconds = state.continuousHighSeconds
        cleared.startedAt = state.startedAt
        cleared.lastHighAt = state.lastHighAt
        cleared.weightedSum = state.weightedSum
        cleared.weightedSeconds = state.weightedSeconds
        cleared.peakUsage = state.peakUsage
        cleared.highObservationCount = state.highObservationCount
        cleared.segments = state.segments
        cleared.isConfirmed = state.isConfirmed
        let didChange = state.isRunning || state.continuousHighSeconds > 0
        // 仅在达到持续资格时报告完成事件。
        let reported = outcome?.wasConfirmed == true ? outcome : nil
        return Transition(state: cleared, finishedEvent: reported, didChange: didChange)
    }

    private static func makeOutcome(
        state: State,
        endedAt: Date,
        reason: EndReason,
        spanStart: Date
    ) -> Outcome? {
        guard let startedAt = state.startedAt else { return nil }
        let span = max(0, endedAt.timeIntervalSince(spanStart))
        return Outcome(
            startedAt: startedAt,
            endedAt: endedAt,
            reason: reason,
            continuousHighSeconds: state.continuousHighSeconds,
            eventSpanSeconds: span == 0 ? state.continuousHighSeconds : span,
            averageUsage: state.averageUsage,
            peakUsage: state.peakUsage,
            highObservationCount: state.highObservationCount,
            wasConfirmed: state.isConfirmed,
            segments: state.segments
        )
    }

    /// 把分段裁剪到 [from, to) 并重新汇总。
    /// 返回范围内的有效秒数、按秒加权的均值与峰值；若无有效分段返回 nil。
    static func clipSegments(
        _ segments: [CoveredSegment],
        from: Date,
        to: Date
    ) -> (seconds: TimeInterval, averageValue: Double, peak: Double)? {
        var totalSeconds: TimeInterval = 0
        var weightedSum: Double = 0
        var peak = 0.0
        for segment in segments {
            let start = max(segment.start, from)
            let end = min(segment.end, to)
            let seconds = end.timeIntervalSince(start)
            guard seconds > 0 else { continue }
            totalSeconds += seconds
            weightedSum += segment.averageValue * seconds
            peak = max(peak, segment.averageValue)
        }
        guard totalSeconds > 0 else { return nil }
        return (totalSeconds, weightedSum / totalSeconds, peak)
    }

    /// 计算多个时间区间的并集时长，重叠部分不重复计算。
    static func unionSeconds(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return 0 }

        var total: TimeInterval = 0
        var currentStart = sorted[0].start
        var currentEnd = sorted[0].end
        for interval in sorted.dropFirst() {
            if interval.start <= currentEnd {
                currentEnd = max(currentEnd, interval.end)
            } else {
                total += currentEnd.timeIntervalSince(currentStart)
                currentStart = interval.start
                currentEnd = interval.end
            }
        }
        total += currentEnd.timeIntervalSince(currentStart)
        return total
    }
}
