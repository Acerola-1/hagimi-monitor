import Foundation
import Testing
@testable import HagimiMonitorDirect

/// S05 / S06：范围删除联动事件；打卡按既有语义保留；两个目录互不影响。
/// S04：事件保留与日汇总同口径，早于保留窗口的事件被清理。
struct StatisticsStoreDeletionTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> (StatisticsProcessStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (StatisticsProcessStore(directory: directory), directory)
    }

    private func event(id: String, start: Date, end: Date, appKey: String = "bundle:com.example.App") -> PersistedAppEvent {
        PersistedAppEvent(
            eventID: id, appKey: appKey, name: "App", metric: "cpu",
            startedAt: start, endedAt: end, lastEffectiveAt: end,
            continuousHighSeconds: end.timeIntervalSince(start),
            eventSpanSeconds: end.timeIntervalSince(start),
            averageUsage: 70, peakUsage: 90, observationCount: 3,
            state: "interrupted", endReason: "observationGap", notified: false
        )
    }

    @Test func deleteRangeRemovesEventsInsideIt() {
        let (store, _) = makeStore()
        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)
        store.persistSynchronously(event: event(id: "inside", start: t0, end: t0.addingTimeInterval(120)))
        store.flush()
        #expect(store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600)).count == 1)

        store.deleteRange(fromDay: day, toDay: day + 1)
        // 只删日桶会留下「有事件、无用量」的幽灵记录。
        #expect(store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600)).isEmpty)
    }

    @Test func deleteRangeLeavesEventsOutsideIt() {
        let (store, _) = makeStore()
        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)
        let later = t0.addingTimeInterval(5 * 86400)
        store.persistSynchronously(event: event(id: "later", start: later, end: later.addingTimeInterval(120)))
        store.flush()

        store.deleteRange(fromDay: day, toDay: day + 1)
        // 范围外的事件必须保留。
        let remaining = store.events(from: later.addingTimeInterval(-3600), to: later.addingTimeInterval(3600))
        #expect(remaining.count == 1)
    }

    @Test func twoDirectoriesStayIndependent() {
        let (first, _) = makeStore()
        let (second, _) = makeStore()
        first.persistSynchronously(event: event(id: "only-first", start: t0, end: t0.addingTimeInterval(120)))
        first.flush()

        // 两个渠道使用独立库：删除或迁移一方不影响另一方。
        #expect(first.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600)).count == 1)
        #expect(second.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600)).isEmpty)
    }
}

/// S04：事件保留窗口与日汇总同口径。
struct StatisticsEventRetentionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> StatisticsProcessStore {
        StatisticsProcessStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func event(id: String, endedAt: Date) -> PersistedAppEvent {
        PersistedAppEvent(
            eventID: id, appKey: "bundle:com.example.App", name: "App", metric: "cpu",
            startedAt: endedAt.addingTimeInterval(-120), endedAt: endedAt, lastEffectiveAt: endedAt,
            continuousHighSeconds: 120, eventSpanSeconds: 120,
            averageUsage: 70, peakUsage: 90, observationCount: 3,
            state: "interrupted", endReason: "observationGap", notified: false
        )
    }

    @Test func retentionWindowIsSixtyDays() {
        #expect(StatisticsProcessStore.eventRetentionDays == 60)
    }

    @Test func eventsOlderThanCutoffAreRemovedWithDailyRows() {
        let store = makeStore()
        let old = now.addingTimeInterval(-90 * 86400)
        let recent = now.addingTimeInterval(-10 * 86400)
        store.persistSynchronously(event: event(id: "old", endedAt: old))
        store.persistSynchronously(event: event(id: "recent", endedAt: recent))
        store.flush()

        // 以 60 天窗口为界删除。
        let cutoff = StatisticsProcessStore.dayKey(now.addingTimeInterval(-60 * 86400), calendar: .current)
        store.deleteBefore(day: cutoff)
        store.flush()

        let remaining = store.events(from: now.addingTimeInterval(-120 * 86400), to: now)
        #expect(remaining.contains { $0.eventID == "recent" })
        // 事件与日汇总同口径：超窗的记录一并清理，避免无限增长。
        #expect(remaining.contains { $0.eventID == "old" } == false)
    }
}
