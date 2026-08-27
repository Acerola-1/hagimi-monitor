import AppKit
import Foundation
import OSLog
import SQLite3
import SwiftData

// MARK: - SwiftData 实体

/// 应用身份:名称为键,图标以 128px PNG 持久化一次。应用卸载后历史报表仍可
/// 显示名称与图标——统计行只引用 appKey,不依赖进程存活。
@Model
final class StatsAppIdentity {
    @Attribute(.unique) var appKey: String
    var name: String
    var iconPNG: Data?

    init(appKey: String, name: String, iconPNG: Data? = nil) {
        self.appKey = appKey
        self.name = name
        self.iconPNG = iconPNG
    }
}

/// 单应用单日聚合。score 类列为采样值之和(均值 = score/samples),
/// 网络与磁盘为字节总量,内存为占用之和(均值 = memSum/memSamples)。
@Model
final class StatsAppDaily {
    var day: Int64
    var appKey: String
    var name: String
    var cpuScore: Double
    var cpuSamples: Int
    var gpuScore: Double
    var gpuSamples: Int
    var memSum: Double
    var memSamples: Int
    var netDown: Double
    var netUp: Double
    var diskRead: Double
    var diskWrite: Double

    init(day: Int64, appKey: String, name: String) {
        self.day = day
        self.appKey = appKey
        self.name = name
        self.cpuScore = 0; self.cpuSamples = 0
        self.gpuScore = 0; self.gpuSamples = 0
        self.memSum = 0; self.memSamples = 0
        self.netDown = 0; self.netUp = 0
        self.diskRead = 0; self.diskWrite = 0
    }
}

/// 电池慢变量按日快照:循环次数与健康度(有电池机型)。
@Model
final class StatsBatteryDaily {
    var day: Int64
    var cycleCount: Int
    var healthPercent: Double

    init(day: Int64, cycleCount: Int, healthPercent: Double) {
        self.day = day
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }
}

/// 单个活跃日(当天有过任何采样即插入),供打卡图与连续天数计算。
@Model
final class StatsActiveDay {
    @Attribute(.unique) var day: Int64
    init(day: Int64) { self.day = day }
}

/// 使用打卡元信息:首用日/累计活跃天数(连续天数由日历推导)。
@Model
final class StatsUsageMeta {
    var firstUseDay: Int64
    var totalActiveDays: Int64
    var lastActiveDay: Int64

    init(firstUseDay: Int64, totalActiveDays: Int64, lastActiveDay: Int64) {
        self.firstUseDay = firstUseDay
        self.totalActiveDays = totalActiveDays
        self.lastActiveDay = lastActiveDay
    }
}

// MARK: - 进程统计存储

/// SwiftData 存储的进程/电池/打卡统计。所有公开方法内部经专用串行队列执行,
/// ModelContext 只在该队列上创建与使用。API 值类型进出,调用方不接触托管对象。
final class StatisticsProcessStore {
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.stats-process-db", qos: .utility)
    private var container: ModelContainer?
    private var context: ModelContext?
    private var databaseURL: URL?
    /// breakdown 查询复用的只读 SQLite 连接,随容器重建同步更换。
    private var breakdownHandle: OpaquePointer?
    /// 重建失败时暂存的打卡,下次重建成功后补写回新库。
    private var pendingCheckin: (days: [Int64], meta: (firstUseDay: Int64, totalActiveDays: Int64, lastActiveDay: Int64)?)?

    /// 一日内的进程聚合累加器(仅队列线程访问),封口刷入 SwiftData。
    private struct AppAccumulator {
        var name: String
        var cpuScore = 0.0
        var cpuSamples = 0
        var gpuScore = 0.0
        var gpuSamples = 0
        var memSum = 0.0
        var memSamples = 0
        var netDown = 0.0
        var netUp = 0.0
        var diskRead = 0.0
        var diskWrite = 0.0
    }
    private var currentDay: Int64 = 0
    private var accumulators: [String: AppAccumulator] = [:]
    /// 名称 → 图标 PNG 内存缓存,避免重复转码。
    private var iconCache: [String: Data] = [:]
    /// 确认无图标的进程名集合,避免对守护进程反复查询。
    private var iconSkipSet: Set<String> = []

