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

/// 记录一帧;测试里传入的模块都视为本帧新鲜采样。
@MainActor
private func recordFrame(_ recorder: StatisticsRecorder, _ modules: [MonitorModule], fans: [FanInfo] = [], at date: Date) {
    recorder.record(modules: modules, fans: fans, freshKinds: Set(modules.map(\.kind)), at: date)
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

    /// 秒数口径列必须按求和聚合:分钟→小时→日与原始秒数一致(模型 §10 可合并性)。
    @Test func secondColumnsRollUpBySum() {
        let database = StatisticsDatabase(url: tempDatabaseURL("rollup-seconds"))
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9))!
        let dayStart = calendar.startOfDay(for: day)

        let validMemIndex = StatisticsRow.columns.firstIndex { $0.name == "valid_mem_s" }!
        let memWarnIndex = StatisticsRow.columns.firstIndex { $0.name == "mem_warn_s" }!
        let intersectionIndex = StatisticsRow.columns.firstIndex { $0.name == "valid_mem_thermal_s" }!

        for offset in 0..<3 {
            var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            v[validMemIndex] = 60
            v[memWarnIndex] = Double(10 * (offset + 1))
            v[intersectionIndex] = 60
            database.insertMinuteRow(StatisticsRow(
                t: Int64(day.addingTimeInterval(Double(offset) * 60).timeIntervalSince1970), n: 60, values: v))
        }
        database.maintain(now: dayStart.addingTimeInterval(86400 + 3600))

        let hours = database.hourRows(from: dayStart, to: dayStart.addingTimeInterval(86400))
        #expect(hours.count == 1)
        #expect(hours[0].validMemS == 180)
        #expect(hours[0].memWarnS == 60)
        #expect(hours[0].validMemThermalS == 180)

        let days = database.dayRows(from: dayStart, to: dayStart.addingTimeInterval(86400))
        #expect(days.count == 1)
        #expect(days[0].validMemS == 180)
        #expect(days[0].memWarnS == 60)
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

        recordFrame(recorder, [cpu, network], at: base)
        var fasterNetwork = network
        fasterNetwork.metrics = [
            MonitorMetric(name: "download", value: "150 B/s", numericValue: 150),
            MonitorMetric(name: "upload", value: "10 B/s", numericValue: 10),
        ]
        let idleCPU = makeModule(.cpu, value: 60, metrics: [
            MonitorMetric(name: "system", value: "10%", numericValue: 10),
            MonitorMetric(name: "user", value: "50%", numericValue: 50),
        ])
        recordFrame(recorder, [idleCPU, fasterNetwork], at: base.addingTimeInterval(10))
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
        recordFrame(recorder, [network], at: base)
        // 先同步封第一个分钟:跨分钟触发的 sealCompletedMinute 走 maintenanceQueue 异步,
        // 不先封口会导致 reportSnapshot 时第一个分钟行可能尚未落库。
        recorder.sealCompletedMinuteForTesting()
        // 睡眠 1 小时后的观测:间隔远超积分上限,不累加旧速率
        recordFrame(recorder, [network], at: base.addingTimeInterval(3600))
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
        recordFrame(recorder, [battery("charging")], at: base)
        recordFrame(recorder, [battery("charging")], at: base.addingTimeInterval(1))
        recordFrame(recorder, [battery("ac-power")], at: base.addingTimeInterval(2))
        recordFrame(recorder, [battery("on-battery")], at: base.addingTimeInterval(3))
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
        recordFrame(recorder, [acModule], at: base)
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

        recordFrame(recorder, [cpu, network], at: base)
        recorder.suspend()
        recordFrame(recorder, [cpu, network], at: base.addingTimeInterval(1))
        recordFrame(recorder, [cpu, network], at: base.addingTimeInterval(2))
        recorder.sealCompletedMinuteForTesting()

        // 关闭期间帧不积累:进行中的分钟在 suspend 时已丢弃,封口无行可落。
        var minutes = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes ?? []
        #expect(minutes.isEmpty)

        // 恢复后正常记录;速率游标已在 suspend 清零:若未清零,base 到恢复后首帧的 2s 会
        // 按旧速率积进 2MB,清零后只计恢复后两帧之间的 1s。
        recorder.resume()
        recordFrame(recorder, [cpu, network], at: base.addingTimeInterval(2))
        recordFrame(recorder, [cpu, network], at: base.addingTimeInterval(3))
        recorder.sealCompletedMinuteForTesting()

        minutes = recorder.reportSnapshot(now: base.addingTimeInterval(300))?.minutes ?? []
        #expect(minutes.count == 1)
        #expect(minutes[0].cpuAvg == 40)
        #expect((minutes[0].netDown ?? 0) == 1_000_000)
    }
}

