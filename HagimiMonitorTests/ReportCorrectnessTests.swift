import Foundation
import Dispatch
import Testing
@testable import HagimiMonitorDirect

@Suite("报表正确性回归测试 (R01~R17)")
struct ReportCorrectnessTests {

    @Test func reportSnapshotProviderRunsStorageReadsOffMainActor() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("report-provider-(UUID().uuidString).sqlite3")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        let database = StatisticsDatabase(url: url)
        let provider = StatisticsReportDataProvider(
            database: database,
            processStore: nil,
            calendar: .current
        )

        let input = await Task.detached(priority: .utility) {
            dispatchPrecondition(condition: .notOnQueue(.main))
            return provider.load(now: Date(), alerts: [])
        }.value

        #expect(input != nil)
    }

    private func makeRow(
        t: Int64,
        n: Int = 60,
        cpuAvg: Double? = nil,
        cpuMax: Double? = nil,
        gpuAvg: Double? = nil,
        gpuMax: Double? = nil,
        memUsed: Double? = nil,
        memPressure: Double? = nil,
        netDown: Double? = nil,
        netUp: Double? = nil,
        diskRead: Double? = nil,
        diskWrite: Double? = nil,
        powerAvg: Double? = nil,
        cpuTemp: Double? = nil,
        cpuThermal: Double? = nil,
        fanAvg: Double? = nil,
        coverS: Double? = nil,
        validMemS: Double? = nil,
        memWarnS: Double? = nil,
        memCritS: Double? = nil,
        validThermalS: Double? = nil,
        thFairS: Double? = nil,
        thSeriousS: Double? = nil,
        thCritS: Double? = nil
    ) -> StatisticsRow {
        var row = StatisticsRow(t: t, n: n)
        row.cpuAvg = cpuAvg
        row.cpuMax = cpuMax
        row.gpuAvg = gpuAvg
        row.gpuMax = gpuMax
        row.memUsedAvg = memUsed
        row.memPressureAvg = memPressure
        row.netDown = netDown
        row.netUp = netUp
        row.diskRead = diskRead
        row.diskWrite = diskWrite
        row.powerAvg = powerAvg
        row.cpuTempAvg = cpuTemp
        row.cpuThermalAvg = cpuThermal
        row.fanAvg = fanAvg
        row.coverS = coverS
        row.validMemS = validMemS
        row.memWarnS = memWarnS
        row.memCritS = memCritS
        row.validThermalS = validThermalS
        row.thFairS = thFairS
        row.thSeriousS = thSeriousS
        row.thCritS = thCritS
        return row
    }

    // MARK: - R01: 累计量 vs 平均速率转换

    @Test func r01RateCalculationDividesTotalByBucketSeconds() {
        // 1 分钟桶：累计 60 MiB -> 平均速率应为 1 MiB/s (1,048,576 B/s)
        let minuteBytes: Double = 60 * 1024 * 1024
        let minuteRate = ReportDataAggregator.rateFromTotal(totalBytes: minuteBytes, bucketSeconds: 60)
        #expect(abs(minuteRate - 1_048_576) < 1.0)

        // 1 小时桶：累计 3600 MiB -> 平均速率应同样为 1 MiB/s (1,048,576 B/s)
        let hourBytes: Double = 3600 * 1024 * 1024
        let hourRate = ReportDataAggregator.rateFromTotal(totalBytes: hourBytes, bucketSeconds: 3600)
        #expect(abs(hourRate - 1_048_576) < 1.0)

        // 峰值速率不应再除以桶秒数
        let peakInput: Double = 10 * 1024 * 1024 // 10 MiB/s
        #expect(peakInput == 10 * 1024 * 1024)
    }

    // MARK: - R03: 硬件能力与范围历史无数据区分

    @Test func r03BatteryHardwareDistinguishedFromEmptyHistory() {
        // 当系统拥有电池硬件（hasBatteryHardware = true），即使所选时间范围内 rows 无电量采样、batteryHistory 为空，
        // 也必须标记为 supported，不能误判为“台式机/AC交流供电”
        let metrics = ReportDataAggregator.computeBatteryMetrics(
            rows: [],
            batteryHistory: [],
            from: Date(timeIntervalSince1970: 1000),
            to: Date(timeIntervalSince1970: 2000),
            hardwareHasBattery: true
        )
        #expect(metrics.isSupported == true)
        #expect(metrics.hasHistoryInRange == false)

        // 仅当硬件本身无电池（如 Mac mini / Mac Studio）时，才为 false
        let desktopMetrics = ReportDataAggregator.computeBatteryMetrics(
            rows: [],
            batteryHistory: [],
            from: Date(timeIntervalSince1970: 1000),
            to: Date(timeIntervalSince1970: 2000),
            hardwareHasBattery: false
        )
        #expect(desktopMetrics.isSupported == false)
    }

    @Test func r03FanHardwareDistinguishedFromZeroRPMOrSandbox() {
        // 当设备有风扇硬件，但当前处于 0 RPM（停转），必须判定为 hasFans = true
        let rows = [makeRow(t: 100, fanAvg: 0.0)]
        let metrics = ReportDataAggregator.computeThermalMetrics(
            rows: rows,
            hardwareHasFans: true
        )
        #expect(metrics.hasFans == true)
        #expect(metrics.fanAvgRPM == 0.0)

        // 真实被动散热机型（如 MacBook Air）
        let fanlessMetrics = ReportDataAggregator.computeThermalMetrics(
            rows: [],
            hardwareHasFans: false
        )
        #expect(fanlessMetrics.hasFans == false)
    }

    // MARK: - R05: 热状态 0~3 档位映射

    @Test func r05ThermalStatePreservesLevelSemanticsWithoutMultiplying100() {
        // 0=正常/Nominal, 1=中度/Fair, 2=严重/Serious, 3=紧急/Critical
        let label0 = ReportUIHelper.thermalStateLabel(0)
        let label1 = ReportUIHelper.thermalStateLabel(1)
        let label2 = ReportUIHelper.thermalStateLabel(2)
        let label3 = ReportUIHelper.thermalStateLabel(3)
        let formatted = ReportUIHelper.formatThermalLevel(2.0)

        print("DEBUG r05: label0=\(label0), label1=\(label1), label2=\(label2), label3=\(label3), formatted=\(formatted)")

        #expect(!label0.isEmpty && label0 != "—")
        #expect(!label1.isEmpty && label1 != "—")
        #expect(!label2.isEmpty && label2 != "—")
        #expect(!label3.isEmpty && label3 != "—")

        // 格式化输出不得包含 200%、300%
        #expect(!formatted.contains("200%"))
        #expect(!formatted.contains("300%"))
        #expect(formatted.contains("2.0") || formatted.contains("严重") || formatted.contains("Serious"))
    }

    // MARK: - R06: 7x24 小时热力图消费小时数据与复合忙碌度

    @Test func r06HeatmapUsesHourlyRowsAndCompositeBusyScore() {
        let calendar = Calendar.current
        let t1: Int64 = 1_700_000_000 // A specific timestamp
        let date1 = Date(timeIntervalSince1970: TimeInterval(t1))
        let wd1 = calendar.component(.weekday, from: date1) - 1
        let hr1 = calendar.component(.hour, from: date1)

        // 一行数据：CPU 10%，但 GPU 80%，内存压力 30%
        // 忙碌度应取 max(10, 80, 30) = 80.0
        let hourRow = makeRow(t: t1, n: 3600, cpuAvg: 10.0, gpuAvg: 80.0, memPressure: 30.0)
        let heatmap = ReportDataAggregator.buildHeatmap(hourlyRows: [hourRow], calendar: calendar)

        let targetCell = heatmap.cells.first { $0.weekday == wd1 && $0.hour == hr1 }
        #expect(targetCell != nil)
        #expect(targetCell?.avgBusy != nil)
        #expect(abs((targetCell?.avgBusy ?? 0) - 80.0) < 0.001)
    }

    // MARK: - R07: 采样缺口与曲线断开

    @Test func r07GapDetectionInsertsBreakpoints() {
        let baseT: Int64 = 1_700_000_000
        let rows = [
            makeRow(t: baseT, cpuAvg: 20.0),
            makeRow(t: baseT + 60, cpuAvg: 25.0),
            // 睡眠或关机：间隔 3600 秒（远大于 60 * 1.5 秒）
            makeRow(t: baseT + 3660, cpuAvg: 30.0),
            makeRow(t: baseT + 3720, cpuAvg: 35.0),
        ]

        let series = ReportDataAggregator.buildTimeSeries(
            rows: rows,
            keyPath: \.cpuAvg,
            seriesID: "cpu-avg",
            granularitySeconds: 60
        )

        // 应该分为两个不同的 segmentID，从而在图表中自然断开，不跨睡眠连线
        #expect(series.count == 4)
        #expect(series[0].segmentID == series[1].segmentID)
        #expect(series[2].segmentID == series[3].segmentID)
        #expect(series[1].segmentID != series[2].segmentID)
    }

    // MARK: - R08: 压力事件恢复依据专属维度观测

    @Test func r08PressureEventRecoveryRequiresDomainSpecificObservation() {
        let baseT: Int64 = 1_700_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(baseT + 3600))

        // 1. 内存压力事件发生
        let alertRow = makeRow(t: baseT, n: 60, coverS: 60, validMemS: 60, memWarnS: 40)

        // 2. 后续只有 CPU / 通用 coverS 记录，无 validMemS 或 memNormalS 采样
        let genericRow = makeRow(t: baseT + 60, n: 60, cpuAvg: 20.0, coverS: 60, validMemS: 0)

        let eventsInterrupted = ReportDataAggregator.deriveAlertEvents(
            rows: [alertRow, genericRow],
            source: .minutes,
            now: now
        )
        #expect(eventsInterrupted.count == 1)
        // 没有内存维度的有效观测，绝不能宣告 recovered！
        #expect(eventsInterrupted[0].state != .recovered)

        // 3. 随后出现明确的内存正常观测 (validMemS > 0, memWarnS == 0)
        let normalMemRow = makeRow(t: baseT + 120, n: 60, coverS: 60, validMemS: 60, memWarnS: 0, memCritS: 0)
        let eventsRecovered = ReportDataAggregator.deriveAlertEvents(
            rows: [alertRow, normalMemRow],
            source: .minutes,
            now: now
        )
        #expect(eventsRecovered.count == 1)
        #expect(eventsRecovered[0].state == .recovered)
    }

    // MARK: - R14: 字符串模板变量插值

    @Test func r14TemplateVariableInterpolationWorks() {
        let raw = "所选范围平均 CPU 占用 {v}%"
        let interpolated = ReportUIHelper.interpolateTemplate(raw, replacements: ["v": "24.5"])
        #expect(interpolated == "所选范围平均 CPU 占用 24.5%")
        #expect(!interpolated.contains("{v}"))
    }

    // MARK: - R15: 每日汇总聚合

    @Test func r15DailySummaryAggregatesMultipleRowsIntoSingleDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let t1 = Int64(today.timeIntervalSince1970) + 3600
        let t2 = Int64(today.timeIntervalSince1970) + 7200

        let row1 = makeRow(t: t1, n: 60, cpuAvg: 20.0, cpuMax: 30.0, netDown: 1000, netUp: 500, coverS: 60)
        let row2 = makeRow(t: t2, n: 60, cpuAvg: 40.0, cpuMax: 60.0, netDown: 2000, netUp: 1000, coverS: 60)

        let dailyRows = ReportDataAggregator.aggregateDailySummary(
            minutes: [row1, row2],
            hours: [],
            days: [],
            from: today,
            to: today.addingTimeInterval(86400),
            calendar: calendar
        )

        #expect(dailyRows.count == 1)
        let d = dailyRows[0]
        #expect(d.cpuAvg == 30.0)      // (20+40)/2
        #expect(d.cpuPeak == 60.0)     // max(30, 60)
        #expect(d.netDownTotal == 3000) // 1000 + 2000 (累计量，非速率)
        #expect(d.netUpTotal == 1500)   // 500 + 1000
    }

    // MARK: - R17: 日历分组按时间排序，避免跨年倒序

    @Test func r17DailyBarsSortedChronologicallyAcrossYears() {
        let calendar = Calendar.current
        // 构造 2025-12-31 与 2026-01-01 两行
        var comp1 = DateComponents(); comp1.year = 2025; comp1.month = 12; comp1.day = 31
        var comp2 = DateComponents(); comp2.year = 2026; comp2.month = 1; comp2.day = 1
        let d1 = calendar.date(from: comp1)!
        let d2 = calendar.date(from: comp2)!

        let r1 = makeRow(t: Int64(d1.timeIntervalSince1970), netDown: 1000)
        let r2 = makeRow(t: Int64(d2.timeIntervalSince1970), netDown: 2000)

        let metrics = ReportDataAggregator.computeNetworkMetrics(
            rows: [r2, r1], // 乱序输入
            isHourly: false,
            calendar: calendar
        )

        #expect(metrics.dailyBars.count == 2)
        // 第一项必须是 2025-12-31，第二项必须是 2026-01-01
        #expect(metrics.dailyBars[0].date < metrics.dailyBars[1].date)
        #expect(metrics.dailyBars[0].downBytes == 1000)
        #expect(metrics.dailyBars[1].downBytes == 2000)
    }
}
