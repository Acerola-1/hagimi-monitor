import Foundation
import Combine

/// 统计记录器:把 MonitorStore 每秒发布的模块帧在主线程做轻量累加(纯内存),
/// 分钟封口后交后台串行队列落库并维护汇总表。速率型指标(网络/磁盘)以
/// 「上次速率 × 距上次观测时长」分段积分成字节总量;间隔超过 30s 视为睡眠/间隙,
/// 该段丢弃——睡眠时段在报表里呈现为空隙而非补零。

/// 设置页「数据统计」的概览范围:今日 / 近 7 日 / 近 30 日,整组卡片随范围切换。
enum StatisticsOverviewRange: CaseIterable, Hashable {
    case today
    case week
    case month

    /// 聚合窗口起点(本地时区自然日对齐)。
    func startOfDayWindow(from today: Date, calendar: Calendar) -> Date {
        switch self {
        case .today:
            return calendar.startOfDay(for: today)
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: today)) ?? today
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: today)) ?? today
        }
    }
}

/// 速率积分的分段上限:超过视为采样中断,不把旧速率外推成长时段流量。
final class StatisticsRecorder: ObservableObject {
    static let rateIntegrationCap: TimeInterval = 30

    /// 各范围的聚合行(无数据为 nil)。分钟封口后随概览一起刷新。
    @Published private(set) var rangeRows: [StatisticsOverviewRange: StatisticsRow?] = [:]
    /// 从最早一条记录至今的自然日数(0 = 尚无任何数据)。
    @Published private(set) var recordDays = 0
    /// 本地存储占用快照(统计库/应用统计库/报表文件),随概览一起刷新。
    @Published private(set) var storageInfo: StorageInfo?
    /// 本 App 使用打卡:累计活跃天数与截至今日的连续天数。
    @Published private(set) var usageTotalDays = 0
    @Published private(set) var usageStreakDays = 0
    /// 打卡日历数据:首个活跃日键与全部活跃日键(yyyymmdd)。
    @Published private(set) var usageFirstDay: Int64 = 0
    @Published private(set) var usageActiveDays: [Int64] = []

    /// 三类本地存储产物的占用与记录规模。
    struct StorageInfo: Equatable {
        var databaseBytes: Int64
        var appStatsBytes: Int64
        var reportBytes: Int64
        var minuteCount: Int64
        var hourCount: Int64
        var dayCount: Int64

        var totalBytes: Int64 { databaseBytes + appStatsBytes + reportBytes }
    }

    /// 进程/电池/打卡的 SwiftData 存储(图标随身份持久化,卸载应用不丢历史)。
    let processStore: StatisticsProcessStore?

    private let database: StatisticsDatabase?
    private let calendar: Calendar

    /// 列名 → 列下标,与 StatisticsRow.columns 的顺序契约绑定。
    private static let columnIndex: [String: Int] = {
        Dictionary(uniqueKeysWithValues: StatisticsRow.columns.enumerated().map { ($1.name, $0) })
    }()

    // MARK: - 分钟累加器(仅主线程访问)

    private struct Accumulator {
        var sums = [Double](repeating: 0, count: StatisticsRow.columns.count)
        var counts = [Int](repeating: 0, count: StatisticsRow.columns.count)
        var maximaArray: [Double?] = Array(repeating: nil, count: StatisticsRow.columns.count)
        var frames = 0

        mutating func add(_ index: Int, _ value: Double) {
            sums[index] += value
            counts[index] += 1
        }

        mutating func trackMax(_ index: Int, _ value: Double) {
            maximaArray[index] = max(maximaArray[index] ?? -.infinity, value)
        }

        func row(t: Int64) -> StatisticsRow? {
            guard frames > 0 else { return nil }
            var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            for (index, column) in StatisticsRow.columns.enumerated() {
                switch column.aggregation {
                case .weightedAverage:
                    if counts[index] > 0 { values[index] = sums[index] / Double(counts[index]) }
                case .maximum:
                    if let peak = maximaArray[index], peak > -.infinity { values[index] = peak }
                case .total:
                    if sums[index] > 0 { values[index] = sums[index] }
                }
            }
            return StatisticsRow(t: t, n: frames, values: values)
        }
    }