// MARK: - 秒数口径(运行状态评估模型 v0.1)

@MainActor
struct StatisticsSecondsTests {
    /// 一帧含 CPU(带热状态)、GPU、内存(带压力档位)的模块。
    private func frame(cpu: Double, gpu: Double, memLevel: Int, thermal: Int) -> [MonitorModule] {
        [
            makeModule(.cpu, value: cpu, metrics: [
                MonitorMetric(name: "thermal-pressure", value: "s\(thermal)", numericValue: Double(thermal)),
            ]),
            makeModule(.gpu, value: gpu),
            makeModule(.memory, value: 50, metrics: [
                MonitorMetric(name: "pressure-level", value: "l\(memLevel)", numericValue: Double(memLevel)),
            ]),
        ]
    }

    @Test func accruesValidLevelAndHighLoadSeconds() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("seconds"))
        let base = recentMinuteBase()
        for offset in 0...3 {
            recordFrame(recorder, frame(cpu: 90, gpu: 95, memLevel: 1, thermal: 2), at: base.addingTimeInterval(Double(offset)))
        }
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        // 区间归给前一次观测:4 帧覆盖 3 秒
        #expect(row?.validCpuS == 3)
        #expect(row?.cpuHighS == 3)
        #expect(row?.validGpuS == 3)
        #expect(row?.gpuHighS == 3)
        #expect(row?.validMemS == 3)
        #expect(row?.memWarnS == 3)
        #expect(row?.memNormalS == nil, "没有 normal 档位秒数时不写 0")
        #expect(row?.validThermalS == 3)
        #expect(row?.thSeriousS == 3)
        // 交集 J 与两分量同步覆盖
        #expect(row?.validMemThermalS == 3)
        #expect(row?.memWarnJS == 3)
        #expect(row?.thSeriousJS == 3)
    }

    @Test func cachedReadIsNotANewObservation() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("cached"))
        let base = recentMinuteBase()
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 0, thermal: 0), at: base)
        // 缓存帧:内存模块在快照里(值已变),但本帧只新鲜采样了 CPU。
        let cached = frame(cpu: 41, gpu: 10, memLevel: 1, thermal: 0)
        recorder.record(modules: cached, fans: [], freshKinds: [.cpu], at: base.addingTimeInterval(1))
        recorder.record(modules: cached, fans: [], freshKinds: [.cpu], at: base.addingTimeInterval(2))
        // 内存重新新鲜观测:0→3 秒仍归给上次真实观测的 normal 档位。
        recordFrame(recorder, frame(cpu: 42, gpu: 10, memLevel: 1, thermal: 0), at: base.addingTimeInterval(3))
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        #expect(row?.validMemS == 3)
        #expect(row?.memNormalS == 3)
        #expect(row?.memWarnS == nil, "缓存回读不得把区间记给未观测到的档位")
    }

    @Test func gapBeyondContractIsNotAccrued() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("gap-seconds"))
        let base = recentMinuteBase()
        // CPU 契约 maxGap = 6s,内存 9s;30s 间隔整体视为中断。
        recordFrame(recorder, frame(cpu: 90, gpu: 95, memLevel: 1, thermal: 2), at: base)
        recordFrame(recorder, frame(cpu: 90, gpu: 95, memLevel: 1, thermal: 2), at: base.addingTimeInterval(30))
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        #expect(row?.validCpuS == nil)
        #expect(row?.validMemS == nil)
        #expect(row?.validMemThermalS == nil, "中断区间不得计入交集")
    }

    @Test func unknownLevelBreaksTheKnownChain() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("unknown"))
        let base = recentMinuteBase()
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 0), at: base)
        // 观测到未知档位(3):0→1 秒归给上次的 warning,之后链断。
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 3, thermal: 0), at: base.addingTimeInterval(1))
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 0, thermal: 0), at: base.addingTimeInterval(2))
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 0, thermal: 0), at: base.addingTimeInterval(3))
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        #expect(row?.memWarnS == 1)
        #expect(row?.memNormalS == 1)
        #expect(row?.validMemS == 2)
        // 交集同样在未知处断开:0→1 有累计,1→2 为未知,2→3 恢复。
        #expect(row?.validMemThermalS == 1)
    }

    @Test func intersectionNeverExceedsEitherDimension() {
        let recorder = StatisticsRecorder(databaseURL: tempDatabaseURL("intersection"))
        let base = recentMinuteBase()
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 0), at: base)
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 0), at: base.addingTimeInterval(1))
        // 热状态观测到未知(+2):内存继续有效,交集断开。
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 9), at: base.addingTimeInterval(2))
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 0), at: base.addingTimeInterval(3))
        recordFrame(recorder, frame(cpu: 40, gpu: 10, memLevel: 1, thermal: 0), at: base.addingTimeInterval(4))
        recorder.sealCompletedMinuteForTesting()

        let row = recorder.reportSnapshot(now: base.addingTimeInterval(120))?.minutes.first
        // 内存每段都有效;热在+2→+3 未知段不计;交集只在两段已知区间累计。
        #expect(row?.validMemS == 4)
        #expect(row?.validThermalS == 3)
        #expect(row?.validMemThermalS == 2)
        #expect((row?.validThermalS ?? 0) >= (row?.validMemThermalS ?? 0))
    }
}

