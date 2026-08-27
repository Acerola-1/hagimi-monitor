import Foundation
import Testing
@testable import HagimiMonitorDirect

// MARK: - 测试辅助

/// 组装一个仅含指定指标的模块,其余字段与采样器真实输出同构。
private func makeModule(
    _ kind: MonitorKind,
    value: Double,
    metrics: [MonitorMetric] = [],
    pressureValue: Double? = nil,
    cpuCoreDetail: CPUCoreDetail? = nil
) -> MonitorModule {
    var module = MonitorModule(kind: kind, value: value, summary: "", metrics: metrics, samples: [])
    module.pressureValue = pressureValue
    module.cpuCoreDetail = cpuCoreDetail
    return module
}

private func tempDatabaseURL(_ name: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("stats-tests-\(name)-\(UUID().uuidString).sqlite3")
}

/// 测试帧基准时戳:对齐分钟边界的近时刻。记录器初始化会异步触发按真实当前时刻的
/// maintain,超出保留窗口的历史行会被剪掉,测试行必须落在保留窗口内。
private func recentMinuteBase(_ secondsAgo: TimeInterval = 600) -> Date {
    Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60 - secondsAgo)
}

// MARK: - 行聚合

struct StatisticsRowTests {
    @Test func weightedAverageRespectsFrameCounts() {
        let base = TimeInterval(1_700_000_000)
        let rows = [
            StatisticsRow(t: Int64(base), n: 10, values: {
                var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
                v[0] = 20   // cpu_avg
                return v
            }()),
            StatisticsRow(t: Int64(base + 60), n: 30, values: {
                var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
                v[0] = 60   // cpu_avg
                return v
            }()),
        ]
        let aggregated = StatisticsRow.aggregate(rows, t: Int64(base))
        #expect(aggregated?.n == 40)
        #expect(abs((aggregated?.cpuAvg ?? 0) - 50) < 0.001)
    }

    @Test func totalsSumAndPeaksMax() {
        let base = TimeInterval(1_700_000_000)
        let netDownIndex = StatisticsRow.columns.firstIndex { $0.name == "net_down" }!
        let netDownPeakIndex = StatisticsRow.columns.firstIndex { $0.name == "net_down_peak" }!
        func row(_ t: TimeInterval, down: Double, peak: Double) -> StatisticsRow {
            var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            v[netDownIndex] = down
            v[netDownPeakIndex] = peak
            return StatisticsRow(t: Int64(t), n: 60, values: v)
        }
        let aggregated = StatisticsRow.aggregate(
            [row(base, down: 100, peak: 5), row(base + 60, down: 900, peak: 25)],
            t: Int64(base)
        )
        #expect(aggregated?.netDown == 1000)
        #expect(aggregated?.netDownPeak == 25)
    }
}

// MARK: - 数据库三层汇总与保留