    private var currentMinuteStart: Int64?
    private var accumulator = Accumulator()

    // 电池慢变量(循环次数/健康度)最近一次读数,封口时按日落库。
    private var lastBatterySlow: (cycles: Double, health: Double)?
    /// 已落库的电池慢变量(日键, 值):同日同值跳过写库,
    /// 避免插电稳态下每分钟对未变化的行做一次无意义的 fetch+save。
    private var savedBattery: (day: Int64, cycles: Double, health: Double)?

    // 速率积分游标:记录各速率方向上次观测的(速率, 时刻)。
    private var lastNetDown: (rate: Double, at: Date)?
    private var lastNetUp: (rate: Double, at: Date)?
    private var lastDiskRead: (rate: Double, at: Date)?
    private var lastDiskWrite: (rate: Double, at: Date)?
    /// 上一帧时刻,用于分段累计采样覆盖秒数(cover_s)。
    private var lastFrameAt: Date?

    /// 概览/落库共用的后台队列;数据库自身另有串行队列,这里只避免主线程做 IO。
    private let maintenanceQueue = DispatchQueue(label: "com.acerola.hagimi-monitor.statistics-maintenance", qos: .utility)

    init(databaseURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        let url = databaseURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HagimiMonitor", isDirectory: true)
            .appendingPathComponent("statistics.sqlite3")
        processStore = StatisticsProcessStore.defaultDirectory().map { StatisticsProcessStore(directory: $0) }
        if let url {
            database = StatisticsDatabase(url: url, calendar: calendar)
            maintenanceQueue.async { [weak self] in
                self?.database?.maintain(now: Date())
                self?.refreshOverview()
            }
        } else {
            database = nil
        }
    }

    /// 一帧进程采样的直通入口(MonitorStore 统计定时器调用,主线程)。
    /// 网络速率为窗口均值,按 60s 统计节奏折算为分钟字节量。
    func recordProcesses(
        cpu: [TopCPUProcess],
        memory: [TopMemoryProcess],
        gpu: [TopGPUProcess],
        network: [TopNetworkProcess],
        disk: [TopDiskProcess],
        at date: Date
    ) {
        processStore?.record(
            cpu: cpu.map { (name: $0.name, pid: $0.pid, usage: $0.cpuUsage) },
            memory: memory.map { (name: $0.name, pid: $0.pid, bytes: Double($0.memoryUsage)) },
            gpu: gpu.map { (name: $0.name, pid: $0.pid, usage: $0.gpuUsage) },
            network: network.map { (name: $0.name, pid: $0.pid, downBytes: Double($0.download) * 60, upBytes: Double($0.upload) * 60) },
            disk: disk.map { (name: $0.name, pid: $0.pid, readBytes: Double($0.bytesRead), writeBytes: Double($0.bytesWritten)) },
            at: date,
            calendar: calendar
        )
    }

    // MARK: - 采集(主线程,微秒级)