// MARK: - 评分口径(运行状态评估模型 v0.1)

struct StatisticsHealthScoreTests {
    /// 按列名组装一行(未指定的列保持 nil)。
    private func row(_ values: [String: Double], n: Int = 60) -> StatisticsRow {
        var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        for (name, value) in values {
            guard let index = StatisticsRow.columns.firstIndex(where: { $0.name == name }) else {
                Issue.record("未知列名:\(name)")
                continue
            }
            v[index] = value
        }
        return StatisticsRow(t: 0, n: n, values: v)
    }

    @Test func intersectionBurdenAndSampleGate() {
        // 6 小时交集内 2 分钟 serious 热:分数只轻微下降(模型 §6 示例语义)。
        let result = StatisticsHealthScore.evaluate(rows: [row([
            "valid_mem_thermal_s": 21600, "mem_normal_j_s": 21600,
            "th_nominal_j_s": 21480, "th_serious_j_s": 120, "cover_s": 21600,
        ])])
        let expected = 100 * (1 - 0.4 * (0.6 * 120 / 21600))
        #expect(abs((result?.score ?? 0) - expected) < 0.01)

        // 交集不足 30 分钟:不出总分。
        #expect(StatisticsHealthScore.evaluate(rows: [row([
            "valid_mem_thermal_s": 120, "mem_normal_j_s": 120, "th_nominal_j_s": 120, "cover_s": 120,
        ])])?.score == nil)

        // 交集只覆盖监视时长的三分之一:不出总分。
        #expect(StatisticsHealthScore.evaluate(rows: [row([
            "valid_mem_thermal_s": 3600, "mem_normal_j_s": 3600, "th_nominal_j_s": 3600, "cover_s": 10800,
        ])])?.score == nil)
    }

    @Test func memoryWarningBurdenScoresLower() {
        // 全程 warning:负担 0.6 × 权重 0.6 → 64 分。
        let result = StatisticsHealthScore.evaluate(rows: [row([
            "valid_mem_thermal_s": 3600, "mem_warn_j_s": 3600, "th_nominal_j_s": 3600, "cover_s": 3600,
        ])])
        #expect(abs((result?.score ?? 0) - 64) < 0.01)
        #expect(result?.dimensions.count == 2)
    }

    @Test func legacyRowsFallBackToStressColumns() {
        // 升级前历史没有档位秒数:整段按旧应力口径(CPU/GPU 仍参与),不与新口径混合。
        let legacy = row([
            "stress_mem_avg": 0.6, "stress_thermal_avg": 0.2, "stress_cpu_avg": 0.5, "stress_gpu_avg": 0.4,
        ])
        let result = StatisticsHealthScore.evaluate(rows: [legacy])
        let expected = 100 * (1 - (0.6 * 0.45 + 0.2 * 0.30 + 0.5 * 0.15 + 0.4 * 0.10))
        #expect(abs((result?.score ?? 0) - expected) < 0.01)
        #expect(result?.dimensions.count == 4)
        // 维度类型随结果给出:视图据此取标签与配色,不写死维度身份。
        #expect(result?.dimensions.map(\.kind) == [.cpu, .gpu, .memory, .thermal])
    }

    @Test func fullLoadWorkIntensityDoesNotReduceScore() {
        // CPU/GPU 满载属工作强度:有高负载秒数也不扣分(模型验收 1)。
        let seconds = row([
            "valid_mem_thermal_s": 3600, "mem_normal_j_s": 3600, "th_nominal_j_s": 3600, "cover_s": 3600,
            "valid_cpu_s": 3600, "cpu_high_s": 3600, "valid_gpu_s": 3600, "gpu_high_s": 3600,
        ])
        let result = StatisticsHealthScore.evaluate(rows: [seconds])
        #expect(result?.score == 100)
        #expect(result?.dimensions.count == 2)
        #expect(result?.dimensions.map(\.kind) == [.memory, .thermal])
    }
}

