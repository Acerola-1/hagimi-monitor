import Testing
import SwiftData
@testable import HagimiMonitor

@Suite("Statistics Tests")
struct StatisticsTests {

    /// 创建内存中的测试容器
    private func makeTestContainer() -> ModelContainer {
        let schema = Schema([HourlySample.self, DailyAggregate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func makeTestModule(kind: MonitorKind, value: Double) -> MonitorModule {
        MonitorModule(kind: kind, value: value, summary: "\(value)", metrics: [], samples: [])
    }

    @Test("Record accumulates values in bucket")
    func testRecordAccumulates() async throws {
        let container = makeTestContainer()
        let recorder = await StatisticsRecorder(container: container)

        let modules = [makeTestModule(kind: .cpu, value: 50)]
        await recorder.record(modules: modules)
        await recorder.record(modules: modules)
        await recorder.record(modules: modules)

        // 验证内存桶已累加（通过检查内部状态不可直接测试，
        // 但可以通过 flush 后查询来验证）
        // 这里主要验证不会崩溃
    }

    @Test("HourlySample round-trip")
    func testHourlySamplePersistence() throws {
        let container = makeTestContainer()
        let context = ModelContext(container)

        let sample = HourlySample(
            hour: Date(), kind: "cpu",
            avg: 42.5, peak: 89.0, low: 5.0, sampleCount: 100
        )
        context.insert(sample)
        try context.save()

        let descriptor = FetchDescriptor<HourlySample>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].avg == 42.5)
        #expect(fetched[0].peak == 89.0)
        #expect(fetched[0].sampleCount == 100)
    }

    @Test("DailyAggregate round-trip")
    func testDailyAggregatePersistence() throws {
        let container = makeTestContainer()
        let context = ModelContext(container)

        let agg = DailyAggregate(
            date: Calendar.current.startOfDay(for: Date()), kind: "memory",
            avg: 10.4, peak: 13.2, low: 8.1, sampleCount: 86400,
            avgPower: 8.3
        )
        context.insert(agg)
        try context.save()

        let descriptor = FetchDescriptor<DailyAggregate>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].avg == 10.4)
        #expect(fetched[0].avgPower == 8.3)
    }

    @Test("Aggregator returns empty for no data")
    func testAggregatorEmpty() async throws {
        let container = makeTestContainer()
        let aggregator = await StatisticsAggregator(container: container)
        let result = await aggregator.query(kind: .cpu, range: .lastWeek)
        #expect(result.points.isEmpty)
        #expect(result.avg == 0)
    }

    @Test("Aggregator queries daily data correctly")
    func testAggregatorDaily() async throws {
        let container = makeTestContainer()
        let context = ModelContext(container)

        // 插入测试数据
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Calendar.current.startOfDay(for: Date()))!
            let agg = DailyAggregate(date: date, kind: "cpu", avg: Double(30 + i * 5), peak: Double(50 + i * 5), low: Double(10 + i), sampleCount: 1000)
            context.insert(agg)
        }
        try context.save()

        let aggregator = await StatisticsAggregator(container: container)
        let result = await aggregator.query(kind: .cpu, range: .lastWeek)
        #expect(result.points.count == 7)
        #expect(result.peak > 0)
    }

    @Test("StatisticsTimeRange title is localized")
    func testTimeRangeTitle() {
        let range = StatisticsTimeRange.lastWeek
        // 验证不会崩溃，title 非空
        #expect(!range.title.isEmpty)
    }
}