    /// 记录一帧。由 MonitorStore 在每次采样成功应用后调用;各指标采样节奏
    /// (1~10s)不同,按「本帧里有什么就累加什么」独立统计,互不等待。
    func record(modules: [MonitorModule], fans: [FanInfo], at date: Date) {
        let minuteStart = Int64((date.timeIntervalSince1970 / 60).rounded(.down) * 60)
        if minuteStart != currentMinuteStart {
            sealCompletedMinute()
            currentMinuteStart = minuteStart
        }
        accumulator.frames += 1
        accumulator.add(Self.index("uptime_avg"), ProcessInfo.processInfo.systemUptime)

        // 采样覆盖秒数:与速率积分同款分段累计(间隔越界视为睡眠/中断不计)。
        // 「活跃时长」以真实墙钟为口径,不依赖「1 帧 ≈ 1 秒」的采样节奏假设--
        // 采样失败、动画推迟、未来节奏调整都不会让它失真。
        if let previous = lastFrameAt {
            let elapsed = date.timeIntervalSince(previous)
            if elapsed > 0, elapsed <= Self.rateIntegrationCap {
                accumulator.sums[Self.index("cover_s")] += elapsed
            }
        }
        lastFrameAt = date

        // 本帧各应力输入(跨模块收集,循环后统一算帧级应力)。
        var frameCPU: Double?, frameGPU: Double?, frameThermal: Double?, frameTemp: Double?
        var framePressurePct: Double?, framePressureLevel: Double?

        for module in modules where !module.isPlaceholder {
            switch module.kind {
            case .cpu:
                accumulateCPU(module)
                frameCPU = module.value
                frameThermal = numeric("thermal-pressure", in: module)
                frameTemp = numeric("temperature", in: module)
            case .gpu:
                accumulateGPU(module)
                frameGPU = module.value
            case .memory:
                accumulateMemory(module)
                framePressurePct = module.pressureValue
                framePressureLevel = numeric("pressure-level", in: module)
            case .network: accumulateNetwork(module, at: date)
            case .storage: accumulateStorage(module, at: date)
            case .battery: accumulateBattery(module)
            case .fan, .bluetooth: break
            }
        }

        // 帧级应力:非线性曲线只作用在单帧上,桶内存均值,
        // 评分侧线性重组即可,饱和尖峰不被桶均值抹平。
        if framePressurePct != nil || framePressureLevel != nil {
            accumulator.add(Self.index("stress_mem_avg"),
                            StatisticsHealthScore.stressMem(percent: framePressurePct, level: framePressureLevel))
        }
        if let frameCPU {
            accumulator.add(Self.index("stress_cpu_avg"), StatisticsHealthScore.stressCPU(frameCPU))
        }
        if let frameGPU {
            accumulator.add(Self.index("stress_gpu_avg"), StatisticsHealthScore.stressGPU(frameGPU))
        }
        if frameThermal != nil || frameTemp != nil {
            accumulator.add(Self.index("stress_thermal_avg"),
                            StatisticsHealthScore.stressThermal(state: frameThermal, temp: frameTemp))
        }

        if let maxRPM = fans.map(\.currentRPM).max(), maxRPM > 0 {
            accumulator.add(Self.index("fan_avg"), Double(maxRPM))
            accumulator.trackMax(Self.index("fan_max"), Double(maxRPM))
        }
    }

    private func accumulateCPU(_ module: MonitorModule) {
        accumulator.add(Self.index("cpu_avg"), module.value)
        accumulator.trackMax(Self.index("cpu_max"), module.value)
        if let system = numeric("system", in: module) {
            accumulator.add(Self.index("cpu_sys_avg"), system)
        }
        if let user = numeric("user", in: module) {
            accumulator.add(Self.index("cpu_user_avg"), user)
        }
        if let thermal = numeric("thermal-pressure", in: module) {
            accumulator.add(Self.index("cpu_thermal_avg"), thermal)
        }
        if let performance = numeric("core-split", in: module) {
            accumulator.add(Self.index("cpu_p_avg"), performance)
        }
        if let efficiency = module.cpuCoreDetail?.efficiencyUsage {
            accumulator.add(Self.index("cpu_e_avg"), efficiency)
        }
        if let temperature = numeric("temperature", in: module) {
            accumulator.add(Self.index("cpu_temp_avg"), temperature)
        }
    }

    private func accumulateGPU(_ module: MonitorModule) {
        accumulator.add(Self.index("gpu_avg"), module.value)
        accumulator.trackMax(Self.index("gpu_max"), module.value)
        if let tiler = numeric("tiler", in: module) {
            accumulator.add(Self.index("gpu_tiler_avg"), tiler)
        }
        if let gpuMemory = numeric("gpu-memory", in: module) {
            accumulator.add(Self.index("gpu_mem_avg"), gpuMemory)
        }
    }