// MARK: - 概览展示口径(时段聚合、当前状态、范围结论、时长转换)

struct StatisticsOverviewModelTests {
    private func row(_ values: [String: Double], t: TimeInterval = 0, n: Int = 60) -> StatisticsRow {
        var v = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        for (name, value) in values {
            guard let index = StatisticsRow.columns.firstIndex(where: { $0.name == name }) else {
                Issue.record("未知列名:\(name)")
                continue
            }
            v[index] = value
        }
        return StatisticsRow(t: Int64(t), n: n, values: v)
    }

    @Test func episodesMergeConsecutiveBucketsOnly() {
        let base = TimeInterval(1_700_000_000)
        // 3 分钟连续热压力 + 1 分钟内存压力 + 缺口后的孤立热压力。
        let series = [
            row(["th_serious_s": 60, "gpu_avg": 90], t: base, n: 60),
            row(["th_serious_s": 60, "gpu_avg": 94], t: base + 60, n: 60),
            row(["th_serious_s": 60, "gpu_avg": 96], t: base + 120, n: 60),
            row(["mem_warn_s": 60, "mem_swap_avg": 2.0], t: base + 180, n: 60),
            // 缺 base+240 桶
            row(["th_serious_s": 60, "gpu_avg": 80], t: base + 300, n: 60),
        ]
        let episodes = StatisticsSummary.episodes(from: series, bucketSeconds: 60)

        #expect(episodes.count == 3)
        let thermal = episodes.filter { $0.kind == .thermal }
        #expect(thermal.count == 2)
        #expect(thermal[0].pressureSeconds == 180)
        #expect(thermal[0].spanSeconds == 180)
        #expect(thermal[1].pressureSeconds == 60, "缺口两侧不得合并为同一段")

        let memory = episodes.filter { $0.kind == .memory }
        #expect(memory.count == 1)
    }

    @Test func isolatedPressureBucketFormsOneEpisode() {
        let series = [
            row(["th_nominal_s": 60], t: 0),
            row(["th_serious_s": 60], t: 60),
            row(["th_nominal_s": 60], t: 120),
        ]
        let episodes = StatisticsSummary.episodes(from: series, bucketSeconds: 60)
        #expect(episodes.count == 1)
        #expect(episodes[0].kind == .thermal)
        #expect(episodes[0].pressureSeconds == 60)
        #expect(episodes[0].spanSeconds == 60)
    }

    @Test func bucketWidthIgnoresLeadingGap() {
        // 首两桶之间横跨 6 小时缺口:桶宽取相邻间隔的最小值,不能把缺口当桶宽
        // (否则缺口两侧的压力会被并成一段,时段结束点也被抬高)。
        let base = TimeInterval(1_700_000_000)
        let gapped = [
            row(["th_serious_s": 60], t: base),
            row(["th_serious_s": 60], t: base + 6 * 3600),
            row(["th_serious_s": 60], t: base + 6 * 3600 + 60),
        ]
        #expect(StatisticsOverviewModel.bucketSeconds(for: .today, series: gapped) == 60)

        let episodes = StatisticsSummary.episodes(
            from: gapped,
            bucketSeconds: StatisticsOverviewModel.bucketSeconds(for: .today, series: gapped)
        )
        // 缺口两侧各成一段,只有后两桶连续。
        #expect(episodes.count == 2)
        #expect(episodes[0].spanSeconds == 60)
        #expect(episodes[1].pressureSeconds == 120)
    }

