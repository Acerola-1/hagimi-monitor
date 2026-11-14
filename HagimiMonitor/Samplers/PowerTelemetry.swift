import Foundation

/// 数值只属于明确的观测区间；缓存显示保留首次观测的区间端点。
nonisolated struct PowerReading: Equatable, Sendable {
    enum State: String, Sendable { case valid, warmingUp, unavailable, frozen, unsupported, unverified }
    enum Source: String, Sendable { case energyModel, clpc, display, smc, registry, derived, unknown }
    let watts: Double?
    let state: State
    let source: Source
    let identity: String
    let intervalStart: TimeInterval
    let intervalEnd: TimeInterval
    var interval: TimeInterval { max(0, intervalEnd - intervalStart) }

    init(watts: Double? = nil, state: State, source: Source, identity: String = "",
         intervalStart: TimeInterval, intervalEnd: TimeInterval) {
        let valid = watts.map { $0.isFinite && $0 >= 0 } ?? false
        self.watts = state == .valid && valid ? watts : nil
        self.state = state == .valid && !valid ? .unavailable : state
        self.source = source
        self.identity = identity
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
    }

    static func missing(_ state: State, source: Source, at time: TimeInterval, identity: String = "") -> Self {
        Self(state: state, source: source, identity: identity, intervalStart: time, intervalEnd: time)
    }
}

nonisolated enum PowerEnergyUnit {
    /// IOReport 的常数、倒数、十进制与二进制缩放共同构成单位倍率。
    static func joulesPerCount(_ unit: UInt64) -> Double? {
        guard unit >> 56 == 3, unit & 0x00ff000000000000 == 0 else { return nil }
        let scale = unit & 0x00ffffffffffffff
        if scale == 0 { return 1 }
        let constant = Double(scale & 0x7fffffff)
        let reciprocal = scale & 0x80000000 != 0
        if reciprocal && constant == 0 { return nil }
        let si = Int((scale >> 32) & 0xff)
        let iec = Int((scale >> 40) & 0xff)
        let factor = (constant == 0 ? 1 : reciprocal ? 1 / constant : constant)
            * pow(10, Double(si == 0 ? 0 : si - 127))
            * pow(2, Double(iec == 0 ? 0 : iec - 127))
        return factor.isFinite && factor > 0 ? factor : nil
    }
}

nonisolated struct PowerEnergyCounter: Equatable, Sendable {
    let identity: String
    let value: Int64
    let joulesPerCount: Double
    let timestamp: UInt64
}

nonisolated enum PowerScreenActivity: String, Sendable { case active, inactive, unknown, absent }