struct StatisticsDatabaseTests {
    @Test func hourAndDayRollUpFromMinutes() {
        let database = StatisticsDatabase(url: tempDatabaseURL("rollup"))
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 10))!
        let dayStart = calendar.startOfDay(for: day)

        let cpuAvgIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_avg" }!
        let cpuMaxIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_max" }!
        let netDownIndex = StatisticsRow.columns.firstIndex { $0.name == "net_down" }!

        for (offset, cpu, down) in [(0.0, 10.0, 100.0), (60.0, 50.0, 200.0), (120.0, 20.0, 50.0)] {
            var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            v[cpuAvgIndex] = cpu
            v[cpuMaxIndex] = cpu * 1.5
            v[netDownIndex] = down
            database.insertMinuteRow(StatisticsRow(t: Int64(day.addingTimeInterval(offset).timeIntervalSince1970), n: 60, values: v))
        }

        // 汇总边界落在次日:当天 10 点这一小时与整天都已完成
        let nextDay = dayStart.addingTimeInterval(86400 + 3600)
        database.maintain(now: nextDay)

        let hours = database.hourRows(from: dayStart, to: dayStart.addingTimeInterval(86400))
        #expect(hours.count == 1)
        #expect(abs((hours[0].cpuAvg ?? 0) - 26.6667) < 0.01)
        #expect(hours[0].cpuMax == 75)
        #expect(hours[0].netDown == 350)

        let days = database.dayRows(from: dayStart, to: dayStart.addingTimeInterval(86400))
        #expect(days.count == 1)
        #expect(days[0].n == 180)
        #expect(days[0].netDown == 350)
    }

    @Test func retentionPrunesRolledUpRows() {
        let database = StatisticsDatabase(url: tempDatabaseURL("retention"))
        let now = Date()
        let ancient = now.addingTimeInterval(-(StatisticsDatabase.minuteRetention + 86400))
        let cpuAvgIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_avg" }!
        var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        v[cpuAvgIndex] = 42
        database.insertMinuteRow(StatisticsRow(t: Int64(ancient.timeIntervalSince1970), n: 60, values: v))

        database.maintain(now: now)

        // 分钟行按保留窗口清理,但值先被汇总进小时/日层
        #expect(database.minuteRows(from: ancient.addingTimeInterval(-60), to: ancient.addingTimeInterval(60)).isEmpty)
        #expect(!database.hourRows(from: ancient.addingTimeInterval(-3600), to: ancient.addingTimeInterval(3600)).isEmpty)
        #expect(!database.dayRows(from: ancient.addingTimeInterval(-86400), to: ancient.addingTimeInterval(86400)).isEmpty)
    }

    @Test func deleteBeforeRemovesOnlyOlderRows() {
        let database = StatisticsDatabase(url: tempDatabaseURL("delete-before"))
        let now = Date()
        let old = now.addingTimeInterval(-10 * 86400)
        let recent = now.addingTimeInterval(-1 * 86400)
        let cpuAvgIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_avg" }!
        func row(_ date: Date) -> StatisticsRow {
            var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            v[cpuAvgIndex] = 10
            return StatisticsRow(t: Int64(date.timeIntervalSince1970), n: 60, values: v)
        }
        database.insertMinuteRow(row(old))
        database.insertMinuteRow(row(recent))
        #expect(database.rowCounts.minute == 2)

        // 删除 5 天前:旧行清除、近行保留
        database.deleteBefore(now.addingTimeInterval(-5 * 86400))

        #expect(database.minuteRows(from: old.addingTimeInterval(-60), to: old.addingTimeInterval(60)).isEmpty)
        #expect(!database.minuteRows(from: recent.addingTimeInterval(-60), to: recent.addingTimeInterval(60)).isEmpty)
        #expect(database.rowCounts.minute == 1)
    }

    @Test func deleteAllClearsEveryLayer() {
        let database = StatisticsDatabase(url: tempDatabaseURL("delete-all"))
        let now = Date()
        let cpuAvgIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_avg" }!
        var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        v[cpuAvgIndex] = 42
        database.insertMinuteRow(StatisticsRow(t: Int64(now.timeIntervalSince1970), n: 60, values: v))
        database.maintain(now: now.addingTimeInterval(7200))
        #expect(database.rowCounts.minute + database.rowCounts.hour + database.rowCounts.day > 0)

        database.deleteAll()

        let counts = database.rowCounts
        #expect(counts.minute == 0)
        #expect(counts.hour == 0)
        #expect(counts.day == 0)
    }
}

// MARK: - 记录器