    @Test func bucketWidthFallsBackWhenEveryBucketIsIsolated() {
        // 只有两个相距 6 小时的桶:没有任何相邻对可依据,退回范围默认粒度,
        // 而不是把 6 小时当成桶宽。周/月的默认是小时层。
        let base = TimeInterval(1_700_000_000)
        let twoFarApart = [
            row(["cover_s": 60], t: base),
            row(["cover_s": 60], t: base + 6 * 3600),
        ]
        #expect(StatisticsOverviewModel.bucketSeconds(for: .today, series: twoFarApart) == 60)
        #expect(StatisticsOverviewModel.bucketSeconds(for: .week, series: twoFarApart) == 3600)
        #expect(StatisticsOverviewModel.bucketSeconds(for: .today, series: []) == 60)

        // 小时层的正常序列按 3600 认。
        let hourly = [
            row(["cover_s": 3600], t: base),
            row(["cover_s": 3600], t: base + 3600),
        ]
        #expect(StatisticsOverviewModel.bucketSeconds(for: .week, series: hourly) == 3600)
    }

    @Test func currentStatusTakesWorstLevelInLastBucket() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let latest = row([
            "valid_mem_s": 60, "mem_normal_s": 30, "mem_warn_s": 30,
            "valid_thermal_s": 60, "th_nominal_s": 60,
        ], t: now.timeIntervalSince1970 - 60)
        let status = StatisticsOverviewModel.currentStatus(latest: latest, now: now)
        #expect(status?.isFresh == true)
        #expect(status?.memoryLevel == 1)
        #expect(status?.thermalLevel == 0)