    init(directory: URL) {
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                databaseURL = directory.appendingPathComponent("AppStats.sqlite")
                try reopenStoreLocked()
            } catch {
                AppLogger.settings.error("Statistics process store init failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 建立(或重建)库容器与上下文。调用前必须已持有 queue。
    private func reopenStoreLocked() throws {
        guard let databaseURL else { return }
        if let breakdownHandle {
            sqlite3_close_v2(breakdownHandle)
            self.breakdownHandle = nil
        }
        let config = ModelConfiguration(url: databaseURL)
        let newContainer = try ModelContainer(
            for: StatsAppIdentity.self, StatsAppDaily.self, StatsBatteryDaily.self,
                 StatsUsageMeta.self, StatsActiveDay.self,
            configurations: config
        )
        let newContext = ModelContext(newContainer)
        newContext.autosaveEnabled = false
        container = newContainer
        context = newContext
        restorePendingCheckinsLocked()
    }

    /// 上下文缺失时按需重建库容器(容器损坏/整库重建失败后的停写期),
    /// 重建成功后暂存的打卡随之补写回新库。
    private func ensureContextLocked() {
        guard context == nil, databaseURL != nil else { return }
        try? reopenStoreLocked()
    }

    private func restorePendingCheckinsLocked() {
        guard let pending = pendingCheckin, let context else { return }
        for day in pending.days {
            context.insert(StatsActiveDay(day: day))
        }
        if let meta = pending.meta {
            context.insert(StatsUsageMeta(
                firstUseDay: meta.firstUseDay,
                totalActiveDays: meta.totalActiveDays,
                lastActiveDay: meta.lastActiveDay
            ))
        }
        pendingCheckin = nil
        do {
            try context.save()
        } catch {
            AppLogger.settings.error("Statistics checkin restore failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func defaultDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HagimiMonitor", isDirectory: true)
    }

    /// 空库表结构页字节(main 文件):临时目录建同 schema 空库实测,
    /// schema 演进后测量值自动跟随。进程内只测一次。
    private static let schemaMainBytesProbe: Int64 = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstats-schema-probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = StatisticsProcessStore(directory: directory)
        let mainURL = directory.appendingPathComponent("AppStats.sqlite")
        return (try? FileManager.default.attributesOfItem(atPath: mainURL.path))?[.size] as? Int64 ?? 0
    }()

    /// 库文件占用的数据/系统两方分解(口径见 StorageBreakdown)。
    /// 只读连接随容器缓存复用,避免每次分解都建连;WAL 多读者安全,与写入互不干扰。
    var breakdown: StorageBreakdown {
        queue.sync {
            guard let url = databaseURL else { return .zero }
            func fileSize(_ suffix: String) -> Int64 {
                (try? FileManager.default.attributesOfItem(atPath: url.path + suffix))?[.size] as? Int64 ?? 0
            }
            let walBytes = fileSize("-wal")
            let shmBytes = fileSize("-shm")
            var pageSize: Int64 = 4096
            var freeCount: Int64 = 0
            if breakdownHandle == nil {
                var opened: OpaquePointer?
                if sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let opened {
                    sqlite3_busy_timeout(opened, 2_000)
                    breakdownHandle = opened
                }
            }
            if let handle = breakdownHandle {
                pageSize = Self.scalarPragma(handle, "page_size") ?? 4096
                freeCount = Self.scalarPragma(handle, "freelist_count") ?? 0
            }

            // main 以文件实际大小为基准:未 checkpoint 的新增页尚在 WAL 侧,
            // 不含在 main 里,与 walBytes 相加不重复。
            let schemaBytes = Self.schemaMainBytesProbe
            let dataOnMain = max(fileSize("") - schemaBytes - freeCount * pageSize, 0)
            return StorageBreakdown(
                dataBytes: dataOnMain + walBytes,
                systemBytes: schemaBytes + freeCount * pageSize + shmBytes
            )
        }
    }

    private static func scalarPragma(_ handle: OpaquePointer?, _ name: String) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    // MARK: - 写入

    /// 一帧进程采样:按应用名合并进当日累加器。在统计串行队列外调用安全。
    /// 图标按 pid 现取全分辨率源(见 captureIcon),不消费面板的降采样图标。
    func record(
        cpu: [(name: String, pid: pid_t, usage: Double)],
        memory: [(name: String, pid: pid_t, bytes: Double)],
        gpu: [(name: String, pid: pid_t, usage: Double)],
        network: [(name: String, pid: pid_t, downBytes: Double, upBytes: Double)],
        disk: [(name: String, pid: pid_t, readBytes: Double, writeBytes: Double)],
        at date: Date,
        calendar: Calendar
    ) {
        let day = Self.dayKey(date, calendar: calendar)
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureContextLocked()
            if day != self.currentDay {
                self.flushLocked()
                self.currentDay = day
            }
            for entry in cpu where entry.usage >= 0.5 {
                var acc = self.accumulators[entry.name] ?? AppAccumulator(name: entry.name)
                acc.cpuScore += entry.usage
                acc.cpuSamples += 1
                self.accumulators[entry.name] = acc
                self.captureIcon(entry.name, pid: entry.pid)
            }
            for entry in memory where entry.bytes >= 64 * 1_048_576 {
                var acc = self.accumulators[entry.name] ?? AppAccumulator(name: entry.name)
                acc.memSum += entry.bytes
                acc.memSamples += 1
                self.accumulators[entry.name] = acc
                self.captureIcon(entry.name, pid: entry.pid)
            }
            for entry in gpu where entry.usage >= 0.5 {
                var acc = self.accumulators[entry.name] ?? AppAccumulator(name: entry.name)
                acc.gpuScore += entry.usage
                acc.gpuSamples += 1
                self.accumulators[entry.name] = acc
                self.captureIcon(entry.name, pid: entry.pid)
            }
            for entry in network where entry.downBytes + entry.upBytes >= 5 * 1_048_576 {
                var acc = self.accumulators[entry.name] ?? AppAccumulator(name: entry.name)
                acc.netDown += entry.downBytes
                acc.netUp += entry.upBytes
                self.accumulators[entry.name] = acc
                self.captureIcon(entry.name, pid: entry.pid)
            }
            for entry in disk where entry.readBytes + entry.writeBytes >= 10 * 1_048_576 {
                var acc = self.accumulators[entry.name] ?? AppAccumulator(name: entry.name)
                acc.diskRead += entry.readBytes
                acc.diskWrite += entry.writeBytes
                self.accumulators[entry.name] = acc
                self.captureIcon(entry.name, pid: entry.pid)
            }
        }
    }

    /// 电池慢变量按日快照(同日重复调用以后到者为准)。
    func recordBattery(cycleCount: Int, healthPercent: Double, at date: Date, calendar: Calendar) {
        let day = Self.dayKey(date, calendar: calendar)
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureContextLocked()
            guard let context = self.context else { return }
            let predicate = #Predicate<StatsBatteryDaily> { $0.day == day }
            if let existing = try? context.fetch(FetchDescriptor(predicate: predicate)).first {
                existing.cycleCount = cycleCount
                existing.healthPercent = healthPercent
            } else {
                context.insert(StatsBatteryDaily(day: day, cycleCount: cycleCount, healthPercent: healthPercent))
            }
            try? context.save()
        }
    }

