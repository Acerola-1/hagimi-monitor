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
    /// 身份类别（bundle / systemExecutable / unresolved / legacyName）。未设置时回退为 legacyName。
    var identityKind: String?

    init(appKey: String, name: String, iconPNG: Data? = nil, identityKind: String? = nil) {
        self.appKey = appKey
        self.name = name
        self.iconPNG = iconPNG
        self.identityKind = identityKind
    }

    /// 身份是否为可跨重命名延续的稳定键。
    var hasStableIdentity: Bool {
        guard let identityKind else { return false }
        return identityKind != AppIdentity.Kind.unresolved.rawValue
            && identityKind != "legacyName"
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
    var cpuTier1: Int = 0
    var cpuTier2: Int = 0
    var cpuTier3: Int = 0
    var cpuPeak: Double = 0.0
    var gpuTier1: Int = 0
    var gpuTier2: Int = 0
    var gpuTier3: Int = 0
    var gpuPeak: Double = 0.0
    var memTier1: Int = 0
    var memTier2: Int = 0
    var memTier3: Int = 0
    var memPeak: Double = 0.0

    init(day: Int64, appKey: String, name: String) {
        self.day = day
        self.appKey = appKey
        self.name = name
        self.cpuScore = 0; self.cpuSamples = 0
        self.gpuScore = 0; self.gpuSamples = 0
        self.memSum = 0; self.memSamples = 0
        self.netDown = 0; self.netUp = 0
        self.diskRead = 0; self.diskWrite = 0
        self.cpuTier1 = 0; self.cpuTier2 = 0; self.cpuTier3 = 0; self.cpuPeak = 0.0
        self.gpuTier1 = 0; self.gpuTier2 = 0; self.gpuTier3 = 0; self.gpuPeak = 0.0
        self.memTier1 = 0; self.memTier2 = 0; self.memTier3 = 0; self.memPeak = 0.0
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
/// 安全不变式：内部 ModelContext 与所有状态均由专用串行队列（com.acerola.hagimi-monitor.stats-process-db）串行管理，对外提供线程安全的访问接口。
nonisolated final class StatisticsProcessStore: @unchecked Sendable {
    /// 确认事件的默认保留期（自然日）。与日汇总同口径，由调用方按窗口传入。
    static let eventRetentionDays = 60

    /// 进程统计库的 schema 版本。2 = 新增 `StatsAppEvent` 并把 `appKey` 语义
    /// 从显示名改为稳定身份键。迁移与回滚路线见 docs/development/statistics-store-schema.md。
    static let schemaVersion = 2

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
        /// 稳定身份存储键（bundle:/systemExecutable:/unresolved:）。
        var appKey: String
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
        var cpuTier1 = 0
        var cpuTier2 = 0
        var cpuTier3 = 0
        var cpuPeak = 0.0
        var gpuTier1 = 0
        var gpuTier2 = 0
        var gpuTier3 = 0
        var gpuPeak = 0.0
        var memTier1 = 0
        var memTier2 = 0
        var memTier3 = 0
        var memPeak = 0.0
    }
    private var currentDay: Int64 = 0
    private var accumulators: [String: AppAccumulator] = [:]
    /// 名称 → 图标 PNG 内存缓存,避免重复转码。设置上限防止无界常驻。
    private let iconCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 64
        return cache
    }()
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
        // 注册数据模型实体，保留已有表并增量创建事件表。
        let newContainer = try ModelContainer(
            for: StatsAppIdentity.self, StatsAppDaily.self, StatsBatteryDaily.self,
                 StatsUsageMeta.self, StatsActiveDay.self, StatsAppEvent.self,
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

    /// 在落库持久化完成后重建上下文，释放本次落库过程中常驻的托管对象（StatsAppDaily、StatsAppIdentity 等），
    /// 防止 ModelContext 在长期运行中无限累积已持久化的实体与快照。
    private func resetContextLocked() {
        guard let container else { return }
        let newContext = ModelContext(container)
        newContext.autosaveEnabled = false
        self.context = newContext
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

    /// 一帧进程采样：按应用身份合并进当日累加器。在统计串行队列外调用安全。
    /// 身份标识优先使用 bundle identifier 或可执行路径，未确定时使用 unresolved 会话键。
    /// 显示名称作为展示标签保留。图标按 pid 捕获全分辨率源。
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
            // 每帧清空身份缓存，避免进程退出后 PID 复用导致身份串联。
            self.identityCache.removeAll(keepingCapacity: true)
            if day != self.currentDay {
                self.flushLocked()
                self.currentDay = day
            }
            // 档位边界与采样下限统一使用 StatisticsMetricDefinition 定义的标准阈值。
            let cpuBands = StatisticsMetricDefinition.cpuBandBoundaries
            let gpuBands = StatisticsMetricDefinition.gpuBandBoundaries
            let memoryBands = StatisticsMetricDefinition.memoryBands.map(\.lowerBound)

            for entry in cpu where entry.usage >= cpuBands[0] / 2 {
                let identity = self.identity(for: entry.name, pid: entry.pid)
                var acc = self.accumulators[identity.storageKey] ?? AppAccumulator(appKey: identity.storageKey, name: entry.name)
                acc.cpuScore += entry.usage
                acc.cpuSamples += 1
                acc.cpuPeak = max(acc.cpuPeak, entry.usage)
                if entry.usage >= cpuBands[2] {
                    acc.cpuTier3 += 1
                } else if entry.usage >= cpuBands[1] {
                    acc.cpuTier2 += 1
                } else if entry.usage >= cpuBands[0] {
                    acc.cpuTier1 += 1
                }
                self.accumulators[identity.storageKey] = acc
                self.captureIcon(identity.storageKey, pid: entry.pid)
            }
            for entry in memory where entry.bytes >= 64 * StatisticsMetricDefinition.mebibyte {
                let identity = self.identity(for: entry.name, pid: entry.pid)
                var acc = self.accumulators[identity.storageKey] ?? AppAccumulator(appKey: identity.storageKey, name: entry.name)
                acc.memSum += entry.bytes
                acc.memSamples += 1
                acc.memPeak = max(acc.memPeak, entry.bytes)
                if entry.bytes >= memoryBands[2] {
                    acc.memTier3 += 1
                } else if entry.bytes >= memoryBands[1] {
                    acc.memTier2 += 1
                } else if entry.bytes >= memoryBands[0] {
                    acc.memTier1 += 1
                }
                self.accumulators[identity.storageKey] = acc
                self.captureIcon(identity.storageKey, pid: entry.pid)
            }
            for entry in gpu where entry.usage >= gpuBands[0] / 2 {
                let identity = self.identity(for: entry.name, pid: entry.pid)
                var acc = self.accumulators[identity.storageKey] ?? AppAccumulator(appKey: identity.storageKey, name: entry.name)
                acc.gpuScore += entry.usage
                acc.gpuSamples += 1
                acc.gpuPeak = max(acc.gpuPeak, entry.usage)
                if entry.usage >= gpuBands[2] {
                    acc.gpuTier3 += 1
                } else if entry.usage >= gpuBands[1] {
                    acc.gpuTier2 += 1
                } else if entry.usage >= gpuBands[0] {
                    acc.gpuTier1 += 1
                }
                self.accumulators[identity.storageKey] = acc
                self.captureIcon(identity.storageKey, pid: entry.pid)
            }
            for entry in network where entry.downBytes + entry.upBytes >= 5 * StatisticsMetricDefinition.mebibyte {
                let identity = self.identity(for: entry.name, pid: entry.pid)
                var acc = self.accumulators[identity.storageKey] ?? AppAccumulator(appKey: identity.storageKey, name: entry.name)
                acc.netDown += entry.downBytes
                acc.netUp += entry.upBytes
                self.accumulators[identity.storageKey] = acc
                self.captureIcon(identity.storageKey, pid: entry.pid)
            }
            for entry in disk where entry.readBytes + entry.writeBytes >= 10 * StatisticsMetricDefinition.mebibyte {
                let identity = self.identity(for: entry.name, pid: entry.pid)
                var acc = self.accumulators[identity.storageKey] ?? AppAccumulator(appKey: identity.storageKey, name: entry.name)
                acc.diskRead += entry.readBytes
                acc.diskWrite += entry.writeBytes
                self.accumulators[identity.storageKey] = acc
                self.captureIcon(identity.storageKey, pid: entry.pid)
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
            if !context.hasChanges {
                self.resetContextLocked()
            }
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
            if !context.hasChanges {
                self.resetContextLocked()
            }
        }
    }

    /// 把当日累加器写入 SwiftData(每日切换/定期触发)。
    func flush() {
        queue.async { [weak self] in
            self?.flushLocked()
        }
    }

    /// 同步收口所有待落库内容。
    /// 在应用退出、测试验证或迁移时使用，确保内存累加器完全持久化到数据库。
    func flushSynchronously() {
        queue.sync {
            flushLocked()
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
            row.cpuTier1 += acc.cpuTier1; row.cpuTier2 += acc.cpuTier2; row.cpuTier3 += acc.cpuTier3
            row.cpuPeak = max(row.cpuPeak, acc.cpuPeak)
            row.gpuTier1 += acc.gpuTier1; row.gpuTier2 += acc.gpuTier2; row.gpuTier3 += acc.gpuTier3
            row.gpuPeak = max(row.gpuPeak, acc.gpuPeak)
            row.memTier1 += acc.memTier1; row.memTier2 += acc.memTier2; row.memTier3 += acc.memTier3
            row.memPeak = max(row.memPeak, acc.memPeak)
        }
        accumulators.removeAll()
        do {
            try context.save()
            resetContextLocked()
        } catch {
            // 失败时保留当前 context：上面已写入托管对象的改动仍可由后续 save 重试。
            // 若此处直接重建 context，会把已清空累加器对应的数据永久丢弃。
            AppLogger.settings.error("Statistics process flush failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 报表 Retina 显示需要 2x 以上源图:图标以 128px PNG 落库,
    /// 旧版 64px 库存在下次见到该应用时自动升级。
    static let iconSize: CGFloat = 128

    /// 首次见到应用时捕获 128px 图标。按 pid 现取全分辨率 bundle 图标
    /// (面板图标是 32px 降采样产物,放大到 128px 会永久糊化);
    /// 进程取不到图标时本轮跳过,下轮采样再试。缩放走 CoreGraphics,
    /// 不触碰 NSGraphicsContext.current,后台队列安全。
    /// 落库不单独 save:由 flushLocked/分钟封口的统一 save 收口。
    /// 采样帧期间解析到的稳定身份。按 pid 缓存，避免每条指标各查一次。
    private var identityCache: [pid_t: AppIdentity] = [:]
    /// 显示名称 → 最近一次解析到的身份键。用于按名称取图标等展示型查询：
    /// 身份键才是聚合主键，但调用方（如实时告警）手上只有显示名称。
    private var identityKeyByName: [String: String] = [:]

    /// 解析并缓存本帧的稳定身份；拿不到稳定身份时明确标记 unresolved。
    private func identity(for name: String, pid: pid_t) -> AppIdentity {
        if let cached = identityCache[pid] {
            identityKeyByName[name] = cached.storageKey
            return cached
        }
        let resolved = AppIdentityResolver.resolve(pid: pid, name: name)
        identityCache[pid] = resolved
        identityKeyByName[name] = resolved.storageKey
        return resolved
    }

    private func captureIcon(_ identityKey: String, pid: pid_t) {
        let nameKey = identityKey as NSString
        guard iconCache.object(forKey: nameKey) == nil, !iconSkipSet.contains(identityKey) else { return }
        guard let context else { return }
        let key = identityKey
        let predicate = #Predicate<StatsAppIdentity> { $0.appKey == key }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)).first) ?? nil
        if let stored = existing?.iconPNG, Self.iconPixels(stored) >= Int(Self.iconSize) {
            iconCache.setObject(stored as NSData, forKey: nameKey)
            return
        }
        // 守护进程(.prohibited 或无 Launch Services 注册)使用通用系统图标,
        // 不落库——数十个守护进程共用同一张图标,冗余存储可达数 MB。
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy != .prohibited else {
            iconSkipSet.insert(identityKey)
            return
        }
        guard let png = ProcessIconCache.fullSizePNG(forPID: pid, sidePixels: Int(Self.iconSize)) else { return }
        iconCache.setObject(png as NSData, forKey: nameKey)
        if let existing {
            existing.iconPNG = png
        } else {
            let displayName = identityKeyByName.first(where: { $0.value == identityKey })?.key ?? identityKey
            let kind = identityKey.split(separator: ":").first.map(String.init)
            context.insert(StatsAppIdentity(
                appKey: identityKey,
                name: displayName,
                iconPNG: png,
                identityKind: kind
            ))
        }
    }

    private static func iconPixels(_ data: Data) -> Int {
        NSBitmapImageRep(data: data)?.pixelsWide ?? 0
    }

    private func iconPNGLocked(for name: String) -> Data? {
        let nameKey = name as NSString
        if let cached = iconCache.object(forKey: nameKey) { return cached as Data }
        guard let context else { return nil }
        // 优先根据身份键查询，缺失时回退至显示名称。
        let identityKey = identityKeyByName[name] ?? name
        let predicate = #Predicate<StatsAppIdentity> { $0.appKey == identityKey }
        var data = (try? context.fetch(FetchDescriptor(predicate: predicate)).first)?.iconPNG
        if data == nil, identityKey != name {
            let fallback = #Predicate<StatsAppIdentity> { $0.appKey == name }
            data = (try? context.fetch(FetchDescriptor(predicate: fallback)).first)?.iconPNG
        }
        if let data {
            iconCache.setObject(data as NSData, forKey: nameKey)
        }
        return data
    }

    // MARK: - 事件持久化

    /// 写入或更新一条确认事件（按 eventID 幂等）。
    func persist(event: PersistedAppEvent) {
        queue.async { [weak self] in
            self?.persistLocked(event)
        }
    }

    /// 同步写入：供需要在返回后立刻读回的场景（例如测试与退出前的收口）。
    func persistSynchronously(event: PersistedAppEvent) {
        queue.sync {
            persistLocked(event)
        }
    }

    private func persistLocked(_ event: PersistedAppEvent) {
        ensureContextLocked()
        guard let context else { return }
        let key = event.eventID
        let predicate = #Predicate<StatsAppEvent> { $0.eventID == key }
        let row = (try? context.fetch(FetchDescriptor(predicate: predicate)).first) ?? nil
        if let row {
            row.appKey = event.appKey
            row.name = event.name
            row.endedAt = event.endedAt
            row.lastEffectiveAt = event.lastEffectiveAt
            row.continuousHighSeconds = event.continuousHighSeconds
            row.eventSpanSeconds = event.eventSpanSeconds
            row.averageUsage = event.averageUsage
            row.peakUsage = event.peakUsage
            row.observationCount = event.observationCount
            row.segmentsJSON = Self.encodeSegments(event.segments)
            row.state = event.state
            row.endReason = event.endReason
            row.notified = event.notified
        } else {
            context.insert(StatsAppEvent(
                eventID: event.eventID,
                appKey: event.appKey,
                name: event.name,
                metric: event.metric,
                startedAt: event.startedAt,
                endedAt: event.endedAt,
                lastEffectiveAt: event.lastEffectiveAt,
                continuousHighSeconds: event.continuousHighSeconds,
                eventSpanSeconds: event.eventSpanSeconds,
                averageUsage: event.averageUsage,
                peakUsage: event.peakUsage,
                observationCount: event.observationCount,
                segmentsJSON: Self.encodeSegments(event.segments),
                state: event.state,
                endReason: event.endReason,
                notified: event.notified
            ))
        }
        do {
            try context.save()
        } catch {
            // 保存失败时保留当前上下文供后续重试。
            AppLogger.settings.error("Statistics event persist failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// 查询与 [from, to) 有交集的事件。完全在范围外的事件不进列表。
    func events(from: Date, to: Date) -> [PersistedAppEvent] {
        queue.sync {
            guard let context else { return [] }
            let predicate = #Predicate<StatsAppEvent> { $0.startedAt < to && $0.endedAt > from }
            let rows = (try? context.fetch(
                FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            )) ?? []
            return rows.map {
                PersistedAppEvent(
                    eventID: $0.eventID,
                    appKey: $0.appKey,
                    name: $0.name,
                    metric: $0.metric,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    lastEffectiveAt: $0.lastEffectiveAt,
                    continuousHighSeconds: $0.continuousHighSeconds,
                    eventSpanSeconds: $0.eventSpanSeconds,
                    averageUsage: $0.averageUsage,
                    peakUsage: $0.peakUsage,
                    observationCount: $0.observationCount,
                    segments: Self.decodeSegments($0.segmentsJSON),
                    state: $0.state,
                    endReason: $0.endReason,
                    notified: $0.notified
                )
            }
        }
    }

    /// 重启时把持久化中仍处于进行中状态的事件标记为中断，结束时间取最后有效观测时刻。
    func interruptPersistedOngoing(reason: String) {
        queue.async { [weak self] in
            self?.interruptPersistedOngoingLocked(reason: reason)
        }
    }

    /// 同步版本：应用退出或测试中需要在返回后立刻读回。
    func interruptPersistedOngoingSynchronously(reason: String) {
        queue.sync {
            interruptPersistedOngoingLocked(reason: reason)
        }
    }

    private func interruptPersistedOngoingLocked(reason: String) {
        ensureContextLocked()
        guard let context else { return }
        let ongoing = "ongoing"
        let predicate = #Predicate<StatsAppEvent> { $0.state == ongoing }
        let rows = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        guard !rows.isEmpty else { return }
        for row in rows {
            row.state = "interrupted"
            row.endReason = reason
            row.endedAt = row.lastEffectiveAt
            row.eventSpanSeconds = row.lastEffectiveAt.timeIntervalSince(row.startedAt)
        }
        try? context.save()
    }

    /// 查询某应用持久化的图标 PNG（内存缓存命中即返，未命中查库）
    func iconPNG(for name: String) -> Data? {
        queue.sync {
            iconPNGLocked(for: name)
        }
    }

    // MARK: - 查询

    struct AppRankEntry {
        let appKey: String
        let name: String
        let value: Double
        let secondary: Double
        let iconPNG: Data?
    }

    private struct AppAggregatedMetrics {
        var name: String
        var cpuScore: Double = 0; var cpuSamples: Int = 0
        var gpuScore: Double = 0; var gpuSamples: Int = 0
        var memSum: Double = 0; var memSamples: Int = 0
        var netDown: Double = 0; var netUp: Double = 0
        var diskRead: Double = 0; var diskWrite: Double = 0
        var cpuTier1: Int = 0; var cpuTier2: Int = 0; var cpuTier3: Int = 0
        var cpuPeak: Double = 0
        var gpuTier1: Int = 0; var gpuTier2: Int = 0; var gpuTier3: Int = 0
        var gpuPeak: Double = 0
        var memTier1: Int = 0; var memTier2: Int = 0; var memTier3: Int = 0
        var memPeak: Double = 0
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
            var aggregated: [String: AppAggregatedMetrics] = [:]
            rows.forEach { row in
                if var merged = aggregated[row.appKey] {
                    merged.cpuScore += row.cpuScore; merged.cpuSamples += row.cpuSamples
                    merged.gpuScore += row.gpuScore; merged.gpuSamples += row.gpuSamples
                    merged.memSum += row.memSum; merged.memSamples += row.memSamples
                    merged.netDown += row.netDown; merged.netUp += row.netUp
                    merged.diskRead += row.diskRead; merged.diskWrite += row.diskWrite
                    merged.cpuTier1 += row.cpuTier1; merged.cpuTier2 += row.cpuTier2; merged.cpuTier3 += row.cpuTier3
                    merged.cpuPeak = max(merged.cpuPeak, row.cpuPeak)
                    merged.gpuTier1 += row.gpuTier1; merged.gpuTier2 += row.gpuTier2; merged.gpuTier3 += row.gpuTier3
                    merged.gpuPeak = max(merged.gpuPeak, row.gpuPeak)
                    merged.memTier1 += row.memTier1; merged.memTier2 += row.memTier2; merged.memTier3 += row.memTier3
                    merged.memPeak = max(merged.memPeak, row.memPeak)
                    merged.name = row.name
                    aggregated[row.appKey] = merged
                } else {
                    var fresh = AppAggregatedMetrics(name: row.name)
                    fresh.cpuScore = row.cpuScore; fresh.cpuSamples = row.cpuSamples
                    fresh.gpuScore = row.gpuScore; fresh.gpuSamples = row.gpuSamples
                    fresh.memSum = row.memSum; fresh.memSamples = row.memSamples
                    fresh.netDown = row.netDown; fresh.netUp = row.netUp
                    fresh.diskRead = row.diskRead; fresh.diskWrite = row.diskWrite
                    fresh.cpuTier1 = row.cpuTier1; fresh.cpuTier2 = row.cpuTier2; fresh.cpuTier3 = row.cpuTier3
                    fresh.cpuPeak = row.cpuPeak
                    fresh.gpuTier1 = row.gpuTier1; fresh.gpuTier2 = row.gpuTier2; fresh.gpuTier3 = row.gpuTier3
                    fresh.gpuPeak = row.gpuPeak
                    fresh.memTier1 = row.memTier1; fresh.memTier2 = row.memTier2; fresh.memTier3 = row.memTier3
                    fresh.memPeak = row.memPeak
                    aggregated[row.appKey] = fresh
                }
            }

            let entries: [(key: String, name: String, value: Double, secondary: Double)]
            switch category {
            case .cpu:
                entries = aggregated
                    .filter { $0.value.cpuSamples > 0 }
                    .map { ($0.key, $0.value.name, $0.value.cpuScore / Double($0.value.cpuSamples), Double($0.value.cpuSamples)) }
            case .memory:
                entries = aggregated
                    .filter { $0.value.memSamples > 0 }
                    .map { ($0.key, $0.value.name, $0.value.memSum / Double($0.value.memSamples), Double($0.value.memSamples)) }
            case .gpu:
                entries = aggregated
                    .filter { $0.value.gpuSamples > 0 }
                    .map { ($0.key, $0.value.name, $0.value.gpuScore / Double($0.value.gpuSamples), Double($0.value.gpuSamples)) }
            case .network:
                entries = aggregated
                    .map { ($0.key, $0.value.name, $0.value.netDown + $0.value.netUp, $0.value.netDown) }
            }

            let topEntries = entries
                .sorted { $0.value > $1.value }
                .prefix(limit)

            let result = topEntries.map { entry in
                AppRankEntry(
                    appKey: entry.key,
                    name: entry.name,
                    value: entry.value,
                    secondary: entry.secondary,
                    iconPNG: self.iconPNGLocked(for: entry.key)
                )
            }

            if !context.hasChanges {
                resetContextLocked()
            }

            return result
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
        let diskReadBytes: Double
        let diskWriteBytes: Double
        let cpuTier1: Int
        let cpuTier2: Int
        let cpuTier3: Int
        let cpuPeak: Double
        let gpuTier1: Int
        let gpuTier2: Int
        let gpuTier3: Int
        let gpuPeak: Double
        let memTier1: Int
        let memTier2: Int
        let memTier3: Int
        let memPeak: Double
    }

    /// 按右开区间 `[fromDay, toDay)` 查询日级应用聚合行。
    func dailyRows(fromDay: Int64, toDay: Int64) -> [DailyAppRow] {
        queue.sync {
            guard let context else { return [] }
            let predicate = #Predicate<StatsAppDaily> { $0.day >= fromDay && $0.day < toDay }
            let rows = (try? context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.day)]))) ?? []
            let result = rows.map { row in
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
                    netUpBytes: row.netUp,
                    diskReadBytes: row.diskRead,
                    diskWriteBytes: row.diskWrite,
                    cpuTier1: row.cpuTier1,
                    cpuTier2: row.cpuTier2,
                    cpuTier3: row.cpuTier3,
                    cpuPeak: row.cpuPeak,
                    gpuTier1: row.gpuTier1,
                    gpuTier2: row.gpuTier2,
                    gpuTier3: row.gpuTier3,
                    gpuPeak: row.gpuPeak,
                    memTier1: row.memTier1,
                    memTier2: row.memTier2,
                    memTier3: row.memTier3,
                    memPeak: row.memPeak
                )
            }
            if !context.hasChanges {
                resetContextLocked()
            }
            return result
        }
    }

    /// 全部应用身份(含图标),报表用。`hasStableIdentity` 为 false 表示这是旧版
    /// 按显示名存储的行，其历史应标为旧版估算。
    func identities() -> [(appKey: String, name: String, iconPNG: Data?, hasStableIdentity: Bool)] {
        queue.sync {
            guard let context else { return [] }
            let rows = (try? context.fetch(FetchDescriptor<StatsAppIdentity>())) ?? []
            let result = rows.map { ($0.appKey, $0.name, $0.iconPNG, $0.hasStableIdentity) }
            if !context.hasChanges {
                resetContextLocked()
            }
            return result
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
            // 早于保留窗口的确认事件与日汇总保持一致口径清理。
            let cutoff = Date(timeIntervalSince1970: TimeInterval(Self.dateFromDayKey(day)))
            let eventRows = (try? context.fetch(FetchDescriptor<StatsAppEvent>(
                predicate: #Predicate { $0.endedAt < cutoff }
            ))) ?? []
            eventRows.forEach { context.delete($0) }
            repairUsageMetaLocked()
            do {
                try context.save()
                compactDatabaseLocked()
                resetContextLocked()
            } catch {
                AppLogger.settings.error("Statistics delete-before save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 删除日键区间 [fromDay, toDay) 内的应用聚合/打卡/电池行(存储浏览按桶清理)。
    /// 先 flush 当日内存累加器:区间覆盖今天时,已采样未落库的部分一并入删。
    /// 应用身份(名称+图标)保留,与 deleteBefore 同口径。
    func deleteRange(fromDay: Int64, toDay: Int64) {
        queue.sync {
            flushLocked()
            // flushLocked 会重置 context，此处重新获取以保证在同一上下文中执行后续删除与保存。
            guard let context else { return }
            let appRows = (try? context.fetch(FetchDescriptor<StatsAppDaily>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            appRows.forEach { context.delete($0) }
            let activeRows = (try? context.fetch(FetchDescriptor<StatsActiveDay>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            activeRows.forEach { context.delete($0) }
            let batteryRows = (try? context.fetch(FetchDescriptor<StatsBatteryDaily>(predicate: #Predicate { $0.day >= fromDay && $0.day < toDay }))) ?? []
            batteryRows.forEach { context.delete($0) }
            // 删除指定区间内对应时间戳范围的确认事件，与日汇总保持一致。
            let lowerBound = Date(timeIntervalSince1970: TimeInterval(Self.dateFromDayKey(fromDay)))
            let upperBound = Date(timeIntervalSince1970: TimeInterval(Self.dateFromDayKey(toDay)))
            let eventRows = (try? context.fetch(FetchDescriptor<StatsAppEvent>(
                predicate: #Predicate { $0.startedAt < upperBound && $0.endedAt > lowerBound }
            ))) ?? []
            eventRows.forEach { context.delete($0) }
            repairUsageMetaLocked()
            do {
                try context.save()
                compactDatabaseLocked()
                resetContextLocked()
            } catch {
                AppLogger.settings.error("Statistics delete-range save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 截断 WAL 并压缩数据库主文件,回收已删除行释放的空闲页(freelist)。
    private func compactDatabaseLocked() {
        guard let url = databaseURL else { return }
        if let breakdownHandle {
            sqlite3_close_v2(breakdownHandle)
            self.breakdownHandle = nil
        }
        var rwHandle: OpaquePointer?
        if sqlite3_open_v2(url.path, &rwHandle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let rwHandle {
            sqlite3_busy_timeout(rwHandle, 3_000)
            sqlite3_exec(rwHandle, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
            sqlite3_exec(rwHandle, "VACUUM", nil, nil, nil)
            sqlite3_close_v2(rwHandle)
        }
    }

    /// 清空全部应用统计数据（应用聚合、身份图标、电池快照）。
    /// 通过销毁并重建库文件彻底回收存储空间，保留打卡与活跃天数元信息。
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
            iconCache.removeAllObjects()
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

    /// 编码/解码事件的有效覆盖分段。
    ///
    /// 分段用于按查询范围精确裁剪时长与均值。旧数据没有分段，解码得到空数组，
    /// 调用方回退到比例折算，不会因此显示为零。
    private struct SegmentDTO: Codable {
        let start: Double
        let end: Double
        let average: Double
    }

    static func encodeSegments(_ segments: [AppResourceEventStateMachine.CoveredSegment]) -> Data? {
        guard !segments.isEmpty else { return nil }
        let dto = segments.map {
            SegmentDTO(
                start: $0.start.timeIntervalSince1970,
                end: $0.end.timeIntervalSince1970,
                average: $0.averageValue
            )
        }
        return try? JSONEncoder().encode(dto)
    }

    static func decodeSegments(_ data: Data?) -> [AppResourceEventStateMachine.CoveredSegment] {
        guard let data,
              let dto = try? JSONDecoder().decode([SegmentDTO].self, from: data) else { return [] }
        return dto.map {
            AppResourceEventStateMachine.CoveredSegment(
                start: Date(timeIntervalSince1970: $0.start),
                end: Date(timeIntervalSince1970: $0.end),
                averageValue: $0.average
            )
        }
    }

    /// 把日键还原成当天零点的 unix 秒，供按时间戳存储的事件区间使用。
    /// 只用于把日键范围转成事件查询边界，不参与展示。
    static func dateFromDayKey(_ key: Int64, calendar: Calendar = .current) -> Int64 {
        let year = Int(key / 10_000)
        let month = Int((key % 10_000) / 100)
        let day = Int(key % 100)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return key }
        return Int64(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> Int64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return Int64(components.year ?? 0) * 10_000 + Int64(components.month ?? 0) * 100 + Int64(components.day ?? 0)
    }

    /// 将查询时间区间 [from, to) 转换为日键右开范围 `[fromDay, toDayExclusive)`。
    struct DayRange: Sendable, Equatable {
        let fromDay: Int64
        let toDayExclusive: Int64

        func contains(day: Int64) -> Bool {
            day >= fromDay && day < toDayExclusive
        }
    }

    static func dayRange(from: Date, to: Date, calendar: Calendar) -> DayRange {
        let fromDay = dayKey(from, calendar: calendar)
        let toDayStart = calendar.startOfDay(for: to)
        // 结束端点恰是某天零点时，该天不属于本区间；否则结束端点所在日整天参与统计。
        let toDay = dayKey(to, calendar: calendar)
        let isExactDayStart = to == toDayStart
        let exclusive = isExactDayStart
            ? toDay
            : dayKey(calendar.date(byAdding: .day, value: 1, to: toDayStart) ?? to, calendar: calendar)
        return DayRange(fromDay: fromDay, toDayExclusive: exclusive)
    }
}

/// 持久化的应用资源高占用事件，记录有效区间、均值峰值、覆盖分段及结束状态。
@Model
final class StatsAppEvent {
    /// 稳定事件 ID。同一事件重复写入时按它幂等更新。
    @Attribute(.unique) var eventID: String
    var appKey: String
    var name: String
    var metric: String
    var startedAt: Date
    var endedAt: Date
    var lastEffectiveAt: Date
    /// 有效高占用秒数。
    var continuousHighSeconds: Double
    /// 首末观测跨度。
    var eventSpanSeconds: Double
    var averageUsage: Double
    var peakUsage: Double
    var observationCount: Int
    /// 有效覆盖分段（JSON 编码）。若为空则回退为空数组。
    var segmentsJSON: Data?
    var state: String
    var endReason: String?
    var notified: Bool

    init(
        eventID: String,
        appKey: String,
        name: String,
        metric: String,
        startedAt: Date,
        endedAt: Date,
        lastEffectiveAt: Date,
        continuousHighSeconds: Double,
        eventSpanSeconds: Double,
        averageUsage: Double,
        peakUsage: Double,
        observationCount: Int,
        segmentsJSON: Data?,
        state: String,
        endReason: String?,
        notified: Bool
    ) {
        self.eventID = eventID
        self.appKey = appKey
        self.name = name
        self.metric = metric
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastEffectiveAt = lastEffectiveAt
        self.continuousHighSeconds = continuousHighSeconds
        self.eventSpanSeconds = eventSpanSeconds
        self.averageUsage = averageUsage
        self.peakUsage = peakUsage
        self.observationCount = observationCount
        self.segmentsJSON = segmentsJSON
        self.state = state
        self.endReason = endReason
        self.notified = notified
    }
}


/// 事件持久化的值类型：跨队列传递用，不直接把 SwiftData 实体交给调用方。
nonisolated struct PersistedAppEvent: Sendable, Equatable {
    let eventID: String
    let appKey: String
    let name: String
    let metric: String
    let startedAt: Date
    let endedAt: Date
    let lastEffectiveAt: Date
    let continuousHighSeconds: Double
    let eventSpanSeconds: Double
    let averageUsage: Double
    let peakUsage: Double
    let observationCount: Int
    /// 有效覆盖分段。缺失时可按比例折算。
    var segments: [AppResourceEventStateMachine.CoveredSegment] = []
    let state: String
    let endReason: String?
    let notified: Bool
}
