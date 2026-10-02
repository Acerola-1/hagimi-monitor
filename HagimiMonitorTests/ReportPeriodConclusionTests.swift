import Foundation
import Testing
@testable import HagimiMonitorDirect

/// U09：总览先给结论，且区分历史时段结论与当前状态；评分不足不回退成满分。
struct ReportPeriodConclusionTests {
    private func event(_ kind: ReportEventItem.Kind, level: Int = 1) -> ReportEventItem {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return ReportEventItem(
            id: "\(kind)-\(level)",
            kind: kind,
            state: .recovered,
            start: start,
            end: start.addingTimeInterval(600),
            pressureSeconds: 600,
            worstLevel: level,
            detailText: ""
        )
    }

    @Test func highAppUsageWithLowPressureIsNotAFalseAlarm() {
        let summary = ReportPeriodConclusion.summary(
            events: [],
            appAlertCount: 2,
            coveredSeconds: 6 * 3600,
            quality: [.observed]
        )
        #expect(summary.kind == .calm)
        #expect(summary.isElevated == false)
        // 高占用应用作为补充出现，但不改变结论语气。
        #expect(summary.detail?.contains("2") == true)
    }

    @Test func systemPressureIsElevatedAndCountsEpisodes() {
        let summary = ReportPeriodConclusion.summary(
            events: [event(.memory), event(.memory), event(.thermal)],
            appAlertCount: 1,
            coveredSeconds: 6 * 3600,
            quality: [.observed]
        )
        #expect(summary.kind == .pressure)
        #expect(summary.isElevated)
        #expect(summary.detail?.contains("3") == true)
    }

    @Test func insufficientObservationDoesNotPretendToBeCalm() {
        let summary = ReportPeriodConclusion.summary(
            events: [],
            appAlertCount: 0,
            coveredSeconds: 5 * 60,
            quality: [.observed]
        )
        #expect(summary.kind == .insufficient)
        #expect(summary.isElevated == false)
    }

    @Test func noObservationIsDistinctFromInsufficient() {
        let summary = ReportPeriodConclusion.summary(
            events: [],
            appAlertCount: 0,
            coveredSeconds: 0,
            quality: [.noObservation]
        )
        #expect(summary.kind == .noObservation)
        #expect(summary.detail?.isEmpty == false)
    }

    @Test func legacyDailyQualityIsDisclosedInConclusion() {
        let summary = ReportPeriodConclusion.summary(
            events: [],
            appAlertCount: 0,
            coveredSeconds: 24 * 3600,
            quality: [.observed, .legacyDailyEstimate]
        )
        #expect(summary.kind == .calm)
        #expect(summary.detail?.isEmpty == false)
    }

    @Test func pressureConclusionStaysElevatedEvenWithPartialCoverage() {
        let summary = ReportPeriodConclusion.summary(
            events: [event(.thermal, level: 3)],
            appAlertCount: 0,
            coveredSeconds: 3600,
            quality: [.observed, .partialCoverage]
        )
        #expect(summary.kind == .pressure)
        #expect(summary.isElevated)
        // 覆盖限制仍然要说明，不能因为出现压力就隐去。
        #expect(summary.detail?.isEmpty == false)
    }
}
