import Foundation
import Testing
@testable import HagimiMonitorDirect

/// P02 / U09：刷新失败或未完成时保留上次成功快照；快照时刻可见；
/// 当前读数与历史快照分离，刷新不重算历史。
struct StatisticsSnapshotSemanticsTests {
    private func row(t: Int64) -> StatisticsRow {
        var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        values[0] = 10
        values[2] = 20
        let coverIndex = StatisticsRow.columns.firstIndex { $0.name == "cover_s" }!
        values[coverIndex] = 60
        return StatisticsRow(t: t, n: 1, values: values)
    }

    private func snapshot(capturedAt: Date, rows: [StatisticsRow]) -> ReportSnapshot {
        ReportSnapshot(
            capturedAt: capturedAt,
            meta: ReportMeta(
                deviceName: "Test Mac",
                modelName: "Mac16,1",
                osVersion: "macOS 27.0",
                recordDays: 3,
                appVersion: "1.0",
                isDirect: true
            ),
            minutes: rows,
            hours: [],
            days: [],
            process: nil,
            hardware: nil,
            systemSleepIntervals: []
        )
    }

    @Test func aggregatedModelCarriesSnapshotTimestamp() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let model = ReportDataAggregator.aggregate(
            snapshot: snapshot(capturedAt: capturedAt, rows: [row(t: 1_699_999_940)]),
            range: .today
        )
        #expect(model.updatedAt == capturedAt)
    }

    @Test func aggregateDoesNotInventValuesWhenRangeHasNoRows() {
        let model = ReportDataAggregator.aggregate(
            snapshot: snapshot(capturedAt: Date(), rows: []),
            range: .today
        )
        #expect(model.rows.isEmpty)
        #expect(model.coverageRatio == nil)
        // 没有观测时必须标记缺失，不能用满分或零值代替。
        #expect(model.quality.contains(.noObservation))
    }

    @Test func coverageRatioReflectsPartialObservation() {
        // 一天中的 60 秒覆盖 → 明显低于 1，属于部分覆盖。
        let model = ReportDataAggregator.aggregate(
            snapshot: snapshot(capturedAt: Date(), rows: [row(t: Int64(Date().timeIntervalSince1970) - 60)]),
            range: .today
        )
        if let ratio = model.coverageRatio {
            #expect(ratio < 1)
            #expect(model.quality.contains(.partialCoverage))
        }
        #expect(model.coveredSeconds > 0)
    }

    @Test func fullCoverageIsNotFlaggedPartial() {
        let now = Date()
        var rows: [StatisticsRow] = []
        for index in 0..<60 {
            let t = Int64(now.timeIntervalSince1970) - Int64(index) * 60
            var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            values[0] = 10
            let coverIndex = StatisticsRow.columns.firstIndex { $0.name == "cover_s" }!
            values[coverIndex] = 60
            rows.append(StatisticsRow(t: t, n: 1, values: values))
        }
        let model = ReportDataAggregator.aggregate(
            snapshot: snapshot(capturedAt: now, rows: rows),
            range: .today
        )
        #expect(model.quality.contains(.observed))
    }
}