    private func accumulateMemory(_ module: MonitorModule) {
        accumulator.add(Self.index("mem_pct_avg"), module.value)
        accumulator.trackMax(Self.index("mem_pct_max"), module.value)
        if let used = numeric("used", in: module) {
            accumulator.add(Self.index("mem_used_avg"), used)
        }
        if let compressed = numeric("compressed", in: module) {
            accumulator.add(Self.index("mem_comp_avg"), compressed)
        }
        if let swap = numeric("swap-used", in: module) {
            accumulator.add(Self.index("mem_swap_avg"), swap)
        }
        if let pressure = module.pressureValue {
            accumulator.add(Self.index("mem_pressure_avg"), pressure)
        }
    }

    private func accumulateNetwork(_ module: MonitorModule, at date: Date) {
        if let download = numeric("download", in: module) {
            integrate(rate: download, at: date, cursor: &lastNetDown, totalIndex: Self.index("net_down"), peakIndex: Self.index("net_down_peak"))
        }
        if let upload = numeric("upload", in: module) {
            integrate(rate: upload, at: date, cursor: &lastNetUp, totalIndex: Self.index("net_up"), peakIndex: Self.index("net_up_peak"))
        }
    }

    private func accumulateStorage(_ module: MonitorModule, at date: Date) {
        if let readRate = numeric("disk-read-rate", in: module) {
            integrate(rate: readRate, at: date, cursor: &lastDiskRead, totalIndex: Self.index("disk_read"), peakIndex: Self.index("disk_read_peak"))
        }
        if let writeRate = numeric("disk-write-rate", in: module) {
            integrate(rate: writeRate, at: date, cursor: &lastDiskWrite, totalIndex: Self.index("disk_write"), peakIndex: Self.index("disk_write_peak"))
        }
    }

    private func accumulateBattery(_ module: MonitorModule) {
        // 无 status 的模块电源状态不可信(占位模块已在入口过滤,此处为防御):
        // 不计入电源构成,避免把 nil 误判成交流供电。
        guard let status = text("status", in: module) else { return }
        // 电源构成只认 IOPS 状态:非 "on-battery" 即在交流侧(直供/维持/充电)。
        let onAC = status != "on-battery"
        accumulator.add(Self.index("ac_frac"), onAC ? 1 : 0)
        accumulator.add(Self.index("charging_frac"), status == "charging" ? 1 : 0)
        // 电量/电池温度只在真电池模块(type=battery)上有意义,桌面机型的
        // ac-power 模块不产出,避免把占位值记进历史。
        if text("type", in: module) == "battery" {
            accumulator.add(Self.index("batt_level_avg"), module.value)
            if let temperature = numeric("temperature", in: module) {
                accumulator.add(Self.index("batt_temp_avg"), temperature)
            }
        }
        if let power = numeric("power", in: module) {
            accumulator.add(Self.index("power_avg"), power)
            accumulator.trackMax(Self.index("power_max"), power)
        }
        if let cycles = numeric("cycle-count", in: module), let health = numeric("health", in: module) {
            lastBatterySlow = (cycles, health)
        }
    }

    /// 分段积分:把上一观测点的速率按保持外推覆盖到当前时刻,累进总量列;
    /// 同时记录峰值速率。间隔越界(睡眠/间隙)只刷新游标不累加。
    private func integrate(rate: Double, at date: Date, cursor: inout (rate: Double, at: Date)?, totalIndex: Int, peakIndex: Int) {
        if let previous = cursor {
            let elapsed = date.timeIntervalSince(previous.at)
            if elapsed > 0, elapsed <= Self.rateIntegrationCap {
                accumulator.sums[totalIndex] += previous.rate * elapsed
            }
        }
        cursor = (rate, date)
        accumulator.trackMax(peakIndex, rate)
    }

    // MARK: - 封口与落库

