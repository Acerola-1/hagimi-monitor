import Foundation
import Testing
@testable import HagimiMonitorDirect

/// S03 相关：确认事件落库后可读回；重启把进行中的事件以最后有效时刻中断；
/// 完全在范围外的事件不进入查询结果。
struct AppEventPersistenceTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> (StatisticsProcessStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (StatisticsProcessStore(directory: directory), directory)
    }

    private func event(
        id: String,
        appKey: String = "bundle:com.example.App",
        name: String = "App",
        metric: String = "cpu",
        start: Date,
        end: Date,
        state: String = "interrupted",
        reason: String? = "observationGap"
    ) -> PersistedAppEvent {
        PersistedAppEvent(
            eventID: id,
            appKey: appKey,
            name: name,
            metric: metric,
            startedAt: start,
            endedAt: end,
            lastEffectiveAt: end,
            continuousHighSeconds: end.timeIntervalSince(start),
            eventSpanSeconds: end.timeIntervalSince(start),
            averageUsage: 70,
            peakUsage: 85,
            observationCount: 3,
            state: state,
            endReason: reason,
            notified: false
        )
    }

    @Test func persistedEventCanBeReadBack() {
        let (store, _) = makeStore()
        store.persistSynchronously(event: event(id: "e1", start: t0, end: t0.addingTimeInterval(120)))
        // persist 走异步队列；flush 保证前面的写入已完成。
        store.flush()

        let read = store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        #expect(read.count == 1)
        let first = read.first
        #expect(first?.eventID == "e1")
        #expect(first?.continuousHighSeconds == 120)
        #expect(first?.state == "interrupted")
        #expect(first?.endReason == "observationGap")
    }

    @Test func repeatedPersistOfSameEventIsIdempotent() {
        let (store, _) = makeStore()
        let base = event(id: "dup", start: t0, end: t0.addingTimeInterval(120))
        store.persist(event: base)
        store.persist(event: base)
        store.flush()

        let read = store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        // 同一事件重复落库只保留一行，不会因重复投递而倍增。
        #expect(read.count == 1)
    }

    @Test func updateReplacesFieldsInsteadOfDuplicating() {
        let (store, _) = makeStore()
        store.persistSynchronously(event: event(id: "upd", start: t0, end: t0.addingTimeInterval(120)))
        store.persistSynchronously(event: event(
            id: "upd", start: t0, end: t0.addingTimeInterval(300),
            state: "recovered", reason: "recovered"
        ))
        store.flush()

        let read = store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        #expect(read.count == 1)
        #expect(read.first?.state == "recovered")
        #expect(read.first?.continuousHighSeconds == 300)
    }

    @Test func eventsOutsideRangeAreExcluded() {
        let (store, _) = makeStore()
        store.persistSynchronously(event: event(id: "old", start: t0, end: t0.addingTimeInterval(120)))
        store.flush()

        // 查询窗口完全在事件之后：与 [from, to) 无交集，不返回。
        let after = store.events(from: t0.addingTimeInterval(7200), to: t0.addingTimeInterval(10800))
        #expect(after.isEmpty)
    }

    @Test func eventStraddlingBoundaryIsReturned() {
        let (store, _) = makeStore()
        // 23:59 开始、跨过范围起点的事件仍与本期有交集，应当返回。
        store.persistSynchronously(event: event(id: "straddle", start: t0, end: t0.addingTimeInterval(600)))
        store.flush()

        let read = store.events(from: t0.addingTimeInterval(300), to: t0.addingTimeInterval(900))
        #expect(read.count == 1)
        #expect(read.first?.eventID == "straddle")
    }

    @Test func ongoingEventIsInterruptedAtLastEffectiveMoment() {
        let (store, _) = makeStore()
        // 一条仍标记为进行中的事件：上次退出时没有正常结束。
        store.persistSynchronously(event: event(
            id: "ongoing",
            start: t0,
            end: t0.addingTimeInterval(120),
            state: "ongoing",
            reason: nil
        ))
        store.flush()

        store.interruptPersistedOngoingSynchronously(reason: "replaced")
        store.flush()

        let read = store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        #expect(read.count == 1)
        #expect(read.first?.state == "interrupted")
        #expect(read.first?.endReason == "replaced")
        // 结束点取最后有效时刻，不能延长到本次启动。
        #expect(read.first?.endedAt == t0.addingTimeInterval(120))
    }

    @Test func persistedEventsRestoreIntoDisplayModel() {
        let stored = [
            PersistedAppEvent(
                eventID: UUID().uuidString,
                appKey: "bundle:com.example.App",
                name: "App",
                metric: "cpu",
                startedAt: t0,
                endedAt: t0.addingTimeInterval(180),
                lastEffectiveAt: t0.addingTimeInterval(180),
                continuousHighSeconds: 180,
                eventSpanSeconds: 180,
                averageUsage: 72,
                peakUsage: 91,
                observationCount: 4,
                state: "interrupted",
                endReason: "observationGap",
                notified: false
            ),
            // 无法解析的脏数据必须被跳过，而不是让整批历史消失或崩掉。
            PersistedAppEvent(
                eventID: "not-a-uuid",
                appKey: "bundle:com.example.Broken",
                name: "Broken",
                metric: "cpu",
                startedAt: t0,
                endedAt: t0,
                lastEffectiveAt: t0,
                continuousHighSeconds: 0,
                eventSpanSeconds: 0,
                averageUsage: 0,
                peakUsage: 0,
                observationCount: 0,
                state: "interrupted",
                endReason: nil,
                notified: false
            ),
        ]
        let restored = ReportDataAggregator.persistedEpisodes(stored)
        #expect(restored.count == 1)
        let episode = restored.first
        #expect(episode?.metric == .cpu)
        #expect(episode?.state == .interrupted)
        #expect(episode?.endReason == .observationGap)
        #expect(episode?.continuousHighSeconds == 180)
        #expect(episode?.observationCount == 4)
    }

    @Test func unknownMetricOrStateIsSkipped() {
        let stored = [PersistedAppEvent(
            eventID: UUID().uuidString,
            appKey: "k", name: "n", metric: "unknown-metric",
            startedAt: t0, endedAt: t0, lastEffectiveAt: t0,
            continuousHighSeconds: 0, eventSpanSeconds: 0,
            averageUsage: 0, peakUsage: 0, observationCount: 0,
            state: "interrupted", endReason: nil, notified: false
        )]
        #expect(ReportDataAggregator.persistedEpisodes(stored).isEmpty)
    }

    @Test func eventsSurviveStoreReopen() {
        let (store, directory) = makeStore()
        store.persistSynchronously(event: event(id: "survivor", start: t0, end: t0.addingTimeInterval(120)))
        store.flush()

        // 重新打开同一目录（等价于重启后再读历史）。
        let reopened = StatisticsProcessStore(directory: directory)
        let read = reopened.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        #expect(read.count == 1)
        #expect(read.first?.eventID == "survivor")
    }
}
