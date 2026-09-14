import Foundation
import Testing
@testable import HagimiMonitorDirect

@Suite("原生报表数据聚合器测试")
struct ReportDataAggregatorTests {

    private func makeRow(
        t: Int64,
        n: Int = 60,
        cpuAvg: Double? = nil,
        cpuMax: Double? = nil,
        memUsed: Double? = nil,
        netDown: Double? = nil,
        coverS: Double? = nil,
        validMemS: Double? = nil,
        memWarnS: Double? = nil,
        memCritS: Double? = nil
    ) -> StatisticsRow {
        var row = StatisticsRow(t: t, n: n)
        row.cpuAvg = cpuAvg
        row.cpuMax = cpuMax
        row.memUsedAvg = memUsed
        row.netDown = netDown
        row.coverS = coverS
        row.validMemS = validMemS
        row.memWarnS = memWarnS
        row.memCritS = memCritS
        return row
    }

    // MARK: - 粒度选择

    @Test func pickSourceSelectsMinutesForShortRange() {
        let now = Date()
        let from = now.addingTimeInterval(-3600) // 1 hour ago
        let minuteRows = [makeRow(t: Int64(from.timeIntervalSince1970))]
        let source = ReportDataAggregator.pickSource(
            from: from,
            to: now,
            minutes: minuteRows,
            hours: [],
            days: []
        )
        #expect(source == .minutes)
    }

    @Test func pickSourceSelectsHoursForWeekRange() {
        let now = Date()
        let from = now.addingTimeInterval(-7 * 86400) // 7 days ago
        let hourRows = [makeRow(t: Int64(from.timeIntervalSince1970))]
        let source = ReportDataAggregator.pickSource(
            from: from,
            to: now,
            minutes: [],
            hours: hourRows,
            days: []
        )
        #expect(source == .hours)
    }

    @Test func pickSourceSelectsDaysForYearRange() {
        let now = Date()
        let from = now.addingTimeInterval(-365 * 86400) // 365 days ago
        let dayRows = [makeRow(t: Int64(from.timeIntervalSince1970))]
        let source = ReportDataAggregator.pickSource(
            from: from,
            to: now,
            minutes: [],
            hours: [],
            days: dayRows
        )
        #expect(source == .days)
    }

    // MARK: - 基础数学聚合

    @Test func weightedAverageRespectsFrameCounts() {
        // row1: 20%, 10 frames -> sum = 200
        // row2: 80%, 30 frames -> sum = 2400
        // total frames = 40, expected avg = 2600 / 40 = 65.0
        let rows = [
            makeRow(t: 100, n: 10, cpuAvg: 20.0),
            makeRow(t: 200, n: 30, cpuAvg: 80.0),
        ]
        let avg = ReportDataAggregator.weightedAverage(of: rows, keyPath: \.cpuAvg)
        #expect(avg != nil)
        #expect(abs(avg! - 65.0) < 0.001)
    }

    @Test func maximumPicksHighestNonNilValue() {
        let rows = [
            makeRow(t: 100, cpuMax: 45.0),
            makeRow(t: 200, cpuMax: nil),
            makeRow(t: 300, cpuMax: 92.5),
            makeRow(t: 400, cpuMax: 88.0),
        ]
        let maxVal = ReportDataAggregator.maximum(of: rows, keyPath: \.cpuMax)
        #expect(maxVal == 92.5)

        let maxPair = ReportDataAggregator.maximumWithTime(of: rows, keyPath: \.cpuMax)
        #expect(maxPair?.value == 92.5)
        #expect(maxPair?.time == Date(timeIntervalSince1970: 300))
    }

    @Test func totalSumsAllAvailableValues() {
        let rows = [
            makeRow(t: 100, netDown: 1024),
            makeRow(t: 200, netDown: nil),
            makeRow(t: 300, netDown: 2048),
        ]
        let sum = ReportDataAggregator.total(of: rows, keyPath: \.netDown)
        #expect(sum == 3072)
    }

