import Foundation
import OSLog
import SQLite3

/// 单库磁盘占用的两方分解。有效数据 = 在用页中扣除表结构页的部分 + 未合并的
/// WAL 写入;系统侧 = 表结构页 + 空闲页(已删行、待复用) + WAL 索引文件。
struct StorageBreakdown: Equatable {
    var dataBytes: Int64 = 0
    var systemBytes: Int64 = 0

    static let zero = StorageBreakdown()
}

/// 数值列的跨粒度聚合方式:
/// - weightedAverage: 上层均值 = Σ(下层均值×下层n) / Σn(占比型同此口径)
/// - maximum:         取下层最大值(峰值)
/// - total:           求和(速率积分出的字节总量)
enum StatisticsAggregation {
    case weightedAverage
    case maximum
    case total
}

/// 一行统计数据。分/时/日三张表共用同一组数值列;列顺序由 `columns` 单一来源
/// 决定,同时是 SQL 建表列序与报表 JSON 的列序契约。
struct StatisticsRow: Equatable {
    /// 桶起点(unix 秒)。分=分钟起点,时=本地小时起点,日=本地日起点。
    var t: Int64
    /// 该桶内采到的帧数(加权平均的权重)。
    var n: Int

    var cpuAvg: Double?
    var cpuMax: Double?
    var cpuSysAvg: Double?
    var cpuUserAvg: Double?
    var cpuPAvg: Double?
    var cpuEAvg: Double?
    var cpuThermalAvg: Double?
    var cpuTempAvg: Double?
    var gpuAvg: Double?
    var gpuMax: Double?
    var gpuTilerAvg: Double?
    var gpuMemAvg: Double?
    var memPctAvg: Double?
    var memPctMax: Double?
    var memUsedAvg: Double?
    var memCompAvg: Double?
    var memSwapAvg: Double?
    var memPressureAvg: Double?
    var netDown: Double?
    var netUp: Double?
    var netDownPeak: Double?
    var netUpPeak: Double?
    var diskRead: Double?
    var diskWrite: Double?
    var diskReadPeak: Double?
    var diskWritePeak: Double?
    var battLevelAvg: Double?
    var acFrac: Double?
    var chargingFrac: Double?
    var battTempAvg: Double?
    var powerAvg: Double?
    var powerMax: Double?
    var fanAvg: Double?
    var fanMax: Double?
    /// 系统开机至今年秒数(ProcessInfo.systemUptime),用于重启检测与开机时长。
    var uptimeAvg: Double?
    /// 帧级应力(0~1)的桶均值:落库时按帧算好,消除「非线性曲线 × 桶均值」的抹平偏差。
    var stressMemAvg: Double?
    var stressThermalAvg: Double?
    var stressCpuAvg: Double?
    var stressGpuAvg: Double?
    /// 桶内真实被采样覆盖的墙钟秒数(total 聚合):「活跃时长」口径的数据源。
    /// 帧数 n 只是应用批次计数,采样节奏/失败/推迟都会让它偏离真实时间。
    var coverS: Double?

    /// (列名, 聚合方式, 字段读写)。顺序即表列序/JSON 列序。
    static let columns: [(name: String, aggregation: StatisticsAggregation)] = [
        ("cpu_avg", .weightedAverage),
        ("cpu_max", .maximum),
        ("cpu_sys_avg", .weightedAverage),
        ("cpu_user_avg", .weightedAverage),
        ("cpu_p_avg", .weightedAverage),
        ("cpu_e_avg", .weightedAverage),
        ("cpu_thermal_avg", .weightedAverage),
        ("cpu_temp_avg", .weightedAverage),
        ("gpu_avg", .weightedAverage),
        ("gpu_max", .maximum),
        ("gpu_tiler_avg", .weightedAverage),
        ("gpu_mem_avg", .weightedAverage),
        ("mem_pct_avg", .weightedAverage),
        ("mem_pct_max", .maximum),
        ("mem_used_avg", .weightedAverage),
        ("mem_comp_avg", .weightedAverage),
        ("mem_swap_avg", .weightedAverage),
        ("mem_pressure_avg", .weightedAverage),
        ("net_down", .total),
        ("net_up", .total),
        ("net_down_peak", .maximum),
        ("net_up_peak", .maximum),
        ("disk_read", .total),
        ("disk_write", .total),
        ("disk_read_peak", .maximum),
        ("disk_write_peak", .maximum),
        ("batt_level_avg", .weightedAverage),
        ("ac_frac", .weightedAverage),
        ("charging_frac", .weightedAverage),
        ("batt_temp_avg", .weightedAverage),
        ("power_avg", .weightedAverage),
        ("power_max", .maximum),
        ("fan_avg", .weightedAverage),
        ("fan_max", .maximum),
        ("uptime_avg", .weightedAverage),
        // 应力列追加末尾:旧库经 ALTER 迁移补 NULL,评分侧对 NULL 走均值回退。
        ("stress_mem_avg", .weightedAverage),
        ("stress_thermal_avg", .weightedAverage),
        ("stress_cpu_avg", .weightedAverage),
        ("stress_gpu_avg", .weightedAverage),
        // 采样覆盖秒数(总量):旧库 ALTER 迁移补 NULL,读取侧回退帧数口径。
        ("cover_s", .total),
    ]

