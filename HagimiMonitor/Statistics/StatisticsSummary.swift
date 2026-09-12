import Foundation

/// 概览与详情的聚合层:把范围序列里连续出现同类压力的桶合并成一段。
/// 只陈述观测事实,不引入实时规则引擎;段的状态判定见 StatisticsOverviewModel。
enum StatisticsSummary {
    /// 连续出现同一类压力的桶合并成的一段。
    struct Episode: Identifiable, Equatable {
        enum Kind: Equatable {
            case thermal
            case memory
        }

        let kind: Kind
        let start: Date
        let end: Date
        /// 该时段内的压力累计秒数(热 serious/critical、内存 warning/critical)。
        let pressureSeconds: Double

        var id: Date { start }

        /// 时段跨度(墙钟),与压力累计秒数分开:中断过的时段两者会不同。
        var spanSeconds: TimeInterval { end.timeIntervalSince(start) }
    }

    /// 从范围序列聚合成压力时段。相邻桶(间隔不超过一个桶宽)连续出现压力时
    /// 合并为一段;中断(桶缺失或压力为零)即断开,不跨缺口连接。
    static func episodes(from series: [StatisticsRow], bucketSeconds: TimeInterval) -> [Episode] {
        var episodes: [Episode] = []
        for kind in [Episode.Kind.thermal, .memory] {
            var runStart: Date?
            var runEnd: Date?
            var pressureSeconds = 0.0

            func flush() {
                if let start = runStart, let end = runEnd, pressureSeconds > 0 {
                    episodes.append(Episode(
                        kind: kind,
                        start: start,
                        end: end,
                        pressureSeconds: pressureSeconds
                    ))
                }
                runStart = nil
                runEnd = nil
                pressureSeconds = 0
            }

            for row in series {
                let pressure = kind == .thermal
                    ? (row.thSeriousS ?? 0) + (row.thCritS ?? 0)
                    : (row.memWarnS ?? 0) + (row.memCritS ?? 0)
                guard pressure > 0 else {
                    flush()
                    continue
                }
                let start = Date(timeIntervalSince1970: TimeInterval(row.t))
                if let previousEnd = runEnd, start.timeIntervalSince(previousEnd) > bucketSeconds {
                    // 与上一桶不连续(缺桶)时按新时段起算,不把缺口并在同一段里。
                    flush()
                }
                if runStart == nil {
                    runStart = start
                }
                runEnd = start.addingTimeInterval(bucketSeconds)
                pressureSeconds += pressure
            }
            flush()
        }
        return episodes.sorted { $0.start < $1.start }
    }
}
