import Foundation

/// 统计摘要的展示模型:把已记录的数据折成「当前状态」「范围结论」「事件摘要」。
/// 只做展示口径归并,不引入新的评估规则;事件由已记录的档位秒数聚合,
/// 状态区分 持续中 / 已恢复 / 观测中断——观测中断后不宣称恢复,
/// 持续时间只统计已观测到的部分(模型 §5)。
/// 「当前状态」暂不在摘要页展示,保留为后续状态告警的公共证据层。
enum StatisticsOverviewModel {
    /// 「当前」的新鲜度阈值:超过这段时间没有新观测,不再陈述实时状态。
    static let currentFreshness: TimeInterval = 5 * 60

    // MARK: - 当前状态

    struct CurrentStatus: Equatable {
        /// 最后一条观测所在桶的结束时刻。
        let observedAt: Date
        /// 观测是否足够新鲜(不新鲜时只能陈述「最后观测到」)。
        let isFresh: Bool
        /// 最后观测到的内存压力档位(nil = 该维度无有效观测)。
        let memoryLevel: Int?
        /// 最后观测到的系统热状态档位(nil = 该维度无有效观测)。
        let thermalLevel: Int?

        var hasAnyLevel: Bool { memoryLevel != nil || thermalLevel != nil }
    }

    /// 从最新一行分钟记录取当前状态;无记录返回 nil。
    static func currentStatus(
        latest: StatisticsRow?,
        now: Date,
        bucketSeconds: TimeInterval = 60
    ) -> CurrentStatus? {
        guard let latest else { return nil }
        let observedAt = Date(timeIntervalSince1970: TimeInterval(latest.t) + bucketSeconds)
        return CurrentStatus(
            observedAt: observedAt,
            isFresh: now.timeIntervalSince(observedAt) <= currentFreshness,
            memoryLevel: dominantMemoryLevel(latest),
            thermalLevel: dominantThermalLevel(latest)
        )
    }

    /// 桶内任一档位有秒数即取最严重档:最后一段观测里出现过压力,就按出现过陈述。
    static func dominantMemoryLevel(_ row: StatisticsRow) -> Int? {
        if (row.memCritS ?? 0) > 0 { return 2 }
        if (row.memWarnS ?? 0) > 0 { return 1 }
        if (row.memNormalS ?? 0) > 0 { return 0 }
        return nil
    }

    static func dominantThermalLevel(_ row: StatisticsRow) -> Int? {
        if (row.thCritS ?? 0) > 0 { return 3 }
        if (row.thSeriousS ?? 0) > 0 { return 2 }
        if (row.thFairS ?? 0) > 0 { return 1 }
        if (row.thNominalS ?? 0) > 0 { return 0 }
        return nil
    }

    // MARK: - 事件

    struct Event: Identifiable, Equatable {
        enum Kind: Equatable {
            case thermal
            case memory
        }

        /// 持续中 = 压力延伸到范围末尾的观测且观测新鲜;已恢复 = 其后有观测且无压力;
        /// 观测中断 = 压力之后没有新观测,既不能确认持续,也不能宣称恢复。
        enum State: Equatable {
            case ongoing
            case recovered
            case interrupted
        }

        let kind: Kind
        let start: Date
        let end: Date
        /// 已观测到的压力累计秒数(不含中断缺口)。
        let pressureSeconds: Double
        let state: State

        var id: Date { start }
        var spanSeconds: TimeInterval { end.timeIntervalSince(start) }
    }

    /// 事件聚合:连续桶合并为一段;状态按「压力结束时点之后是否还有观测」与
    /// 观测新鲜度判定,不把中断说成恢复。
    static func events(
        from series: [StatisticsRow],
        bucketSeconds: TimeInterval,
        now: Date
    ) -> [Event] {
        let raw = StatisticsSummary.episodes(from: series, bucketSeconds: bucketSeconds)
        guard !raw.isEmpty else { return [] }
        let observationEnds = series.compactMap { row -> Date? in
            let hasObservation = (row.validMemS ?? 0) > 0 || (row.validThermalS ?? 0) > 0
            guard hasObservation else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(row.t) + bucketSeconds)
        }
        guard let lastObservedEnd = observationEnds.max() else { return [] }
        let observationIsFresh = now.timeIntervalSince(lastObservedEnd) <= currentFreshness