    /// 按 columns 顺序输出数值(nil 列保持 nil),供 SQL 绑定与 JSON 编码复用。
    var values: [Double?] {
        [
            cpuAvg, cpuMax, cpuSysAvg, cpuUserAvg, cpuPAvg, cpuEAvg,
            cpuThermalAvg, cpuTempAvg,
            gpuAvg, gpuMax, gpuTilerAvg, gpuMemAvg,
            memPctAvg, memPctMax, memUsedAvg, memCompAvg, memSwapAvg, memPressureAvg,
            netDown, netUp, netDownPeak, netUpPeak,
            diskRead, diskWrite, diskReadPeak, diskWritePeak,
            battLevelAvg, acFrac, chargingFrac, battTempAvg,
            powerAvg, powerMax,
            fanAvg, fanMax, uptimeAvg,
            stressMemAvg, stressThermalAvg, stressCpuAvg, stressGpuAvg,
            coverS,
        ]
    }

    init(t: Int64, n: Int, values: [Double?] = Array(repeating: nil, count: StatisticsRow.columns.count)) {
        self.t = t
        self.n = n
        let v = values
        self.cpuAvg = v[0]; self.cpuMax = v[1]; self.cpuSysAvg = v[2]; self.cpuUserAvg = v[3]
        self.cpuPAvg = v[4]; self.cpuEAvg = v[5]; self.cpuThermalAvg = v[6]; self.cpuTempAvg = v[7]
        self.gpuAvg = v[8]; self.gpuMax = v[9]; self.gpuTilerAvg = v[10]; self.gpuMemAvg = v[11]
        self.memPctAvg = v[12]; self.memPctMax = v[13]; self.memUsedAvg = v[14]
        self.memCompAvg = v[15]; self.memSwapAvg = v[16]; self.memPressureAvg = v[17]
        self.netDown = v[18]; self.netUp = v[19]; self.netDownPeak = v[20]; self.netUpPeak = v[21]
        self.diskRead = v[22]; self.diskWrite = v[23]; self.diskReadPeak = v[24]; self.diskWritePeak = v[25]
        self.battLevelAvg = v[26]; self.acFrac = v[27]; self.chargingFrac = v[28]
        self.battTempAvg = v[29]
        self.powerAvg = v[30]; self.powerMax = v[31]
        self.fanAvg = v[32]; self.fanMax = v[33]
        self.uptimeAvg = v[34]
        self.stressMemAvg = v[35]; self.stressThermalAvg = v[36]
        self.stressCpuAvg = v[37]; self.stressGpuAvg = v[38]
        self.coverS = v[39]
    }

    /// stress 列缺值时,用该行已有的指标列走 fallback 重算近似应力。
    /// 无 stress 值的历史行离散档位不可得,只能用连续值近似。
    func stressFallback(index: Int) -> Double? {
        switch index {
        case Self.index("stress_mem_avg"):
            return memPressureAvg.map { StatisticsHealthScore.stressMem(percent: $0, level: nil) }
        case Self.index("stress_thermal_avg"):
            guard cpuThermalAvg != nil || cpuTempAvg != nil else { return nil }
            return StatisticsHealthScore.stressThermal(state: cpuThermalAvg, temp: cpuTempAvg)
        case Self.index("stress_cpu_avg"):
            return cpuAvg.map { StatisticsHealthScore.stressCPU($0) }
        case Self.index("stress_gpu_avg"):
            return gpuAvg.map { StatisticsHealthScore.stressGPU($0) }
        default:
            return nil
        }
    }