    /// 把已完成的分钟行写入数据库并刷新概览。当前未完成分钟不落库,
    /// 概览因此始终滞后至多一个采样分钟。
    private func sealCompletedMinute() {
        guard let minuteStart = currentMinuteStart,
              let row = accumulator.row(t: minuteStart) else {
            accumulator = Accumulator()
            return
        }
        accumulator = Accumulator()
        // 电池慢变量在主线程读取后随闭包带入后台,避免跨线程访问累加器状态;
        // 同日同值跳过(见 savedBattery 注释)。
        let battery = lastBatterySlow.flatMap { current -> (cycles: Double, health: Double)? in
            let day = StatisticsProcessStore.dayKey(Date(timeIntervalSince1970: TimeInterval(minuteStart)), calendar: calendar)
            guard savedBattery?.day != day || savedBattery?.cycles != current.cycles
                    || savedBattery?.health != current.health else { return nil }
            savedBattery = (day, current.cycles, current.health)
            return current
        }
        maintenanceQueue.async { [weak self] in
            guard let self else { return }
            if let database = self.database {
                database.insertMinuteRow(row)
                database.maintain(now: Date())
            }
            let sealedAt = Date(timeIntervalSince1970: TimeInterval(row.t))
            self.processStore?.recordUsageDay(at: sealedAt, calendar: self.calendar)
            if let battery {
                self.processStore?.recordBattery(
                    cycleCount: Int(battery.cycles.rounded()),
                    healthPercent: battery.health,
                    at: sealedAt,
                    calendar: self.calendar
                )
            }
            self.minuteSealCount += 1
            if self.minuteSealCount % 10 == 0 {
                self.processStore?.flush()
            }
            self.refreshOverview()
        }
    }

    /// 分钟封口计数,驱动进程累加器的周期性刷库。
    private var minuteSealCount = 0

    /// 单测用:同步封口当前分钟并落库(生产封口在 maintenanceQueue 异步执行)。
    func sealCompletedMinuteForTesting() {
        guard let minuteStart = currentMinuteStart else { return }
        let row = accumulator.row(t: minuteStart)
        accumulator = Accumulator()
        currentMinuteStart = nil
        if let row {
            database?.insertMinuteRow(row)
        }
    }

    // MARK: - 概览(设置页数据)

    /// 后台重算各范围聚合行 + 元信息并回主线程发布。分钟一封口即刷新。
    private func refreshOverview() {
        guard let database else { return }
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        var rows: [StatisticsOverviewRange: StatisticsRow?] = [:]
        for range in StatisticsOverviewRange.allCases {
            let windowStart = range.startOfDayWindow(from: now, calendar: calendar)
            let source: [StatisticsRow]
            switch range {
            case .today:
                // 今日优先分钟层(最细);应用刚跨日启动时小时层兜底
                let minutes = database.minuteRows(from: windowStart, to: now.addingTimeInterval(120))
                source = minutes.isEmpty
                    ? database.hourRows(from: windowStart, to: now.addingTimeInterval(3600))
                    : minutes
            case .week, .month:
                source = database.hourRows(from: windowStart, to: now.addingTimeInterval(3600))
            }
            rows[range] = StatisticsRow.aggregate(source, t: Int64(windowStart.timeIntervalSince1970))
        }

        var recordDays = 0
        if let earliest = database.earliestRecord {
            recordDays = (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: todayStart).day ?? 0) + 1
        }
        let storage = currentStorageInfo(database: database)

        var usageTotal = 0
        var usageStreak = 0
        var usageFirst: Int64 = 0
        var activeDaysList: [Int64] = []
        if let summary = processStore?.usageSummary() {
            usageTotal = Int(summary.totalActiveDays)
            usageFirst = summary.firstUseDay
            activeDaysList = processStore?.activeDays() ?? []
            let days = Set(activeDaysList)
            let todayKey = StatisticsProcessStore.dayKey(now, calendar: calendar)
            var cursor = days.contains(todayKey) ? todayKey : previousDayKey(todayKey, calendar: calendar)
            while days.contains(cursor) {
                usageStreak += 1
                cursor = previousDayKey(cursor, calendar: calendar)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rangeRows = rows
            self.storageInfo = storage
            self.recordDays = recordDays
            self.usageTotalDays = usageTotal
            self.usageStreakDays = usageStreak
            self.usageFirstDay = usageFirst
            self.usageActiveDays = activeDaysList
        }
    }