        return raw.map { episode in
            let state: Event.State
            if episode.end >= lastObservedEnd {
                state = observationIsFresh ? .ongoing : .interrupted
            } else {
                state = .recovered
            }
            return Event(
                kind: episode.kind == .thermal ? .thermal : .memory,
                start: episode.start,
                end: episode.end,
                pressureSeconds: episode.pressureSeconds,
                state: state
            )
        }
    }

    // MARK: - 序列桶宽

    /// 记录器能产出的最粗桶粒度(小时层):相邻桶间隔不会比它更大,超过即视为缺口。
    private static let hourBucketSeconds: TimeInterval = 3600

    /// 从序列推断桶宽,供 episode 合并与时段起止按同一宽度计算。
    /// 取相邻桶间隔里最小的那个,不取首两桶之差——首两桶之间可能横跨采样缺口
    /// (睡眠、退出、刚装上),把缺口当桶宽会把缺口并进同一段、抬高时段结束点,
    /// 使早已恢复的压力被判成持续中。全是缺口(不足一个相邻对)时退回范围默认粒度。
    static func bucketSeconds(for range: StatisticsOverviewRange, series: [StatisticsRow]) -> TimeInterval {
        let smallest = zip(series, series.dropFirst())
            .map { TimeInterval($1.t - $0.t) }
            .filter { $0 > 0 }
            .min()
        if let smallest, smallest <= hourBucketSeconds { return smallest }
        return range == .today ? 60 : hourBucketSeconds
    }

    // MARK: - 内存压力行的取值口径

    /// 设置页「内存压力」行的四种取值:无有效观测 / 有压力累计 / 记录不足 / 正常。
    /// 记录不足不写成「正常」,与范围结论共用同一门控,避免两处口径打架。
    enum MemoryPressureStatus: Equatable {
        case noObservation
        case pressure(seconds: Double)
        case insufficient
        case normal
    }

    static func memoryPressureStatus(_ row: StatisticsRow) -> MemoryPressureStatus {
        guard (row.validMemS ?? 0) > 0 else { return .noObservation }
        let pressure = (row.memWarnS ?? 0) + (row.memCritS ?? 0)
        if pressure > 0 { return .pressure(seconds: pressure) }
        guard hasSufficientObservation(row) else { return .insufficient }
        return .normal
    }

    // MARK: - 范围结论

    enum Conclusion: Equatable {
        /// 还没有任何记录(首次启动或该范围无数据)。
        case noObservation
        /// 记录时间不足,不足以判断范围内是否有压力。
        case insufficient(recordedSeconds: Double)
        /// 观测充分且未发现压力。
        case quiet(recordedSeconds: Double)
        /// 发现压力事件;leading 为最值得先看的一条。
        case events(leading: Event, additionalCount: Int, recordedSeconds: Double)
    }

    /// 范围结论只陈述该范围内已观测到的事实,不代替「当前状态」。
    /// 有事件时优先陈述事件(存在可用结论即不因覆盖不足而隐藏)。
    static func conclusion(row: StatisticsRow?, events: [Event]) -> Conclusion {
        guard let row, let recorded = row.coverS, recorded > 0 else { return .noObservation }
        if !events.isEmpty, let leading = leadingEvent(events) {
            return .events(leading: leading, additionalCount: events.count - 1, recordedSeconds: recorded)
        }
        guard hasSufficientObservation(row) else { return .insufficient(recordedSeconds: recorded) }
        return .quiet(recordedSeconds: recorded)
    }

    /// 事件状态的优先次序:持续中 > 观测中断 > 已恢复。
    static func statePriority(_ state: Event.State) -> Int {
        switch state {
        case .ongoing: return 0
        case .interrupted: return 1
        case .recovered: return 2
        }
    }

    /// 最值得先看的事件:状态优先,同级取时长更长者。
    static func leadingEvent(_ events: [Event]) -> Event? {
        events.min { lhs, rhs in
            let lhsPriority = statePriority(lhs.state)
            let rhsPriority = statePriority(rhs.state)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.pressureSeconds > rhs.pressureSeconds
        }
    }

    /// 某个非正常档位在该维度内的累计秒数。
    struct PressureLevel: Equatable {
        /// 原生档位序号(内存 1=警告、2=严重;热状态 1=轻微、2=严重、3=临界)。
        let level: Int
        let seconds: Double
    }

    /// 按维度归并的压力概览:该维度的压力累计秒数、档位组成与最近一次事件的状态。
    /// 秒数与档位优先取聚合行(与指标行同口径、不会两处对不上);聚合行没有而序列里
    /// 有事件时退到事件累计(此时没有档位信息,不编造)。排序与事件一致:
    /// 最值得先看的一类排在最前。
    struct PressureKind: Equatable {
        let kind: Event.Kind
        let seconds: Double
        /// 非正常档位组成,按严重度从高到低;空数组表示没有档位信息(旧记录)。
        let levels: [PressureLevel]
        let state: Event.State

        /// 达到过的最高档位。
        var worstLevel: PressureLevel? { levels.first }
    }

    /// 某维度在聚合行里的非正常档位组成,按严重度从高到低。
    /// 只读已记录的档位秒数;旧记录没有档位列时返回空数组,不编造档位。
    static func pressureLevels(of kind: Event.Kind, row: StatisticsRow?) -> [PressureLevel] {
        let pairs: [(level: Int, seconds: Double)]
        switch kind {
        case .memory:
            pairs = [(2, row?.memCritS ?? 0), (1, row?.memWarnS ?? 0)]
        case .thermal:
            pairs = [(3, row?.thCritS ?? 0), (2, row?.thSeriousS ?? 0), (1, row?.thFairS ?? 0)]
        }
        return pairs.filter { $0.seconds > 0 }.map { PressureLevel(level: $0.level, seconds: $0.seconds) }
    }

    static func pressureKinds(row: StatisticsRow?, events: [Event]) -> [PressureKind] {
        func latestState(of kind: Event.Kind) -> Event.State? {
            events.filter { $0.kind == kind }.max { $0.start < $1.start }?.state
        }
        func eventSeconds(of kind: Event.Kind) -> Double {
            events.filter { $0.kind == kind }.reduce(0) { $0 + $1.pressureSeconds }
        }

        func seconds(of kind: Event.Kind, rowValue: Double) -> Double {
            rowValue > 0 ? rowValue : eventSeconds(of: kind)
        }

        func levels(of kind: Event.Kind) -> [PressureLevel] {
            pressureLevels(of: kind, row: row)
        }

        var kinds: [PressureKind] = []
        let memory = seconds(of: .memory, rowValue: (row?.memWarnS ?? 0) + (row?.memCritS ?? 0))
        if let state = latestState(of: .memory), memory > 0 {
            kinds.append(PressureKind(kind: .memory, seconds: memory, levels: levels(of: .memory), state: state))
        }
        let thermal = seconds(of: .thermal, rowValue: (row?.thSeriousS ?? 0) + (row?.thCritS ?? 0))
        if let state = latestState(of: .thermal), thermal > 0 {
            kinds.append(PressureKind(kind: .thermal, seconds: thermal, levels: levels(of: .thermal), state: state))
        }
        return kinds.sorted { lhs, rhs in
            let lhsPriority = statePriority(lhs.state)
            let rhsPriority = statePriority(rhs.state)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.seconds > rhs.seconds
        }
    }

    /// 记录是否足以判断范围结论:与评分门控同一口径(交集 ≥30 分钟且 ≥90% 覆盖)。
    static func hasSufficientObservation(_ row: StatisticsRow) -> Bool {
        let intersection = row.validMemThermalS ?? 0
        guard intersection >= StatisticsHealthScore.minIntersectionSeconds else { return false }
        let covered = row.coverS ?? 0
        if covered > 0, intersection < covered * StatisticsHealthScore.minCoverageRatio { return false }
        return true
    }
}