    @Test func coverageRatioReturnsNilWithoutRowsOrValidRange() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        #expect(ReportDataAggregator.coverageRatio(rows: [], from: start, to: end) == nil)
        #expect(ReportDataAggregator.coverageRatio(
            rows: [makeRow(t: 1_000, n: 0, coverS: 0)], from: start, to: end
        ) == nil)
        #expect(ReportDataAggregator.coverageRatio(
            rows: [makeRow(t: 1_000, coverS: 60)], from: end, to: start
        ) == nil)
    }

    @Test func coverageRatioUsesEffectiveCoverageAndClampsToRange() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let partial = ReportDataAggregator.coverageRatio(
            rows: [makeRow(t: 1_000, coverS: 250), makeRow(t: 1_500, coverS: 250)],
            from: start,
            to: end
        )
        #expect(partial != nil)
        #expect(abs((partial ?? 0) - 0.5) < 0.000_001)

        let overRange = ReportDataAggregator.coverageRatio(
            rows: [makeRow(t: 1_000, coverS: 1_500)], from: start, to: end
        )
        #expect(overRange == 1)
    }

    // MARK: - 负载分布计算

    @Test func distributionPlacesValuesInCorrectBuckets() {
        // bucket 0: <10, bucket 1: 10..<30, bucket 2: 30..<60, bucket 3: 60..<90, bucket 4: >=90
        let rows = [
            makeRow(t: 100, cpuAvg: 5.0, coverS: 100),   // bucket 0
            makeRow(t: 200, cpuAvg: 20.0, coverS: 200),  // bucket 1
            makeRow(t: 300, cpuAvg: 45.0, coverS: 300),  // bucket 2
            makeRow(t: 400, cpuAvg: 75.0, coverS: 150),  // bucket 3
            makeRow(t: 500, cpuAvg: 95.0, coverS: 250),  // bucket 4
        ]
        let dist = ReportDataAggregator.computeDistribution(of: rows, keyPath: \.cpuAvg)
        #expect(dist != nil)
        #expect(dist?.totalCoverSeconds == 1000)
        #expect(dist?.buckets[0].percent == 10.0)
        #expect(dist?.buckets[1].percent == 20.0)
        #expect(dist?.buckets[2].percent == 30.0)
        #expect(dist?.buckets[3].percent == 15.0)
        #expect(dist?.buckets[4].percent == 25.0)
    }

    // MARK: - 异常事件推导

    @Test func alertEventsMergeConsecutiveRunsAndIdentifyState() {
        let baseT: Int64 = 1_700_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(baseT + 3600))

        // Three consecutive 60s minutes of memory warning
        let rows = [
            makeRow(t: baseT, n: 60, coverS: 60, validMemS: 60, memWarnS: 40),
            makeRow(t: baseT + 60, n: 60, coverS: 60, validMemS: 60, memWarnS: 50),
            makeRow(t: baseT + 120, n: 60, coverS: 60, validMemS: 60, memCritS: 60),
            // Later observation with no pressure: confirms recovery with valid memory sampling
            makeRow(t: baseT + 300, n: 60, coverS: 60, validMemS: 60, memWarnS: 0),
        ]

        let events = ReportDataAggregator.deriveAlertEvents(rows: rows, source: .minutes, now: now)
        #expect(events.count == 1)
        let ev = events[0]
        #expect(ev.kind == .memory)
        #expect(ev.state == .recovered)
        #expect(ev.pressureSeconds == 150)
        #expect(ev.worstLevel == 2)
    }

    // MARK: - 应用排行聚合

    @Test func aggregateAppsComputesWeightedAveragesAndTiers() {
        let from = Date(timeIntervalSince1970: 10_000)
        let to = Date(timeIntervalSince1970: 20_000)
        let day = StatisticsProcessStore.dayKey(from, calendar: .current)

        let row1 = StatisticsProcessStore.DailyAppRow(
            day: day,
            appKey: "com.apple.Safari",
            name: "Safari",
            cpuAvg: 30.0,
            cpuSamples: 10,
            gpuAvg: 10.0,
            gpuSamples: 10,
            memAvgBytes: 500 * 1024 * 1024,
            memSamples: 10,
            netDownBytes: 1000,
            netUpBytes: 500,
            cpuTier1: 5, cpuTier2: 2, cpuTier3: 0,
            cpuPeak: 45.0,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0,
            gpuPeak: 12.0,
            memTier1: 0, memTier2: 0, memTier3: 0,
            memPeak: 0
        )
        let row2 = StatisticsProcessStore.DailyAppRow(
            day: day,
            appKey: "com.apple.Safari",
            name: "Safari",
            cpuAvg: 60.0,
            cpuSamples: 20,
            gpuAvg: 20.0,
            gpuSamples: 20,
            memAvgBytes: 800 * 1024 * 1024,
            memSamples: 20,
            netDownBytes: 2000,
            netUpBytes: 1000,
            cpuTier1: 10, cpuTier2: 5, cpuTier3: 1,
            cpuPeak: 85.0,
            gpuTier1: 0, gpuTier2: 0, gpuTier3: 0,
            gpuPeak: 25.0,
            memTier1: 0, memTier2: 0, memTier3: 0,
            memPeak: 0
        )

        let processData = ReportProcessData(
            identities: ["com.apple.Safari": ReportAppIdentity(appKey: "com.apple.Safari", name: "Safari", iconPNG: nil)],
            dailyRows: [row1, row2],
            batteryHistory: [],
            alerts: []
        )

        let rankings = ReportDataAggregator.aggregateApps(processData: processData, from: from, to: to, isDirect: true)
        #expect(rankings.cpuList.count == 1)
        let safariCpu = rankings.cpuList[0]
        // (30*10 + 60*20) / 30 = 1500 / 30 = 50.0
        #expect(safariCpu.value == 50.0)
        #expect(safariCpu.tierHint?.contains("30-50%: 15m") == true)
        #expect(rankings.netList.count == 1)
        #expect(rankings.netList[0].value == 4500) // (1000+500) + (2000+1000)
    }
}