@MainActor
struct StatisticsRecorderTests {
    @Test func aggregatesMetricsAndIntegratesRates() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("recorder"))
        let base = recentMinuteBase()

        let cpu = makeModule(.cpu, value: 40, metrics: [
            MonitorMetric(name: "system", value: "10%", numericValue: 10),
            MonitorMetric(name: "user", value: "30%", numericValue: 30),
        ])
        let network = makeModule(.network, value: 0, metrics: [
            MonitorMetric(name: "download", value: "100 B/s", numericValue: 100),
            MonitorMetric(name: "upload", value: "10 B/s", numericValue: 10),
        ])

        recorder.record(modules: [cpu, network], fans: [], at: base)
        var fasterNetwork = network
        fasterNetwork.metrics = [
            MonitorMetric(name: "download", value: "150 B/s", numericValue: 150),
            MonitorMetric(name: "upload", value: "10 B/s", numericValue: 10),
        ]
        let idleCPU = makeModule(.cpu, value: 60, metrics: [
            MonitorMetric(name: "system", value: "10%", numericValue: 10),
            MonitorMetric(name: "user", value: "50%", numericValue: 50),
        ])
        recorder.record(modules: [idleCPU, fasterNetwork], fans: [], at: base.addingTimeInterval(10))
        recorder.sealCompletedMinuteForTesting()

        let minutes = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes ?? []
        #expect(minutes.count == 1)
        let row = minutes[0]
        #expect(row.n == 2)
        #expect(abs((row.cpuAvg ?? 0) - 50) < 0.001)
        #expect(row.cpuSysAvg == 10)
        // 速率积分:第一段 100 B/s × 10s = 1000 B;末段未观测到不计
        #expect(abs((row.netDown ?? 0) - 1000) < 0.001)
        #expect(row.netDownPeak == 150)
    }

    @Test func sleepGapDoesNotInflateTotals() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("gap"))
        let base = recentMinuteBase()
        let network = makeModule(.network, value: 0, metrics: [
            MonitorMetric(name: "download", value: "1 MB/s", numericValue: 1_000_000),
        ])
        recorder.record(modules: [network], fans: [], at: base)
        // 先同步封第一个分钟:跨分钟触发的 sealCompletedMinute 走 maintenanceQueue 异步,
        // 不先封口会导致 reportSnapshot 时第一个分钟行可能尚未落库。
        recorder.sealCompletedMinuteForTesting()
        // 睡眠 1 小时后的观测:间隔远超积分上限,不累加旧速率
        recorder.record(modules: [network], fans: [], at: base.addingTimeInterval(3600))
        recorder.sealCompletedMinuteForTesting()

        let minutes = recorder.reportSnapshot(now: base.addingTimeInterval(7200))?.minutes ?? []
        #expect(minutes.count == 2) // 两个不同分钟各封一行
        let total = minutes.reduce(0.0) { $0 + ($1.netDown ?? 0) }
        #expect(total == 0)
    }

    @Test func powerCompositionFractions() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("battery"))
        let base = recentMinuteBase()

        func battery(_ status: String) -> MonitorModule {
            makeModule(.battery, value: 80, metrics: [
                MonitorMetric(name: "type", value: "battery"),
                MonitorMetric(name: "status", value: status),
                MonitorMetric(name: "power", value: "12 W", numericValue: 12),
                MonitorMetric(name: "temperature", value: "30°C", numericValue: 30),
            ])
        }
        recorder.record(modules: [battery("charging")], fans: [], at: base)
        recorder.record(modules: [battery("charging")], fans: [], at: base.addingTimeInterval(1))
        recorder.record(modules: [battery("ac-power")], fans: [], at: base.addingTimeInterval(2))
        recorder.record(modules: [battery("on-battery")], fans: [], at: base.addingTimeInterval(3))
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        #expect(abs((row?.acFrac ?? 0) - 0.75) < 0.001)
        #expect(abs((row?.chargingFrac ?? 0) - 0.5) < 0.001)
        #expect(row?.battLevelAvg == 80)
        #expect(row?.battTempAvg == 30)
        #expect(row?.powerAvg == 12)
        #expect(row?.powerMax == 12)
    }

    @Test func desktopAcModuleSkipsBatteryOnlyColumns() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("desktop"))
        let base = recentMinuteBase()
        let acModule = makeModule(.battery, value: 100, metrics: [
            MonitorMetric(name: "type", value: "ac-power"),
            MonitorMetric(name: "status", value: "ac-power"),
            MonitorMetric(name: "power", value: "28 W", numericValue: 28),
        ])
        recorder.record(modules: [acModule], fans: [], at: base)
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        #expect(row?.acFrac == 1)
        #expect(row?.battLevelAvg == nil, "桌面 ac-power 模块不得产出电量历史")
        #expect(row?.powerAvg == 28)
    }

    @Test func suspendDropsFramesAndCursorsUntilResume() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("suspend"))
        let base = recentMinuteBase()
        let cpu = makeModule(.cpu, value: 40)
        let network = makeModule(.network, value: 0, metrics: [
            MonitorMetric(name: "download", value: "1 MB/s", numericValue: 1_000_000),
        ])

        recorder.record(modules: [cpu, network], fans: [], at: base)
        recorder.suspend()
        recorder.record(modules: [cpu, network], fans: [], at: base.addingTimeInterval(1))
        recorder.record(modules: [cpu, network], fans: [], at: base.addingTimeInterval(2))
        recorder.sealCompletedMinuteForTesting()

        // 关闭期间帧不积累:进行中的分钟在 suspend 时已丢弃,封口无行可落。
        var minutes = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes ?? []
        #expect(minutes.isEmpty)

        // 恢复后正常记录;速率游标已在 suspend 清零:若未清零,base 到恢复后首帧的 2s 会
        // 按旧速率积进 2MB,清零后只计恢复后两帧之间的 1s。
        recorder.resume()
        recorder.record(modules: [cpu, network], fans: [], at: base.addingTimeInterval(2))
        recorder.record(modules: [cpu, network], fans: [], at: base.addingTimeInterval(3))
        recorder.sealCompletedMinuteForTesting()

        minutes = recorder.reportSnapshot(now: base.addingTimeInterval(300))?.minutes ?? []
        #expect(minutes.count == 1)
        #expect(minutes[0].cpuAvg == 40)
        #expect((minutes[0].netDown ?? 0) == 1_000_000)
    }
}