    /// 列名 → 列序号,列不存在时返回 -1。
    private static func index(_ name: String) -> Int {
        columns.firstIndex { $0.name == name } ?? -1
    }

    /// 把多行聚合成一个上层桶。均值按 n 加权,峰值取最大,总量求和;
    /// 参与聚合的子桶缺少某列时该列按「有值的子桶」聚合。
    /// stress 列缺值时不能跳过(会让分母缩小、偏差放大),逐行走 fallback
    /// 用已有的指标列重算后再参与加权平均。
    static func aggregate(_ rows: [StatisticsRow], t: Int64) -> StatisticsRow? {
        guard !rows.isEmpty else { return nil }
        var out = StatisticsRow(t: t, n: rows.reduce(0) { $0 + $1.n })
        var outValues = out.values
        for (index, column) in columns.enumerated() {
            let columnValues = rows.compactMap { $0.values[index] }
            guard !columnValues.isEmpty else { continue }
            switch column.aggregation {
            case .weightedAverage:
                var weightedSum = 0.0
                var weightSum = 0
                for row in rows {
                    var value = row.values[index]
                    // stress 列 null 时按该行已有指标列走 fallback,避免分母缩小
                    if value == nil, let fallback = row.stressFallback(index: index) {
                        value = fallback
                    }
                    guard let value, row.n > 0 else { continue }
                    weightedSum += value * Double(row.n)
                    weightSum += row.n
                }
                outValues[index] = weightSum > 0 ? weightedSum / Double(weightSum) : nil
            case .maximum:
                outValues[index] = columnValues.max()
            case .total:
                outValues[index] = columnValues.reduce(0, +)
            }
        }
        out = StatisticsRow(t: t, n: out.n, values: outValues)
        return out
    }
}

/// SQLite 统计库。所有公开方法内部经串行队列同步执行,可从任意线程调用;
/// 写入只发生在分钟封口/汇总/清理三类低频操作上,常年零 IO。
final class StatisticsDatabase {
    /// 分钟行保留窗口(汇总完成后才清理,先汇总后清理见 `maintain`)。
    static let minuteRetention: TimeInterval = 45 * 86400
    static let hourRetention: TimeInterval = 400 * 86400

    private var handle: OpaquePointer?
    private let url: URL
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.statistics-db", qos: .utility)
    private let calendar: Calendar

    init(url: URL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
        queue.sync {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            let openResult = sqlite3_open_v2(url.path, &handle, flags, nil)
            guard openResult == SQLITE_OK, let handle else {
                if let handle {
                    AppLogger.sampler.error("Statistics database open failed (\(openResult)): \(String(cString: sqlite3_errmsg(handle)))")
                    sqlite3_close_v2(handle)
                    self.handle = nil
                } else {
                    AppLogger.sampler.error("Statistics database open failed (\(openResult))")
                }
                return
            }
            sqlite3_busy_timeout(handle, 5_000)
            execute("PRAGMA journal_mode=WAL")
            execute("PRAGMA synchronous=NORMAL")
            // 增量汇总水位表:记录每个 source→target 上次汇总的 boundary,使 maintain
            // 只重算新封口的桶,而非从源表最早行全量重扫。
            execute("CREATE TABLE IF NOT EXISTS stats_meta (key TEXT PRIMARY KEY, value REAL)")
            for table in ["minute", "hour", "day"] {
                let columnSQL = StatisticsRow.columns.map { "\($0.name) REAL" }.joined(separator: ", ")
                execute("CREATE TABLE IF NOT EXISTS stats_\(table) (t INTEGER PRIMARY KEY, \(columnSQL), n INTEGER NOT NULL DEFAULT 0)")
                execute("CREATE INDEX IF NOT EXISTS idx_stats_\(table)_t ON stats_\(table)(t)")
                // 旧库升级:CREATE IF NOT EXISTS 不会补新列,逐列 ALTER
                let existing = columnNames(of: table)
                for column in StatisticsRow.columns where !existing.contains(column.name) {
                    execute("ALTER TABLE stats_\(table) ADD COLUMN \(column.name) REAL")
                }
            }
        }
    }