/// 纯状态机：输入源时间戳与可控的单调观测时钟，测试无需等待真实时间。
nonisolated struct PowerCounterTracker: Sendable {
    static let freshness: TimeInterval = 5
    static let displayWindow: TimeInterval = 2
    static let maximumGap: TimeInterval = 30

    private struct Snapshot: Sendable {
        let counters: [PowerEnergyCounter]
        let time: TimeInterval
    }
    private var baseline: Snapshot?
    private var history: [Snapshot] = []
    private var identity = ""
    private var firstAt: TimeInterval?
    private var lastPollAt: TimeInterval?
    private var progressAt: TimeInterval?
    private var energyAt: TimeInterval?
    private var lastReading: PowerReading?
    private var interrupted = false
    private var sourceStalled = false
    private var awaitingEnergyUpdate = false
    private var everValid = false
    private var activity: PowerScreenActivity?
    private(set) var hasPositiveEvidence = false
    private(set) var consecutiveIntervals = 0
    var canSelect: Bool { consecutiveIntervals >= 2 && lastReading?.state == .valid }

    mutating func reset() { self = Self() }

    /// 换源保留本轮计数和已验证身份，功率从候选的新区间重新计算。
    mutating func rebaseForSelection() {
        history = baseline.map { [$0] } ?? []
        lastReading = nil
        everValid = false
        energyAt = nil
    }

    mutating func update(_ input: [PowerEnergyCounter]?, at time: TimeInterval,
                         source: PowerReading.Source, requiresPositiveEvidence: Bool = false,
                         screen: PowerScreenActivity? = nil, maximumWatts: Double = 1_000,
                         allowsUntimedGrowth: Bool = false) -> PowerReading {
        func missing(_ state: PowerReading.State) -> PowerReading {
            .missing(state, source: source, at: time, identity: identity)
        }
        guard time.isFinite else { return missing(.unavailable) }
        defer { lastPollAt = time }
        guard let input, !input.isEmpty,
              Set(input.map(\.identity)).count == input.count,
              input.allSatisfy({ $0.value >= 0 && ($0.timestamp > 0 || allowsUntimedGrowth) && $0.joulesPerCount.isFinite && $0.joulesPerCount > 0 }) else {
            baseline = nil
            history = []
            lastReading = nil
            consecutiveIntervals = 0
            interrupted = true
            return missing(.unavailable)
        }
        let counters = input.sorted { $0.identity < $1.identity }
        let newIdentity = counters.map { "\($0.identity):\($0.joulesPerCount):\(allowsUntimedGrowth)" }.joined(separator: "|")
        if newIdentity != identity || activity != screen {
            reset()
            identity = newIdentity
            activity = screen
        }
        if screen == .absent { return missing(.unsupported) }
        let current = Snapshot(counters: counters, time: time)
        if let lastPollAt, time <= lastPollAt || time - lastPollAt > Self.maximumGap {
            baseline = nil
            history = []
            interrupted = true
            consecutiveIntervals = 0
        }
        // CLPC 的部分驱动不发布源时间戳；该路径只按连续正增量出值，零值保持缺失状态。
        if allowsUntimedGrowth, let baseline,
           zip(baseline.counters, counters).contains(where: { $1.value == $0.value }) {
            interrupted = true
            lastReading = nil
            consecutiveIntervals = 0
            return missing(everValid ? .unavailable : time - (firstAt ?? time) < Self.freshness ? .warmingUp : .unverified)
        }
        if interrupted, let baseline {
            let unchanged = zip(baseline.counters, counters).allSatisfy { $0.timestamp == $1.timestamp && $0.value == $1.value }
            if unchanged {
                return missing(requiresPositiveEvidence && !hasPositiveEvidence ? .unverified : .frozen)
            }
        }
        if awaitingEnergyUpdate, let baseline {
            let unchangedEnergy = zip(baseline.counters, counters).allSatisfy { $0.value == $1.value }
            if unchangedEnergy {
                let advanced = zip(baseline.counters, counters).allSatisfy { $1.timestamp > $0.timestamp }
                if advanced {
                    progressAt = time
                    self.baseline = current
                }
                return missing(time - (progressAt ?? time) >= Self.freshness ? .frozen : .unavailable)
            }
            interrupted = true
            awaitingEnergyUpdate = false
        }
        guard let previous = baseline, !interrupted else {
            baseline = current
            history = [current]
            firstAt = time
            progressAt = time
            energyAt = nil
            interrupted = false
            sourceStalled = false
            lastReading = nil
            everValid = false
            return missing(.warmingUp)
        }
        var energy = 0.0
        var advanced = true
        for (old, new) in zip(previous.counters, counters) {
            let (delta, overflow) = new.value.subtractingReportingOverflow(old.value)
            guard !overflow, delta >= 0, new.timestamp >= old.timestamp,
                  !(!allowsUntimedGrowth && new.timestamp == old.timestamp && delta != 0) else {
                baseline = nil
                history = []
                interrupted = true
                consecutiveIntervals = 0
                return missing(.unavailable)
            }
            advanced = advanced && (allowsUntimedGrowth ? delta > 0 : new.timestamp > old.timestamp)
            energy += Double(delta) * new.joulesPerCount
        }
        let noProgressFor = time - (progressAt ?? previous.time)
        guard advanced else {
            consecutiveIntervals = 0
            if screen == nil && !allowsUntimedGrowth { sourceStalled = true }
            if noProgressFor >= Self.freshness {
                interrupted = true
                lastReading = nil
                return missing(requiresPositiveEvidence && !hasPositiveEvidence ? .unverified : .frozen)
            }
            if screen != nil, let lastReading, time - (energyAt ?? firstAt ?? time) < Self.freshness {
                return lastReading
            }
            return missing(everValid ? .unavailable : .warmingUp)
        }
        let elapsed = time - previous.time
        guard elapsed > 0, elapsed <= Self.maximumGap, energy.isFinite,
              energy / elapsed <= maximumWatts else {
            baseline = nil
            history = []
            interrupted = true
            consecutiveIntervals = 0
            return missing(.unavailable)
        }
        progressAt = time
        baseline = current
        consecutiveIntervals += 1
        if energy > 0 { hasPositiveEvidence = true }
        if screen == nil, sourceStalled {
            // 源时间戳停顿后的首次正增量可能包含此前积累，只用于重建基线。
            // 已准入源的时间戳继续前进而能量不变时，仍按健康零区间出值。
            history = [current]
            lastReading = nil
            sourceStalled = false
            everValid = false
            return missing(.warmingUp)
        }

        if let screen {
            if screen != .inactive, time - (energyAt ?? firstAt ?? time) >= Self.freshness {
                // 越过等待期限后的首次能量更新按延迟补报处理，先重建基线。
                history = [current]
                energyAt = energy > 0 ? time : nil
                lastReading = nil
                awaitingEnergyUpdate = energy == 0
                return missing(.unavailable)
            }
            if energy > 0 { energyAt = time }
            history.append(current)
            let anchor = history.last { time - $0.time >= Self.displayWindow }
            history = history.filter { time - $0.time <= Self.freshness }
            if energy == 0, screen != .inactive, let lastReading,
               time - (energyAt ?? firstAt ?? time) < Self.freshness { return lastReading }
            guard let anchor else { return missing(.warmingUp) }
            var windowEnergy = 0.0
            for (old, new) in zip(anchor.counters, counters) {
                let (delta, overflow) = new.value.subtractingReportingOverflow(old.value)
                guard !overflow, delta >= 0 else { return missing(.unavailable) }
                windowEnergy += Double(delta) * new.joulesPerCount
            }
            guard windowEnergy > 0 || screen == .inactive else {
                return missing(time - (firstAt ?? time) >= Self.freshness ? .unavailable : .warmingUp)
            }
            let watts = windowEnergy / (time - anchor.time)
            guard watts.isFinite, watts <= maximumWatts else { return missing(.unavailable) }
            let reading = PowerReading(watts: watts, state: .valid, source: source, identity: identity,
                                       intervalStart: anchor.time, intervalEnd: time)
            lastReading = reading
            everValid = true
            return reading
        }
        if requiresPositiveEvidence && !hasPositiveEvidence {
            consecutiveIntervals = 0
            return missing(time - (firstAt ?? time) >= Self.freshness ? .unverified : .warmingUp)
        }
        let reading = PowerReading(watts: energy / elapsed, state: .valid, source: source, identity: identity,
                                   intervalStart: previous.time, intervalEnd: time)
        lastReading = reading
        everValid = true
        return reading
    }
}