// MARK: - 占用分解与打卡保留

struct StatisticsBreakdownTests {
    @Test func breakdownSplitsDataFromSystemAfterDeleteAll() {
        let database = StatisticsDatabase(url: tempDatabaseURL("breakdown"))
        let base = Int64(Date().timeIntervalSince1970 / 60) * 60 - 300 * 60
        let cpuAvgIndex = StatisticsRow.columns.firstIndex { $0.name == "cpu_avg" }!
        var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        values[cpuAvgIndex] = 30
        for offset in 0..<300 {
            database.insertMinuteRow(StatisticsRow(t: base + Int64(offset) * 60, n: 60, values: values))
        }
        // 有效数据显著存在;清空后归零且系统侧(结构页+WAL索引)仍在
        #expect(database.breakdown.dataBytes > 0)

        database.deleteAll()

        let cleared = database.breakdown
        #expect(cleared.dataBytes == 0)
        #expect(cleared.systemBytes > 0)
    }
}

@MainActor
struct ProcessStoreCheckinTests {
    @Test func deleteAllKeepsCheckins() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("procstore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StatisticsProcessStore(directory: directory)
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = Date(timeIntervalSince1970: 1_760_000_000)
        store.recordUsageDay(at: firstDay, calendar: calendar)
        store.recordUsageDay(at: firstDay.addingTimeInterval(86_400), calendar: calendar)
        _ = store.usageSummary()
        #expect(store.activeDays().count == 2)
        let beforeMeta = try #require(store.usageSummary())

        store.deleteAll()

        let afterMeta = try #require(store.usageSummary())
        #expect(afterMeta.firstUseDay == beforeMeta.firstUseDay)
        #expect(afterMeta.totalActiveDays == beforeMeta.totalActiveDays)
        #expect(afterMeta.lastActiveDay == beforeMeta.lastActiveDay)
        #expect(store.activeDays().count == 2)
    }
}