    /// 汇总三类存储产物的占用与记录规模(后台队列执行)。
    private func currentStorageInfo(database: StatisticsDatabase) -> StorageInfo {
        let counts = database.rowCounts
        let reportBytes = (try? FileManager.default
            .attributesOfItem(atPath: StatisticsReportBuilder.outputURL.path))?[.size] as? Int64 ?? 0
        return StorageInfo(
            databaseBytes: database.fileSize ?? 0,
            appStatsBytes: processStore?.fileSize ?? 0,
            reportBytes: reportBytes,
            minuteCount: counts.minute,
            hourCount: counts.hour,
            dayCount: counts.day
        )
    }

    /// yyyymmdd 整数日键回退一天。必须走 Calendar 的日历日运算:
    /// 直接减 86400s 在夏令时切换日会落到 23:00/01:00,回推出错误日键,
    /// 轻则连续天数跳日,重则回游标不前进而挂死串行维护队列。
    private func previousDayKey(_ key: Int64, calendar: Calendar) -> Int64 {
        let components = DateComponents(year: Int(key / 10_000), month: Int(key % 10_000 / 100), day: Int(key % 100))
        if let day = calendar.date(from: components),
           let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            return StatisticsProcessStore.dayKey(previous, calendar: calendar)
        }
        // 构造失败(理论上仅畸形键):回退一个必然不在集合里的非法键,
        // 保证回推严格递减、调用方循环终止。
        return key - 1
    }

    // MARK: - 报表数据导出

    /// 供报表生成器在后台拉取全量数据:近 48h 分钟行、近 60 天小时行、全部日行。
    func reportSnapshot(now: Date) -> (minutes: [StatisticsRow], hours: [StatisticsRow], days: [StatisticsRow])? {
        guard let database else { return nil }
        let minutesFrom = now.addingTimeInterval(-48 * 3600)
        let hoursFrom = now.addingTimeInterval(-60 * 86400)
        return (
            database.minuteRows(from: minutesFrom, to: now.addingTimeInterval(120)),
            database.hourRows(from: hoursFrom, to: now.addingTimeInterval(3600)),
            database.dayRows(from: .distantPast, to: now.addingTimeInterval(86400))
        )
    }

    // MARK: - 存储管理

    /// 存储浏览粒度:日(含进行中的今天)/ 周 / 月。
    enum StorageGranularity {
        case day
        case week
        case month
    }

    /// 存储浏览中的一个时间桶:聚合行 + 桶起止时刻。
    struct StorageBucket: Identifiable {
        let start: Date
        let end: Date
        let row: StatisticsRow
        var id: Int64 { row.t }
    }

    /// 拉取指定粒度的历史桶(后台执行,主线程回调),供设置页存储浏览。
    /// 日粒度 = 日层行 + 今日分钟行现算;周/月由日桶按本地时区归组。
    func storageBuckets(_ granularity: StorageGranularity, completion: @escaping ([StorageBucket]) -> Void) {
        maintenanceQueue.async { [weak self] in
            guard let self, let database = self.database else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let now = Date()
            let dayBuckets = self.dayBuckets(database: database, now: now)
            var buckets: [StorageBucket]
            switch granularity {
            case .day:
                buckets = dayBuckets
            case .week, .month:
                let unit: Calendar.Component
                switch granularity {
                case .week: unit = .weekOfYear
                default: unit = .month
                }
                var groups: [Int64: [StatisticsRow]] = [:]
                var ends: [Int64: Date] = [:]
                for bucket in dayBuckets {
                    guard let interval = self.calendar.dateInterval(of: unit, for: bucket.start) else { continue }
                    let key = Int64(interval.start.timeIntervalSince1970)
                    groups[key, default: []].append(bucket.row)
                    ends[key] = interval.end
                }
                buckets = groups.keys.sorted().map { key in
                    StorageBucket(
                        start: Date(timeIntervalSince1970: TimeInterval(key)),
                        end: ends[key] ?? now,
                        row: StatisticsRow.aggregate(groups[key] ?? [], t: key) ?? StatisticsRow(t: key, n: 0)
                    )
                }
            }
            DispatchQueue.main.async { completion(buckets) }
        }
    }

    /// 删除指定时刻之前的全部统计数据(统计库 + 应用统计),完成后刷新概览。
    /// 双库按自然日对齐边界:边界日要么两边都保留整天,要么都删整天,
    /// 避免「统计库删到当天时刻、应用库保留整天」的错位。
    func deleteData(before date: Date, completion: @escaping () -> Void) {
        maintenanceQueue.async { [weak self] in
            if let self {
                let dayStart = self.calendar.startOfDay(for: date)
                self.database?.deleteBefore(dayStart)
                self.processStore?.deleteBefore(day: StatisticsProcessStore.dayKey(date, calendar: self.calendar))
                self.refreshOverview()
            }
            // recorder 中途释放也必须回置调用方 busy 状态,否则按钮永久禁用
            DispatchQueue.main.async { completion() }
        }
    }

    /// 删除单个浏览桶(统计库三层区间 + 应用统计对应日区间),完成后刷新概览。
    /// 报表缓存不在此列,由存储页独立入口清理。
    func deleteBucket(_ bucket: StorageBucket, completion: @escaping () -> Void) {
        maintenanceQueue.async { [weak self] in
            if let self {
                self.database?.deleteRange(from: bucket.start, to: bucket.end)
                self.processStore?.deleteRange(
                    fromDay: StatisticsProcessStore.dayKey(bucket.start, calendar: self.calendar),
                    toDay: StatisticsProcessStore.dayKey(bucket.end, calendar: self.calendar)
                )
                self.refreshOverview()
            }
            DispatchQueue.main.async { completion() }
        }
    }

    /// 清空应用统计(进程聚合/身份图标/打卡),完成后刷新概览。
    func clearAppStats(completion: @escaping () -> Void) {
        maintenanceQueue.async { [weak self] in
            if let self {
                self.processStore?.deleteAll()
                self.refreshOverview()
            }
            DispatchQueue.main.async { completion() }
        }
    }

    /// 删除报表缓存文件,完成后刷新概览。
    func clearReportCache(completion: @escaping () -> Void) {
        maintenanceQueue.async { [weak self] in
            if let self {
                try? FileManager.default.removeItem(at: StatisticsReportBuilder.outputURL)
                self.refreshOverview()
            }
            DispatchQueue.main.async { completion() }
        }
    }

    /// 清空全部统计数据(统计库 + 应用统计 + 报表文件),完成后刷新概览。
    func deleteAllData(completion: @escaping () -> Void) {
        maintenanceQueue.async { [weak self] in
            if let self {
                self.database?.deleteAll()
                self.processStore?.deleteAll()
                try? FileManager.default.removeItem(at: StatisticsReportBuilder.outputURL)
                self.refreshOverview()
            }
            DispatchQueue.main.async { completion() }
        }
    }

    /// 日桶:日层历史 + 今日由分钟层现算(日层仅在翻日后落库)。
    private func dayBuckets(database: StatisticsDatabase, now: Date) -> [StorageBucket] {
        let todayStart = calendar.startOfDay(for: now)
        var rows = database.dayRows(from: .distantPast, to: now.addingTimeInterval(86400))
        let todayKey = Int64(todayStart.timeIntervalSince1970)
        if !rows.contains(where: { $0.t == todayKey }) {
            let minutes = database.minuteRows(from: todayStart, to: now.addingTimeInterval(120))
            if let today = StatisticsRow.aggregate(minutes, t: todayKey) {
                rows.append(today)
            }
        }
        return rows
            .sorted { $0.t < $1.t }
            .map { row in
                let start = Date(timeIntervalSince1970: TimeInterval(row.t))
                return StorageBucket(
                    start: start,
                    end: calendar.date(byAdding: .day, value: 1, to: start) ?? now,
                    row: row
                )
            }
    }

    private static func index(_ name: String) -> Int {
        columnIndex[name] ?? 0
    }

    private func numeric(_ name: String, in module: MonitorModule) -> Double? {
        module.metrics.first { $0.name == name }?.numericValue
    }

    private func text(_ name: String, in module: MonitorModule) -> String? {
        module.metrics.first { $0.name == name }?.value
    }
}