/// 候选分别预热；稳定可用后提升，短暂暂缺保持当前来源。
nonisolated struct PowerSourceSelector: Sendable {
    enum Selection: Sendable { case preferred, fallback }
    private(set) var selected: Selection?
    private var lastValidAt: TimeInterval?
    private var selectedIdentity: String?

    mutating func choose(preferred: PowerReading, preferredReady: Bool,
                         fallback: PowerReading, fallbackReady: Bool, at time: TimeInterval,
                         hardFailure: Bool = false) -> (selection: Selection?, changed: Bool) {
        let before = selected
        let previousIdentity = selectedIdentity
        if let selected {
            let current = selected == .preferred ? preferred : fallback
            if current.identity != selectedIdentity {
                self.selected = nil
                lastValidAt = nil
            }
        }
        if selected == nil {
            if preferredReady { selected = .preferred }
            else if fallbackReady { selected = .fallback }
        } else if selected == .fallback && preferredReady {
            selected = .preferred
        } else if selected == .preferred && !preferredReady,
                  hardFailure || time - (lastValidAt ?? time) >= PowerCounterTracker.freshness,
                  fallbackReady {
            selected = .fallback
        }
        guard let selected else { selectedIdentity = nil; return (nil, before != nil) }
        let reading = selected == .preferred ? preferred : fallback
        let changed = before != selected || previousIdentity != reading.identity
        selectedIdentity = reading.identity
        if changed || reading.state == .valid { lastValidAt = time }
        return (selected, changed)
    }
}

/// 失败重建使用当前采样循环的指数退避；订阅代次属于计数身份。
nonisolated struct PowerSubscriptionRecovery<Handle> {
    private(set) var handle: Handle?
    private(set) var generation: UInt64 = 0
    private var nextAttempt: TimeInterval = 0
    private var delay: TimeInterval = 1
    private var failures = 0

    mutating func sample<Value>(at time: TimeInterval, create: () -> Handle?, read: (Handle) -> Value?) -> Value? {
        if handle == nil {
            guard time >= nextAttempt else { return nil }
            guard let created = create() else {
                nextAttempt = time + delay
                delay = min(30, delay * 2)
                return nil
            }
            handle = created
            generation &+= 1
            failures = 0
            delay = 1
        }
        guard let handle else { return nil }
        guard let value = read(handle) else {
            failures += 1
            if failures >= 3 { invalidate(at: time) }
            return nil
        }
        failures = 0
        return value
    }

    mutating func invalidate(at time: TimeInterval) {
        handle = nil
        failures = 0
        nextAttempt = time + delay
        delay = min(30, delay * 2)
    }
}
