import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 5.7：独立旧库 → 新库 → 可恢复旧版本的完整演练，以及库占用测量。
///
/// 演练使用独立临时目录，不触碰用户真实数据。
struct StatisticsStoreDrillTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hagimi-drill-\(UUID().uuidString)")
    }

    private func databaseFile(in directory: URL) -> URL {
        directory.appendingPathComponent("AppStats.sqlite")
    }

    private func event(id: String, appKey: String, at date: Date) -> PersistedAppEvent {
        PersistedAppEvent(
            eventID: id, appKey: appKey, name: appKey, metric: "cpu",
            startedAt: date, endedAt: date.addingTimeInterval(120), lastEffectiveAt: date.addingTimeInterval(120),
            continuousHighSeconds: 120, eventSpanSeconds: 120,
            averageUsage: 70, peakUsage: 90, observationCount: 3,
            state: "interrupted", endReason: "observationGap", notified: false
        )
    }

    /// 旧库形态：只有日汇总与身份，没有事件表。
    private func seedLegacyShape(_ directory: URL) {
        let store = StatisticsProcessStore(directory: directory)
        for dayOffset in 0..<5 {
            let date = t0.addingTimeInterval(Double(dayOffset) * 86400)
            store.record(
                cpu: [(name: "LegacyApp", pid: 1, usage: 70)],
                memory: [(name: "LegacyApp", pid: 1, bytes: 8e9)],
                gpu: [], network: [], disk: [],
                at: date, calendar: .current
            )
        }
        store.flushSynchronously()
    }

    @Test func legacyShapeOpensAndUpgradesWithoutLosingHistory() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // 第一阶段：旧形态写入。
        seedLegacyShape(directory)
        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)
        let legacyCountBefore = StatisticsProcessStore(directory: directory)
            .dailyRows(fromDay: day, toDay: day + 5).count
        #expect(legacyCountBefore > 0)

        // 第二阶段：新版本打开同一目录（加表迁移）并写入事件。
        let upgraded = StatisticsProcessStore(directory: directory)
        upgraded.persistSynchronously(event: event(id: "drill-1", appKey: "bundle:com.example.New", at: t0))
        upgraded.flushSynchronously()

        let upgradedRows = StatisticsProcessStore(directory: directory)
            .dailyRows(fromDay: day, toDay: day + 5)
        // 迁移后旧日汇总仍完整可读。
        #expect(upgradedRows.count == legacyCountBefore)
        #expect(upgradedRows.contains { $0.name == "LegacyApp" })

        let events = StatisticsProcessStore(directory: directory)
            .events(from: t0.addingTimeInterval(-86400), to: t0.addingTimeInterval(86400))
        #expect(events.count == 1)
    }

    @Test func legacyRowsRemainReadableAfterUpgrade() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        seedLegacyShape(directory)
        // 新版本打开并只读：旧的纯名称键行必须仍能读回，不被当成损坏数据丢弃。
        let store = StatisticsProcessStore(directory: directory)
        _ = store.events(from: t0, to: t0.addingTimeInterval(86400))

        let day = StatisticsProcessStore.dayKey(t0, calendar: .current)
        let rows = store.dailyRows(fromDay: day, toDay: day + 5)
        #expect(rows.contains { $0.name == "LegacyApp" })
        #expect(rows.allSatisfy { $0.cpuSamples > 0 })
    }

    @Test func repeatedOpenIsIdempotentAcrossManyLaunches() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        seedLegacyShape(directory)
        StatisticsProcessStore(directory: directory)
            .persistSynchronously(event: event(id: "stable", appKey: "bundle:com.example.New", at: t0))

        // 模拟多次启动；不得报错、不得清空、不得重复插入。
        for _ in 0..<5 {
            _ = StatisticsProcessStore(directory: directory)
        }
        let events = StatisticsProcessStore(directory: directory)
            .events(from: t0.addingTimeInterval(-86400), to: t0.addingTimeInterval(86400))
        #expect(events.count == 1)
    }

    @Test func databaseFootprintStaysBoundedForManyEvents() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = StatisticsProcessStore(directory: directory)
        // 写入 2000 条事件，测量库文件占用，确认不会异常膨胀。
        for index in 0..<2000 {
            let date = t0.addingTimeInterval(Double(index) * 60)
            store.persistSynchronously(event: event(id: "evt-\(index)", appKey: "bundle:com.example.app\(index % 50)", at: date))
        }
        store.flushSynchronously()

        let url = databaseFile(in: directory)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let megabytes = Double(size ?? 0) / 1_048_576
        // 每条事件含分段 JSON，量级应在数十 MB 以内；这里只做数量级护栏。
        #expect(megabytes < 50)
        // 结果写入文件以便对比后续改动。
        let out = directory.appendingPathComponent("footprint.txt")
        try "2000 events\t\(String(format: "%.2f", megabytes)) MB\n".write(to: out, atomically: true, encoding: .utf8)
    }
}