    /// 当日有采样时打卡(分钟封口调用一次即可)。
    func recordUsageDay(at date: Date, calendar: Calendar) {
        let day = Self.dayKey(date, calendar: calendar)
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureContextLocked()
            guard let context = self.context else { return }
            let descriptor = FetchDescriptor<StatsUsageMeta>()
            let meta = (try? context.fetch(descriptor).first) ?? {
                let created = StatsUsageMeta(firstUseDay: day, totalActiveDays: 0, lastActiveDay: 0)
                context.insert(created)
                return created
            }()
            if meta.lastActiveDay != day {
                meta.totalActiveDays += 1
                meta.lastActiveDay = day
            }
            let activeKey = day
            let activePredicate = #Predicate<StatsActiveDay> { $0.day == activeKey }
            var activeDescriptor = FetchDescriptor(predicate: activePredicate)
            activeDescriptor.fetchLimit = 1
            if (try? context.fetch(activeDescriptor))?.first == nil {
                context.insert(StatsActiveDay(day: day))
            }
            try? context.save()
        }
    }

    /// 把当日累加器写入 SwiftData(每日切换/定期触发)。
    func flush() {
        queue.async { [weak self] in
            self?.flushLocked()
        }
    }

    private func flushLocked() {
        ensureContextLocked()
        guard let context else { return }
        let day = currentDay
        guard day > 0 else { return }
        for (key, acc) in accumulators {
            let predicate = #Predicate<StatsAppDaily> { $0.day == day && $0.appKey == key }
            let row = (try? context.fetch(FetchDescriptor(predicate: predicate)).first)
                ?? {
                    let created = StatsAppDaily(day: day, appKey: key, name: acc.name)
                    context.insert(created)
                    return created
                }()
            row.name = acc.name
            row.cpuScore += acc.cpuScore; row.cpuSamples += acc.cpuSamples
            row.gpuScore += acc.gpuScore; row.gpuSamples += acc.gpuSamples
            row.memSum += acc.memSum; row.memSamples += acc.memSamples
            row.netDown += acc.netDown; row.netUp += acc.netUp
            row.diskRead += acc.diskRead; row.diskWrite += acc.diskWrite
        }
        accumulators.removeAll()
        try? context.save()
    }

    /// 报表 Retina 显示需要 2x 以上源图:图标以 128px PNG 落库,
    /// 旧版 64px 库存在下次见到该应用时自动升级。
    static let iconSize: CGFloat = 128

    /// 首次见到应用时捕获 128px 图标。按 pid 现取全分辨率 bundle 图标
    /// (面板图标是 32px 降采样产物,放大到 128px 会永久糊化);
    /// 进程取不到图标时本轮跳过,下轮采样再试。缩放走 CoreGraphics,
    /// 不触碰 NSGraphicsContext.current,后台队列安全。
    /// 落库不单独 save:由 flushLocked/分钟封口的统一 save 收口。
    private func captureIcon(_ name: String, pid: pid_t) {
        guard iconCache[name] == nil, !iconSkipSet.contains(name) else { return }
        guard let context else { return }
        let key = name
        let predicate = #Predicate<StatsAppIdentity> { $0.appKey == key }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)).first) ?? nil
        if let stored = existing?.iconPNG, Self.iconPixels(stored) >= Int(Self.iconSize) {
            iconCache[name] = stored
            return
        }
        // 守护进程(.prohibited 或无 Launch Services 注册)使用通用系统图标,
        // 不落库——数十个守护进程共用同一张图标,冗余存储可达数 MB。
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited else {
            iconSkipSet.insert(name)
            return
        }
        guard let png = ProcessIconCache.fullSizePNG(forPID: pid, sidePixels: Int(Self.iconSize)) else { return }
        iconCache[name] = png
        if let existing {
            existing.iconPNG = png
        } else {
            context.insert(StatsAppIdentity(appKey: name, name: name, iconPNG: png))
        }
    }

    private static func iconPixels(_ data: Data) -> Int {
        NSBitmapImageRep(data: data)?.pixelsWide ?? 0
    }

    // MARK: - 查询

    struct AppRankEntry {
        let appKey: String
        let name: String
        let value: Double
        let secondary: Double
        let iconPNG: Data?
    }

    struct BatteryPoint {
        let day: Int64
        let cycleCount: Int
        let healthPercent: Double
    }

    struct UsageSummary {
        let firstUseDay: Int64
        let totalActiveDays: Int64
        let lastActiveDay: Int64
    }

    enum AppCategory {
        case cpu
        case memory
        case gpu
        case network
    }

    /// 范围内各类别 Top 应用(按均值/总量),网络为下行+上行总量。
    func topApps(fromDay: Int64, toDay: Int64, category: AppCategory, limit: Int = 8) -> [AppRankEntry] {
        queue.sync {
            guard let context else { return [] }
            let predicate = #Predicate<StatsAppDaily> { $0.day >= fromDay && $0.day <= toDay }
            let rows = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
            var aggregated: [String: StatsAppDaily] = [:]
            rows.forEach { row in
                if let merged = aggregated[row.appKey] {
                    merged.cpuScore += row.cpuScore; merged.cpuSamples += row.cpuSamples
                    merged.gpuScore += row.gpuScore; merged.gpuSamples += row.gpuSamples
                    merged.memSum += row.memSum; merged.memSamples += row.memSamples
                    merged.netDown += row.netDown; merged.netUp += row.netUp
                    merged.diskRead += row.diskRead; merged.diskWrite += row.diskWrite
                    merged.name = row.name
                } else {
                    let fresh = StatsAppDaily(day: 0, appKey: row.appKey, name: row.name)
                    fresh.cpuScore = row.cpuScore; fresh.cpuSamples = row.cpuSamples
                    fresh.gpuScore = row.gpuScore; fresh.gpuSamples = row.gpuSamples
                    fresh.memSum = row.memSum; fresh.memSamples = row.memSamples
                    fresh.netDown = row.netDown; fresh.netUp = row.netUp
                    fresh.diskRead = row.diskRead; fresh.diskWrite = row.diskWrite
                    aggregated[row.appKey] = fresh
                }
            }
            let identities = (try? context.fetch(FetchDescriptor<StatsAppIdentity>())) ?? []
            // 旧库/迁移异常可能存在重复 appKey 行,first-wins 去重,不做会 trap 的强唯一构造
            let iconByKey = Dictionary(
                identities.map { ($0.appKey, $0.iconPNG) },
                uniquingKeysWith: { first, _ in first }
            )

            let entries: [(key: String, name: String, value: Double, secondary: Double)]
            switch category {
            case .cpu:
                entries = aggregated.values
                    .filter { $0.cpuSamples > 0 }
                    .map { ($0.appKey, $0.name, $0.cpuScore / Double($0.cpuSamples), Double($0.cpuSamples)) }
            case .memory:
                entries = aggregated.values
                    .filter { $0.memSamples > 0 }
                    .map { ($0.appKey, $0.name, $0.memSum / Double($0.memSamples), Double($0.memSamples)) }
            case .gpu:
                entries = aggregated.values
                    .filter { $0.gpuSamples > 0 }
                    .map { ($0.appKey, $0.name, $0.gpuScore / Double($0.gpuSamples), Double($0.gpuSamples)) }
            case .network:
                entries = aggregated.values
                    .map { ($0.appKey, $0.name, $0.netDown + $0.netUp, $0.netDown) }
            }
            return entries
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { AppRankEntry(appKey: $0.key, name: $0.name, value: $0.value, secondary: $0.secondary, iconPNG: iconByKey[$0.key] ?? nil) }
        }
    }

    /// 日级原始行(报表按任意范围客户端聚合用)。
    struct DailyAppRow {
        let day: Int64
        let appKey: String
        let name: String
        let cpuAvg: Double
        let cpuSamples: Int
        let gpuAvg: Double
        let gpuSamples: Int
        let memAvgBytes: Double
        let memSamples: Int
        let netDownBytes: Double
        let netUpBytes: Double
    }

    func dailyRows(fromDay: Int64, toDay: Int64) -> [DailyAppRow] {
        queue.sync {
            guard let context else { return [] }
            let predicate = #Predicate<StatsAppDaily> { $0.day >= fromDay && $0.day <= toDay }
            let rows = (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.day)]))) ?? []
            return rows.map { row in
                DailyAppRow(
                    day: row.day,
                    appKey: row.appKey,
                    name: row.name,
                    cpuAvg: row.cpuSamples > 0 ? row.cpuScore / Double(row.cpuSamples) : 0,
                    cpuSamples: row.cpuSamples,
                    gpuAvg: row.gpuSamples > 0 ? row.gpuScore / Double(row.gpuSamples) : 0,
                    gpuSamples: row.gpuSamples,
                    memAvgBytes: row.memSamples > 0 ? row.memSum / Double(row.memSamples) : 0,
                    memSamples: row.memSamples,
                    netDownBytes: row.netDown,
                    netUpBytes: row.netUp
                )
            }
        }
    }

    /// 全部应用身份(含图标),报表用。
    func identities() -> [(appKey: String, name: String, iconPNG: Data?)] {
        queue.sync {
            guard let context else { return [] }
            let rows = (try? context.fetch(FetchDescriptor<StatsAppIdentity>())) ?? []
            return rows.map { ($0.appKey, $0.name, $0.iconPNG) }
        }
    }

    func batteryHistory() -> [BatteryPoint] {
        queue.sync {
            guard let context else { return [] }
            let rows = (try? context.fetch(FetchDescriptor<StatsBatteryDaily>(sortBy: [SortDescriptor(\.day)]))) ?? []
            return rows.map { BatteryPoint(day: $0.day, cycleCount: $0.cycleCount, healthPercent: $0.healthPercent) }
        }
    }

    func usageSummary() -> UsageSummary? {
        queue.sync {
            guard let context,
                  let meta = (try? context.fetch(FetchDescriptor<StatsUsageMeta>(sortBy: [SortDescriptor(\.firstUseDay)])))?.first else { return nil }
            return UsageSummary(firstUseDay: meta.firstUseDay, totalActiveDays: meta.totalActiveDays, lastActiveDay: meta.lastActiveDay)
        }
    }

    /// 活跃日列表(打卡图数据)。
    func activeDays() -> [Int64] {
        queue.sync {
            guard let context else { return [] }
            let rows = (try? context.fetch(FetchDescriptor<StatsActiveDay>(sortBy: [SortDescriptor(\.day)]))) ?? []
            return rows.map(\.day)
        }
    }

    // MARK: - 存储管理

    /// 库文件字节数(含 WAL/SHM,供设置页展示占用)。
    var fileSize: Int64? {
        queue.sync {
            guard let databaseURL else { return nil }
            let candidates = [
                databaseURL,
                URL(fileURLWithPath: databaseURL.path + "-wal"),
                URL(fileURLWithPath: databaseURL.path + "-shm"),
            ]
            var total: Int64 = 0
            for candidate in candidates {
                if let size = (try? FileManager.default.attributesOfItem(atPath: candidate.path))?[.size] as? Int64 {
                    total += size
                }
            }
            return total > 0 ? total : nil
        }
    }

    /// 删除早于指定日键的应用聚合/打卡/电池快照行。
    /// 应用身份(名称+图标)保留:占用极小,且是历史行名称与图标的来源。
    func deleteBefore(day: Int64) {
        queue.sync {
            guard let context else { return }
            let appRows = (try? context.fetch(FetchDescriptor<StatsAppDaily>(predicate: #Predicate { $0.day < day }))) ?? []
            appRows.forEach { context.delete($0) }
            let activeRows = (try? context.fetch(FetchDescriptor<StatsActiveDay>(predicate: #Predicate { $0.day < day }))) ?? []
            activeRows.forEach { context.delete($0) }
            let batteryRows = (try? context.fetch(FetchDescriptor<StatsBatteryDaily>(predicate: #Predicate { $0.day < day }))) ?? []
            batteryRows.forEach { context.delete($0) }
            repairUsageMetaLocked()
            try? context.save()
        }
    }

    /// 删除日键区间 [fromDay, toDay) 内的应用聚合/打卡/电池行(存储浏览按桶清理)。
    /// 先 flush 当日内存累加器:区间覆盖今天时,已采样未落库的部分一并入删。
    /// 应用身份(名称+图标)保留,与 deleteBefore 同口径。
    func deleteRange(fromDay: Int64, toDay: Int64) {
        queue.sync {
            guard let context else { return }
            flushLocked()
            let appRows = (try? context.fetch(FetchDescriptor<StatsAppDaily>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            appRows.forEach { context.delete($0) }
            let activeRows = (try? context.fetch(FetchDescriptor<StatsActiveDay>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            activeRows.forEach { context.delete($0) }
            let batteryRows = (try? context.fetch(FetchDescriptor<StatsBatteryDaily>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            batteryRows.forEach { context.delete($0) }
            repairUsageMetaLocked()
            try? context.save()
        }
    }

    /// 清空全部应用统计(应用聚合/身份图标/电池快照)。Core Data 逐行删除只把
    /// 页挂进 freelist,文件体积永不收缩——数 MB 的图标库清空后占用纹丝不动,
    /// 连同库文件一并销毁再按原 schema 重建,是让占用真实回落到空库地板的
    /// 唯一途径。
    /// 使用打卡(活跃日与连续天数)是用户的连续性记录,不随清空丢失:
    /// 销毁前取出,重建后原样写回。
    func deleteAll() {
        queue.sync {
            guard let url = databaseURL else { return }
            var checkinDays: [Int64] = []
            var checkinMeta: (firstUseDay: Int64, totalActiveDays: Int64, lastActiveDay: Int64)?
            if let ctx = context {
                do {
                    let days = try ctx.fetch(FetchDescriptor<StatsActiveDay>(sortBy: [SortDescriptor(\.day)]))
                    checkinDays = days.map(\.day)
                    checkinMeta = try ctx.fetch(FetchDescriptor<StatsUsageMeta>()).first
                        .map { ($0.firstUseDay, $0.totalActiveDays, $0.lastActiveDay) }
                } catch {
                    // 打卡备份失败即中止清空:承诺保留的连续性记录优先于清空本身。
                    AppLogger.settings.error("Statistics checkin backup failed, deleteAll aborted: \(String(describing: error), privacy: .public)")
                    return
                }
            }

            accumulators.removeAll()
            iconCache.removeAll()
            iconSkipSet.removeAll()
            currentDay = 0
            // 先断开容器再删文件;即便旧连接延迟关闭,POSIX unlink 下它写的
            // 是已摘除的 inode,不影响同路径上的新库。
            context = nil
            container = nil
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
            do {
                try reopenStoreLocked()
            } catch {
                AppLogger.settings.error("Statistics process store rebuild failed: \(String(describing: error), privacy: .public)")
                // 停写期由写入入口按需重建;打卡暂存,重建成功后补写回。
                pendingCheckin = (checkinDays, checkinMeta)
                return
            }
            guard let freshContext = context else { return }
            for day in checkinDays {
                freshContext.insert(StatsActiveDay(day: day))
            }
            if let meta = checkinMeta {
                freshContext.insert(StatsUsageMeta(
                    firstUseDay: meta.firstUseDay,
                    totalActiveDays: meta.totalActiveDays,
                    lastActiveDay: meta.lastActiveDay
                ))
            }
            do {
                try freshContext.save()
            } catch {
                // 插入仍留在上下文中,随后续落库的 save 一并持久化。
                AppLogger.settings.error("Statistics checkin restore save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 打卡行被删除后,按剩余活跃日重校元信息;无剩余则整体移除。
    private func repairUsageMetaLocked() {
        guard let context else { return }
        let remaining = (try? context.fetch(FetchDescriptor<StatsActiveDay>(sortBy: [SortDescriptor(\.day)]))) ?? []
        let metas = (try? context.fetch(FetchDescriptor<StatsUsageMeta>())) ?? []
        guard let meta = metas.first else { return }
        if remaining.isEmpty {
            context.delete(meta)
            return
        }
        meta.firstUseDay = remaining.first?.day ?? meta.firstUseDay
        meta.totalActiveDays = Int64(remaining.count)
        meta.lastActiveDay = remaining.last?.day ?? meta.lastActiveDay
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> Int64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return Int64(components.year ?? 0) * 10_000 + Int64(components.month ?? 0) * 100 + Int64(components.day ?? 0)
    }
}