    deinit {
        if let handle {
            // 关库前把 WAL 合并进主库文件,避免残留 -wal/-shm 旁文件。
            sqlite3_exec(handle, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
            sqlite3_close_v2(handle)
        }
    }

    // MARK: - 写入与维护

    /// 插入(或覆盖)一行分钟数据。
    func insertMinuteRow(_ row: StatisticsRow) {
        queue.sync { insertRow(row, into: "minute") }
    }

    /// 增量汇总:把已完成的小时从分钟行汇总、已完成的日从小时行汇总,
    /// 并按保留窗口清理旧行。每次分钟落库后调用,通过水位只重算新封口的桶,
    /// 单次开销与数据总量无关(见 `rollUp` 的 watermarkKey 参数)。
    func maintain(now: Date) {
        queue.sync {
            let nowInterval = now.timeIntervalSince1970
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start.timeIntervalSince1970 ?? nowInterval
            let currentDay = calendar.startOfDay(for: now).timeIntervalSince1970
            rollUp(source: "minute", target: "hour", boundary: currentHour, bucketUnit: .hour, watermarkKey: Self.watermarkMinuteHour)
            rollUp(source: "hour", target: "day", boundary: currentDay, bucketUnit: .day, watermarkKey: Self.watermarkHourDay)
            execute("DELETE FROM stats_minute WHERE t < \(Int64(nowInterval - Self.minuteRetention))")
            execute("DELETE FROM stats_hour WHERE t < \(Int64(nowInterval - Self.hourRetention))")
        }
    }

    /// source → target 的增量汇总:从上次汇总水位重扫到 boundary。
    /// 水位语义 = 上次调用的 boundary(整点/整日),因此下次只处理新封口的一个桶;
    /// 首次(无水位)从源表最早行全量重扫一次,补齐历史缺列(stress 列回填)。
    /// 按本地时区切桶,空桶跳过。汇总完成后把水位推进到本次 boundary。
    private func rollUp(source: String, target: String, boundary: TimeInterval, bucketUnit: Calendar.Component, watermarkKey: String) {
        let bucketSeconds: TimeInterval = bucketUnit == .hour ? 3600 : 86400
        let resumeFrom: TimeInterval
        if let watermark = metaValue(for: watermarkKey) {
            resumeFrom = watermark
        } else if let minSource = scalarQuery("SELECT MIN(t) FROM stats_\(source)") {
            // 首次(或水位被删除):从源表最早行全量重扫,确保老目标行被重算。
            resumeFrom = minSource
        } else if let maxTarget = scalarQuery("SELECT MAX(t) FROM stats_\(target)") {
            resumeFrom = maxTarget - bucketSeconds
        } else {
            return
        }

        var cursor = Date(timeIntervalSince1970: resumeFrom)
        let boundaryDate = Date(timeIntervalSince1970: boundary)
        while cursor < boundaryDate {
            guard let bucketStart = calendar.dateInterval(of: bucketUnit, for: cursor)?.start else { break }
            let bucketEnd = calendar.date(byAdding: bucketUnit, value: 1, to: bucketStart) ?? bucketStart.addingTimeInterval(bucketSeconds)
            if bucketEnd > boundaryDate { break }
            let rows = fetchRows(from: source, from: bucketStart.timeIntervalSince1970, to: bucketEnd.timeIntervalSince1970)
            if let aggregated = StatisticsRow.aggregate(rows, t: Int64(bucketStart.timeIntervalSince1970)) {
                insertRow(aggregated, into: target)
            }
            cursor = bucketEnd
        }
        setMeta(boundary, for: watermarkKey)
    }

    // MARK: - 汇总水位

    private static let watermarkMinuteHour = "rollup.minute_hour.watermark"
    private static let watermarkHourDay = "rollup.hour_day.watermark"

    /// SQLITE_TRANSIENT 的 Swift 等价:告诉 SQLite 在语句执行完成前复制绑定的字符串。
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func metaValue(for key: String) -> TimeInterval? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT value FROM stats_meta WHERE key = ?", -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_double(statement, 0)
    }

