import Foundation
import Testing
@testable import HagimiMonitorDirect

/// R04 / 6.5：来源选择必须让旧/新观测不重复计入。
///
/// 粒度选择是「本期用哪一层数据」的唯一决定点：分钟可用就用分钟，否则退到小时，
/// 再退到日汇总。这保证同一批观测只被其中一层消费，不会把日汇总和小时行叠加。
struct ReportSourceSelectionTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func row(_ t: Int64) -> StatisticsRow {
        var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        values[0] = 10
        return StatisticsRow(t: t, n: 1, values: values)
    }

    private func minutesAround(_ date: Date, count: Int = 60) -> [StatisticsRow] {
        (0..<count).map { row(Int64(date.timeIntervalSince1970) - Int64($0) * 60) }
    }

    private func hoursAround(_ date: Date, count: Int = 24) -> [StatisticsRow] {
        (0..<count).map { row(Int64(date.timeIntervalSince1970) - Int64($0) * 3600) }
    }

    @Test func shortRangeWithFreshMinutesUsesMinutesOnly() {
        let from = t0.addingTimeInterval(-2 * 3600)
        let to = t0
        let granularity = ReportDataAggregator.pickSource(
            from: from, to: to,
            minutes: minutesAround(t0, count: 180),
            hours: hoursAround(t0),
            days: [row(Int64(t0.timeIntervalSince1970) - 86400)]
        )
        #expect(granularity == .minutes)
    }

    @Test func shortRangeWithoutMinutesFallsBackToHours() {
        let from = t0.addingTimeInterval(-2 * 3600)
        let to = t0
        let granularity = ReportDataAggregator.pickSource(
            from: from, to: to,
            minutes: [],
            hours: hoursAround(t0),
            days: [row(Int64(t0.timeIntervalSince1970) - 86400)]
        )
        // 没有分钟数据时不会跳到日汇总，而是退到小时。
        #expect(granularity == .hours)
    }

    @Test func longRangeUsesDaysAndIgnoresHours() {
        let from = t0.addingTimeInterval(-90 * 86400)
        let to = t0
        let granularity = ReportDataAggregator.pickSource(
            from: from, to: to,
            minutes: minutesAround(t0, count: 10),
            hours: hoursAround(t0, count: 48),
            days: (0..<90).map { row(Int64(t0.timeIntervalSince1970) - Int64($0) * 86400) }
        )
        // 90 天超出小时层覆盖范围，必须用日汇总，避免只算到部分天数。
        #expect(granularity == .days)
    }

    @Test func staleMinutesForOldRangeDoNotWin() {
        // 分钟数据很旧（只覆盖最近两小时），查询更早的范围时不能选分钟，
        // 否则会得到「本期几乎为空」的假象。
        let from = t0.addingTimeInterval(-20 * 86400)
        let to = t0.addingTimeInterval(-19 * 86400)
        let granularity = ReportDataAggregator.pickSource(
            from: from, to: to,
            minutes: minutesAround(t0, count: 120),
            hours: hoursAround(t0, count: 24 * 30),
            days: (0..<30).map { row(Int64(t0.timeIntervalSince1970) - Int64($0) * 86400) }
        )
        #expect(granularity != .minutes)
    }

    @Test func emptyEverythingStillPicksADeterministicSource() {
        let granularity = ReportDataAggregator.pickSource(
            from: t0.addingTimeInterval(-3600), to: t0,
            minutes: [], hours: [], days: []
        )
        // 无数据时返回确定性结果（不崩溃、不随机），由上层显示空状态。
        #expect(granularity == .days)
    }
}