        // 没有档位秒数的旧行:该维度算未知,而不是正常。
        let legacy = row(["cover_s": 60], t: now.timeIntervalSince1970 - 60)
        let legacyStatus = StatisticsOverviewModel.currentStatus(latest: legacy, now: now)
        #expect(legacyStatus?.memoryLevel == nil)
        #expect(legacyStatus?.thermalLevel == nil)
        #expect(legacyStatus?.hasAnyLevel == false)
    }

    @Test func currentStatusGoesStaleWithoutNewObservation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let latest = row([
            "valid_mem_s": 60, "mem_crit_s": 60, "valid_thermal_s": 60, "th_nominal_s": 60,
        ], t: now.timeIntervalSince1970 - 20 * 60)
        let status = StatisticsOverviewModel.currentStatus(latest: latest, now: now)
        #expect(status?.isFresh == false, "20 分钟没有新观测不得算作当前状态")
        #expect(status?.memoryLevel == 2, "最后观测到的档位仍要保留,供「最后观测到」陈述")
    }

    @Test func eventStatesDistinguishOngoingRecoveredAndInterrupted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let bucket: TimeInterval = 60

        // 压力延伸到末尾观测且观测新鲜 → 持续中。
        let ongoing = [
            row(["valid_mem_s": 60, "mem_warn_s": 60], t: now.timeIntervalSince1970 - 180),
            row(["valid_mem_s": 60, "mem_warn_s": 60], t: now.timeIntervalSince1970 - 120),
            row(["valid_mem_s": 60, "mem_warn_s": 60], t: now.timeIntervalSince1970 - 60),
        ]
        let ongoingEvents = StatisticsOverviewModel.events(from: ongoing, bucketSeconds: bucket, now: now)
        #expect(ongoingEvents.count == 1)
        #expect(ongoingEvents[0].state == .ongoing)
        #expect(ongoingEvents[0].kind == .memory)

        // 之后有观测且无压力 → 已恢复。
        let recovered = ongoing + [
            row(["valid_mem_s": 60, "mem_normal_s": 60], t: now.timeIntervalSince1970),
        ]
        let recoveredEvents = StatisticsOverviewModel.events(from: recovered, bucketSeconds: bucket, now: now)
        #expect(recoveredEvents[0].state == .recovered)

        // 压力之后没有新观测(观测已过期)→ 观测中断,不得说已恢复。
        let interrupted = [
            row(["valid_mem_s": 60, "mem_warn_s": 60], t: now.timeIntervalSince1970 - 30 * 60),
            row(["valid_mem_s": 60, "mem_warn_s": 60], t: now.timeIntervalSince1970 - 29 * 60),
        ]
        let interruptedEvents = StatisticsOverviewModel.events(from: interrupted, bucketSeconds: bucket, now: now)
        #expect(interruptedEvents[0].state == .interrupted)
        #expect(interruptedEvents[0].pressureSeconds == 120, "中断不得继续累计持续时间")
    }

    @Test func conclusionCoversEmptyInsufficientQuietAndEvents() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(StatisticsOverviewModel.conclusion(row: nil, events: []) == .noObservation)

        // 记录太短:不出结论,也不说成正常。
        let short = row(["cover_s": 300, "valid_mem_thermal_s": 300], t: 0)
        #expect(StatisticsOverviewModel.conclusion(row: short, events: []) == .insufficient(recordedSeconds: 300))

        // 观测充分且无事件:安静结论。
        let quiet = row(["cover_s": 7200, "valid_mem_thermal_s": 7200], t: 0)
        #expect(StatisticsOverviewModel.conclusion(row: quiet, events: []) == .quiet(recordedSeconds: 7200))

        // 有事件时优先陈述事件(即使覆盖不足,已观测到的事实不隐藏)。
        let event = StatisticsOverviewModel.Event(
            kind: .memory,
            start: now.addingTimeInterval(-180),
            end: now,
            pressureSeconds: 180,
            state: .recovered
        )
        let withEvent = StatisticsOverviewModel.conclusion(row: short, events: [event])
        #expect(withEvent == .events(leading: event, additionalCount: 0, recordedSeconds: 300))
    }

    @Test func memoryPressureStatusKeepsNormalUnknownAndInsufficientApart() {
        // 无有效观测(旧库行没有档位秒数)→ 暂无数据,不写「正常」。
        #expect(StatisticsOverviewModel.memoryPressureStatus(row(["cover_s": 600], t: 0)) == .noObservation)

        // 真实非零压力 → 累计时长。
        let pressured = row([
            "cover_s": 600, "valid_mem_s": 600, "mem_normal_s": 420, "mem_warn_s": 180,
        ], t: 0)
        #expect(StatisticsOverviewModel.memoryPressureStatus(pressured) == .pressure(seconds: 180))

        // 有观测但不足以判断 → 记录不足,不得显示为正常。
        let short = row([
            "cover_s": 1200, "valid_mem_s": 1200, "mem_normal_s": 1200,
        ], t: 0)
        #expect(StatisticsOverviewModel.memoryPressureStatus(short) == .insufficient)

        // 观测充分且无压力 → 正常。
        let quiet = row([
            "cover_s": 7800, "valid_mem_s": 7800, "mem_normal_s": 7800, "valid_mem_thermal_s": 7800,
        ], t: 0)
        #expect(StatisticsOverviewModel.memoryPressureStatus(quiet) == .normal)
    }

    @Test func leadingEventPrefersOngoingThenInterrupted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recovered = StatisticsOverviewModel.Event(
            kind: .thermal, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-3000),
            pressureSeconds: 600, state: .recovered
        )
        let interrupted = StatisticsOverviewModel.Event(
            kind: .memory, start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-540),
            pressureSeconds: 60, state: .interrupted
        )
        #expect(StatisticsOverviewModel.leadingEvent([recovered, interrupted]) == interrupted)

        let ongoing = StatisticsOverviewModel.Event(
            kind: .memory, start: now.addingTimeInterval(-120), end: now,
            pressureSeconds: 120, state: .ongoing
        )
        #expect(StatisticsOverviewModel.leadingEvent([recovered, interrupted, ongoing]) == ongoing)
    }

    @Test func pressureKindsMergePerDimensionFromAggregateRow() {
        let aggregate = row([
            "mem_warn_s": 180, "mem_crit_s": 60,
            "th_serious_s": 300, "cover_s": 7800,
        ], t: 0)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let memoryEvent = StatisticsOverviewModel.Event(
            kind: .memory, start: now.addingTimeInterval(-1200), end: now.addingTimeInterval(-900),
            pressureSeconds: 240, state: .ongoing
        )
        let thermalEvent = StatisticsOverviewModel.Event(
            kind: .thermal, start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-300),
            pressureSeconds: 300, state: .recovered
        )

        let kinds = StatisticsOverviewModel.pressureKinds(row: aggregate, events: [thermalEvent, memoryEvent])
        // 持续中的一类排在前;秒数取聚合行(与指标行同口径),不是单条事件的时长。
        #expect(kinds.count == 2)
        #expect(kinds[0].kind == .memory)
        #expect(kinds[0].seconds == 240)
        #expect(kinds[0].state == .ongoing)
        // 档位组成按严重度从高到低,来自聚合行的档位秒数。
        #expect(kinds[0].levels == [
            StatisticsOverviewModel.PressureLevel(level: 2, seconds: 60),
            StatisticsOverviewModel.PressureLevel(level: 1, seconds: 180),
        ])
        #expect(kinds[0].worstLevel?.level == 2)
        #expect(kinds[1].kind == .thermal)
        #expect(kinds[1].seconds == 300)
        #expect(kinds[1].state == .recovered)
        #expect(kinds[1].levels == [StatisticsOverviewModel.PressureLevel(level: 2, seconds: 300)])

        // 同一维度多条事件:归成一类(不按事件条数计数),秒数仍是该维度的合计。
        let second = StatisticsOverviewModel.Event(
            kind: .memory, start: now.addingTimeInterval(-300), end: now,
            pressureSeconds: 400, state: .ongoing
        )
        let merged = StatisticsOverviewModel.pressureKinds(row: aggregate, events: [memoryEvent, second])
        #expect(merged.count == 1)
        #expect(merged[0].seconds == 240)
        #expect(merged[0].state == .ongoing)

        // 聚合行缺失时退到事件累计。
        let fallback = StatisticsOverviewModel.pressureKinds(row: nil, events: [memoryEvent])
        #expect(fallback.first?.seconds == 240)
        #expect(fallback.first?.state == .ongoing)
    }
}