    private func setMeta(_ value: TimeInterval, for key: String) {
        guard let handle else { return }
        var statement: OpaquePointer?
        let sql = "INSERT INTO stats_meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.sqliteTransient)
        sqlite3_bind_double(statement, 2, value)
        sqlite3_step(statement)
    }

    /// 删除水位,使下一次 `maintain` 从源表最早行全量重扫(用于清空/范围删除后)。
    private func resetWatermarks() {
        execute("DELETE FROM stats_meta")
    }

    // MARK: - 查询

    func minuteRows(from: Date, to: Date) -> [StatisticsRow] {
        queue.sync { fetchRows(from: "minute", from: from.timeIntervalSince1970, to: to.timeIntervalSince1970) }
    }

    func hourRows(from: Date, to: Date) -> [StatisticsRow] {
        queue.sync { fetchRows(from: "hour", from: from.timeIntervalSince1970, to: to.timeIntervalSince1970) }
    }

    func dayRows(from: Date, to: Date) -> [StatisticsRow] {
        queue.sync { fetchRows(from: "day", from: from.timeIntervalSince1970, to: to.timeIntervalSince1970) }
    }

    /// 最早一条记录的时间(全部粒度取最小),无数据返回 nil。
    var earliestRecord: Date? {
        queue.sync {
            let candidates = ["minute", "hour", "day"].compactMap { scalarQuery("SELECT MIN(t) FROM stats_\($0)") }
            return candidates.min().map { Date(timeIntervalSince1970: $0) }
        }
    }

    /// 库文件字节数(含 WAL,供设置页展示占用)。
    var fileSize: Int64? {
        queue.sync {
            let candidates = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            var total: Int64 = 0
            for candidate in candidates {
                if let size = (try? FileManager.default.attributesOfItem(atPath: candidate.path))?[.size] as? Int64 {
                    total += size
                }
            }
            return total > 0 ? total : nil
        }
    }

    // MARK: - 存储管理

    /// 三层行数(供设置页存储管理展示记录规模)。
    var rowCounts: (minute: Int64, hour: Int64, day: Int64) {
        queue.sync {
            (rowCount("minute"), rowCount("hour"), rowCount("day"))
        }
    }

