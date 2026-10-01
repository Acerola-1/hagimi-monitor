import Foundation
import Testing
@testable import HagimiMonitorDirect

/// S01：旧库（只有日汇总与身份、没有事件表）升级后历史仍可读，
/// 重复打开幂等；新事件表与既有表共存。
struct StatisticsStoreMigrationTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(_ directory: URL) -> StatisticsProcessStore {
        StatisticsProcessStore(directory: directory)
    }

    @Test func schemaVersionIsDeclared() {
        #expect(StatisticsProcessStore.schemaVersion >= 2)
    }

    @Test func reopeningTheSameDirectoryIsIdempotent() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // 连续打开三次等价于多次启动；不得报错、不得清空。
        let first = makeStore(directory)
        first.persistSynchronously(event: PersistedAppEvent(
            eventID: UUID().uuidString,
            appKey: "bundle:com.example.App", name: "App", metric: "cpu",
            startedAt: t0, endedAt: t0.addingTimeInterval(120), lastEffectiveAt: t0.addingTimeInterval(120),
            continuousHighSeconds: 120, eventSpanSeconds: 120,
            averageUsage: 70, peakUsage: 90, observationCount: 3,
            state: "interrupted", endReason: "observationGap", notified: false
        ))
        first.flush()

        _ = makeStore(directory)
        let third = makeStore(directory)
        let events = third.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        // 重复打开不会重复插入或丢失。
        #expect(events.count == 1)
    }

    @Test func legacyDailyRowsCoexistWithNewEventTable() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = makeStore(directory)
        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)

        // 旧形态数据：以显示名为 appKey 的日汇总行。
        store.record(
            cpu: [(name: "LegacyApp", pid: 1, usage: 70)],
            memory: [], gpu: [], network: [], disk: [],
            at: t0, calendar: .current
        )
        store.flush()

        // 新事件写入同一容器。
        store.persistSynchronously(event: PersistedAppEvent(
            eventID: UUID().uuidString,
            appKey: "bundle:com.example.LegacyApp", name: "LegacyApp", metric: "cpu",
            startedAt: t0, endedAt: t0.addingTimeInterval(120), lastEffectiveAt: t0.addingTimeInterval(120),
            continuousHighSeconds: 120, eventSpanSeconds: 120,
            averageUsage: 70, peakUsage: 90, observationCount: 3,
            state: "interrupted", endReason: "observationGap", notified: false
        ))

        let rows = store.dailyRows(fromDay: day, toDay: day + 1)
        let events = store.events(from: t0.addingTimeInterval(-3600), to: t0.addingTimeInterval(3600))
        // 加表迁移不破坏既有日汇总。
        #expect(rows.isEmpty == false)
        #expect(events.count == 1)
    }

    @Test func unknownIdentityRowsRemainReadable() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = makeStore(directory)
        // 旧版本写入的纯名称键：必须仍能被读回，不能被当成损坏数据丢弃。
        store.record(
            cpu: [(name: "旧名称应用", pid: 1, usage: 80)],
            memory: [], gpu: [], network: [], disk: [],
            at: t0, calendar: .current
        )
        store.flush()

        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)
        let rows = store.dailyRows(fromDay: day, toDay: day + 1)
        #expect(rows.contains { $0.name == "旧名称应用" })
    }
}