struct StatisticsDisplayFormatTests {
    @Test func durationPartsSplitHoursMinutesAndUnderMinute() {
        #expect(StatisticsDisplayFormat.durationParts(0) == .init(hours: 0, minutes: 0, isUnderMinute: false))
        #expect(StatisticsDisplayFormat.durationParts(30) == .init(hours: 0, minutes: 0, isUnderMinute: true))
        #expect(StatisticsDisplayFormat.durationParts(59.9) == .init(hours: 0, minutes: 0, isUnderMinute: true))
        #expect(StatisticsDisplayFormat.durationParts(60) == .init(hours: 0, minutes: 1, isUnderMinute: false))
        #expect(StatisticsDisplayFormat.durationParts(780) == .init(hours: 0, minutes: 13, isUnderMinute: false))
        #expect(StatisticsDisplayFormat.durationParts(3600) == .init(hours: 1, minutes: 0, isUnderMinute: false))
        #expect(StatisticsDisplayFormat.durationParts(4800) == .init(hours: 1, minutes: 20, isUnderMinute: false))
    }

    @Test func percentDropsMeaninglessDecimal() {
        #expect(StatisticsDisplayFormat.percent(24) == "24%")
        #expect(StatisticsDisplayFormat.percent(24.04) == "24%")
        #expect(StatisticsDisplayFormat.percent(62.34) == "62.3%")
        #expect(StatisticsDisplayFormat.percent(0) == "0%")
    }

    @Test func bytesKeepOnlyMeaningfulDecimals() {
        #expect(StatisticsDisplayFormat.bytes(0) == "0 B")
        #expect(StatisticsDisplayFormat.bytes(512) == "512 B")
        #expect(StatisticsDisplayFormat.bytes(1.5e9) == "1.5 GB")
        #expect(StatisticsDisplayFormat.bytes(124.07e9) == "124 GB")
        #expect(StatisticsDisplayFormat.bytes(9.87e6) == "9.9 MB")
        #expect(StatisticsDisplayFormat.bytes(2.5e12) == "2.5 TB")
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

    @Test func storageInfoFourCategorySumEqualsTotal() {
        let info = StatisticsRecorder.StorageInfo(
            metricBytes: 1000,
            appBytes: 2000,
            reportBytes: 500,
            systemBytes: 300,
            minuteCount: 10,
            hourCount: 2,
            dayCount: 1
        )
        #expect(info.totalBytes == 3800)
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