    /// 删除三层中早于指定时刻的行,并收缩文件使占用立即回落。
    /// checkpoint(TRUNCATE) 为防御性收尾:清掉 VACUUM 后可能残留的 WAL 帧,
    /// 让文件占用统计立即归位。
    func deleteBefore(_ date: Date) {
        queue.sync {
            let cutoff = Int64(date.timeIntervalSince1970)
            execute("DELETE FROM stats_minute WHERE t < \(cutoff)")
            execute("DELETE FROM stats_hour WHERE t < \(cutoff)")
            execute("DELETE FROM stats_day WHERE t < \(cutoff)")
            execute("VACUUM")
            execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// 清空全部统计数据并收缩文件。
    func deleteAll() {
        queue.sync {
            execute("DELETE FROM stats_minute")
            execute("DELETE FROM stats_hour")
            execute("DELETE FROM stats_day")
            resetWatermarks()
            execute("VACUUM")
            execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// 删除 [from, to) 区间内的三层行(按桶选择性清理),并收缩文件。
    func deleteRange(from: Date, to: Date) {
        queue.sync {
            let lo = Int64(from.timeIntervalSince1970)
            let hi = Int64(to.timeIntervalSince1970)
            for table in ["minute", "hour", "day"] {
                execute("DELETE FROM stats_\(table) WHERE t >= \(lo) AND t < \(hi)")
            }
            // 范围删除可能落在水位之后(会影响后续汇总),重置水位触发一次全量重算。
            resetWatermarks()
            execute("VACUUM")
            execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    private func rowCount(_ table: String) -> Int64 {
        Int64(scalarQuery("SELECT COUNT(*) FROM stats_\(table)") ?? 0)
    }

    // MARK: - SQLite 基础设施

    /// 空库表结构页字节(main 文件,checkpoint 后实测)。作为占用分解里
    /// 「结构」与「数据」的分界线,schema 演进后测量值自动跟随。
    /// 进程内只测一次。
    static let schemaMainBytes: Int64 = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-schema-probe-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let probe = StatisticsDatabase(url: url)
        probe.deleteAll()
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
    }()

    /// 库文件占用的数据/系统两方分解(口径见 StorageBreakdown)。
    /// main 按文件实际大小扣除结构页与空闲页——未 checkpoint 的新增页尚在
    /// WAL 侧,不含在 main 里,与 walBytes 相加不重复;空闲页整块归系统侧。
    var breakdown: StorageBreakdown {
        queue.sync {
            func fileSize(_ path: String) -> Int64 {
                (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0
            }
            let walBytes = fileSize(url.path + "-wal")
            let shmBytes = fileSize(url.path + "-shm")
            guard handle != nil else { return .zero }
            let pageSize = Int64(scalarQuery("PRAGMA page_size") ?? 4096)
            let freeCount = Int64(scalarQuery("PRAGMA freelist_count") ?? 0)
            let schemaBytes = Self.schemaMainBytes
            let dataOnMain = max(fileSize(url.path) - schemaBytes - freeCount * pageSize, 0)
            return StorageBreakdown(
                dataBytes: dataOnMain + walBytes,
                systemBytes: schemaBytes + freeCount * pageSize + shmBytes
            )
        }
    }

    /// 读表的现有列名,供迁移判断。
    private func columnNames(of table: String) -> Set<String> {
        guard let handle else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA table_info(stats_\(table))", -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 1)
            if let name { names.insert(String(cString: name)) }
        }
        return names
    }

    private func execute(_ sql: String) {
        guard let handle else { return }
        var errorText: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorText) == SQLITE_OK else {
            if let errorText {
                AppLogger.sampler.error("Statistics SQL failed: \(String(cString: errorText)) — \(sql)")
                sqlite3_free(errorText)
            }
            return
        }
    }

    private func scalarQuery(_ sql: String) -> TimeInterval? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return TimeInterval(sqlite3_column_double(statement, 0))
    }

    private func insertRow(_ row: StatisticsRow, into table: String) {
        guard let handle else { return }
        let names = ["t"] + StatisticsRow.columns.map(\.name) + ["n"]
        let placeholders = names.map { _ in "?" }.joined(separator: ", ")
        let sql = "INSERT OR REPLACE INTO stats_\(table) (\(names.joined(separator: ", "))) VALUES (\(placeholders))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, row.t)
        for (index, value) in row.values.enumerated() {
            if let value {
                sqlite3_bind_double(statement, Int32(index + 2), value)
            } else {
                sqlite3_bind_null(statement, Int32(index + 2))
            }
        }
        sqlite3_bind_int64(statement, Int32(row.values.count + 2), Int64(row.n))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            AppLogger.sampler.error("Statistics insert failed: \(String(cString: sqlite3_errmsg(handle)))")
            return
        }
    }

    private func fetchRows(from table: String, from: TimeInterval, to: TimeInterval) -> [StatisticsRow] {
        guard let handle else { return [] }
        // 显式列名取数,不依赖物理列序:ALTER 迁移把新列追加在 n 之后,
        // SELECT * 的位置假设会把 n 读错。
        let sql = "SELECT t, " + StatisticsRow.columns.map(\.name).joined(separator: ", ")
            + ", n FROM stats_\(table) WHERE t >= ? AND t < ? ORDER BY t"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(from))
        sqlite3_bind_int64(statement, 2, Int64(to))

        var rows: [StatisticsRow] = []
        let columnCount = StatisticsRow.columns.count
        while sqlite3_step(statement) == SQLITE_ROW {
            let t = sqlite3_column_int64(statement, 0)
            var values: [Double?] = []
            values.reserveCapacity(columnCount)
            for index in 0..<columnCount {
                let columnIndex = Int32(index + 1)
                values.append(sqlite3_column_type(statement, columnIndex) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(statement, columnIndex))
            }
            let n = Int(sqlite3_column_int64(statement, Int32(columnCount + 1)))
            rows.append(StatisticsRow(t: t, n: n, values: values))
        }
        return rows
    }
}
