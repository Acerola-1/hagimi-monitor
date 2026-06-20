import Foundation
import SwiftData
import os.log

/// 内存桶：累加当前小时的采样值
private struct SampleBucket {
    // MARK: - 现有字段
    var sum: Double = 0
    var peak: Double = -.greatestFiniteMagnitude
    var low: Double = .greatestFiniteMagnitude
    var count: Int = 0
    var bytesInSum: Int64 = 0
    var bytesOutSum: Int64 = 0
    var bytesReadSum: Int64 = 0
    var bytesWrittenSum: Int64 = 0
    var powerSum: Double = 0
    var powerCount: Int = 0

    // MARK: - Phase 1 新增
    var swapUsedSum: Double = 0
    var swapUsedCount: Int = 0
    var pressureLevelMax: Int16 = -1
    var thermalStateMax: Int16 = -1
    var swapinsDelta: Int64 = 0
    var swapoutsDelta: Int64 = 0

    // MARK: - Phase 2 新增
    var cpuSystemSum: Double = 0
    var cpuUserSum: Double = 0
    var cpuIdleSum: Double = 0
    var cpuTempSum: Double = 0
    var cpuTempCount: Int = 0
    var memoryUsedSum: Double = 0
    var memoryUsedCount: Int = 0
    var diskFree: Int64 = 0
    var diskFreeCount: Int = 0
    var netPeakDownload: Double = 0
    var netPeakUpload: Double = 0
    var diskPeakRead: Double = 0
    var diskPeakWrite: Double = 0

    // MARK: - Phase 3 新增
    var gpuMemorySum: Double = 0
    var gpuMemoryCount: Int = 0
    var gpuRenderSum: Double = 0
    var gpuTilerSum: Double = 0
    var gpuUtilCount: Int = 0
    var batteryHealthSum: Double = 0
    var batteryHealthCount: Int = 0
    var batteryCycleCount: Int = 0
    var batteryCycleCountSet: Bool = false
    var batteryTempSum: Double = 0
    var batteryTempCount: Int = 0
    var onBatteryCount: Int = 0

    // MARK: - Mutating Methods

    mutating func add(value: Double) {
        sum += value
        peak = max(peak, value)
        low = min(low, value)
        count += 1
    }

    mutating func addBytes(in inBytes: Int64, out outBytes: Int64) {
        bytesInSum += inBytes
        bytesOutSum += outBytes
    }

    mutating func addDiskBytes(read: Int64, written: Int64) {
        bytesReadSum += read
        bytesWrittenSum += written
    }

    mutating func addPower(_ watts: Double) {
        powerSum += watts
        powerCount += 1
    }

    var avg: Double { count > 0 ? sum / Double(count) : 0 }
    var avgPower: Double? { powerCount > 0 ? powerSum / Double(powerCount) : nil }
}

/// 记录采样数据到 SwiftData
@MainActor
final class StatisticsRecorder {
    private let container: ModelContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hagimi", category: "StatisticsRecorder")

    /// 当前小时的内存桶 [MonitorKind.rawValue: SampleBucket]
    private var buckets: [String: SampleBucket] = [:]
    /// 当前小时起始时间
    private var currentHour: Date
    /// 上次采样的累计值（用于计算差值）
    private var lastCumulative: [String: (bytesIn: Int64, bytesOut: Int64, bytesRead: Int64, bytesWritten: Int64, swapins: Int64, swapouts: Int64)] = [:]

    // MARK: - Batch Event Detection State
    /// 上一小时的 Swap 使用量（用于检测 Swap 突增）
    private var previousHourSwapUsed: Double?
    /// 上一小时的磁盘 I/O 总量（用于检测 I/O 峰值）
    private var previousHourDiskIO: Double?
    /// 上一小时的网络流量总量（用于检测网络峰值）
    private var previousHourNetworkTotal: Double?

    init(container: ModelContainer) {
        self.container = container
        self.currentHour = StatisticsRecorder.startOfHour(Date())
    }

    /// 使用全局共享容器创建。Recorder 与 Aggregator 必须共用同一容器。
    convenience init() {
        self.init(container: StatisticsStore.container)
    }

    /// 接收一批采样结果，累加到内存桶
    func record(modules: [MonitorModule]) {
        let now = Date()
        let hour = StatisticsRecorder.startOfHour(now)

        // 小时切换：flush 上一小时的桶
        if hour != currentHour {
            flushCurrentBuckets()
            currentHour = hour
        }

        for module in modules {
            let kind = module.kind.rawValue
            var bucket = buckets[kind] ?? SampleBucket()
            bucket.add(value: module.value)

            // 网络：从 metrics 读取累计字节，计算差值
            if module.kind == .network {
                if let bytesIn = metricInt64(module, key: "cumulativeBytesIn"),
                   let bytesOut = metricInt64(module, key: "cumulativeBytesOut") {
                    let prev = lastCumulative[kind]
                    let deltaIn = max(0, bytesIn - (prev?.bytesIn ?? bytesIn))
                    let deltaOut = max(0, bytesOut - (prev?.bytesOut ?? bytesOut))
                    bucket.addBytes(in: deltaIn, out: deltaOut)
                    lastCumulative[kind] = (bytesIn: bytesIn, bytesOut: bytesOut,
                                            bytesRead: prev?.bytesRead ?? 0,
                                            bytesWritten: prev?.bytesWritten ?? 0,
                                            swapins: prev?.swapins ?? 0,
                                            swapouts: prev?.swapouts ?? 0)
                    // Phase 2: 网络速率取 peak
                    if let download = metricNumeric(module, key: "download") {
                        bucket.netPeakDownload = max(bucket.netPeakDownload, download)
                    }
                    if let upload = metricNumeric(module, key: "upload") {
                        bucket.netPeakUpload = max(bucket.netPeakUpload, upload)
                    }
                }
            }

            // 存储：从 metrics 读取累计磁盘字节，计算差值
            if module.kind == .storage {
                if let bytesRead = metricInt64(module, key: "cumulativeBytesRead"),
                   let bytesWritten = metricInt64(module, key: "cumulativeBytesWritten") {
                    let prev = lastCumulative[kind]
                    let deltaRead = max(0, bytesRead - (prev?.bytesRead ?? bytesRead))
                    let deltaWritten = max(0, bytesWritten - (prev?.bytesWritten ?? bytesWritten))
                    bucket.addDiskBytes(read: deltaRead, written: deltaWritten)
                    lastCumulative[kind] = (bytesIn: prev?.bytesIn ?? 0,
                                            bytesOut: prev?.bytesOut ?? 0,
                                            bytesRead: bytesRead,
                                            bytesWritten: bytesWritten,
                                            swapins: prev?.swapins ?? 0,
                                            swapouts: prev?.swapouts ?? 0)
                    // Phase 2: 磁盘速率取 peak
                    if let readRate = metricNumeric(module, key: "disk-read-rate") {
                        bucket.diskPeakRead = max(bucket.diskPeakRead, readRate)
                    }
                    if let writeRate = metricNumeric(module, key: "disk-write-rate") {
                        bucket.diskPeakWrite = max(bucket.diskPeakWrite, writeRate)
                    }
                } else {
                    AppLogger.sampler.warning("Storage metricInt64 failed: cumulativeBytesRead/cumulativeBytesWritten not found in module metrics")
                }
                // Phase 2: diskFree 取最新值
                if let free = metricNumeric(module, key: "free") {
                    bucket.diskFree = Int64(free)
                    bucket.diskFreeCount += 1
                }
            }

            // 功耗：从 metrics 读取瓦特
            if module.kind == .power {
                if let watts = metricDouble(module, key: "power-watts") {
                    bucket.addPower(watts)
                }
            }

            // Phase 1: 内存模块新增指标
            if module.kind == .memory {
                if let swapUsed = metricNumeric(module, key: "swap-used") {
                    bucket.swapUsedSum += swapUsed
                    bucket.swapUsedCount += 1
                }
                if let pressureLevel = metricNumeric(module, key: "pressure-level") {
                    let level = Int16(pressureLevel)
                    bucket.pressureLevelMax = max(bucket.pressureLevelMax, level)
                }
                if let swapinsVal = metricNumeric(module, key: "swapins") {
                    let swapins = Int64(swapinsVal)
                    let prev = lastCumulative["memory"]
                    let delta = max(0, swapins - (prev?.swapins ?? swapins))
                    bucket.swapinsDelta += delta
                    lastCumulative["memory"] = (bytesIn: prev?.bytesIn ?? 0,
                                                bytesOut: prev?.bytesOut ?? 0,
                                                bytesRead: prev?.bytesRead ?? 0,
                                                bytesWritten: prev?.bytesWritten ?? 0,
                                                swapins: swapins,
                                                swapouts: prev?.swapouts ?? 0)
                }
                if let swapoutsVal = metricNumeric(module, key: "swapouts") {
                    let swapouts = Int64(swapoutsVal)
                    let prev = lastCumulative["memory"]
                    let delta = max(0, swapouts - (prev?.swapouts ?? swapouts))
                    bucket.swapoutsDelta += delta
                    lastCumulative["memory"] = (bytesIn: prev?.bytesIn ?? 0,
                                                bytesOut: prev?.bytesOut ?? 0,
                                                bytesRead: prev?.bytesRead ?? 0,
                                                bytesWritten: prev?.bytesWritten ?? 0,
                                                swapins: prev?.swapins ?? 0,
                                                swapouts: swapouts)
                }
                // Phase 2: memoryUsed
                if let used = metricNumeric(module, key: "used") {
                    bucket.memoryUsedSum += used
                    bucket.memoryUsedCount += 1
                }
            }

            // Phase 1: 热压力等级（直接读 ProcessInfo）
            if module.kind == .cpu {
                let thermal = Int16(ProcessInfo.processInfo.thermalState.rawValue)
                bucket.thermalStateMax = max(bucket.thermalStateMax, thermal)
                // Phase 2: CPU 分解
                if let sys = metricNumeric(module, key: "system") {
                    bucket.cpuSystemSum += sys
                }
                if let usr = metricNumeric(module, key: "user") {
                    bucket.cpuUserSum += usr
                }
                if let idle = metricNumeric(module, key: "idle") {
                    bucket.cpuIdleSum += idle
                }
                if let temp = metricNumeric(module, key: "temperature") {
                    bucket.cpuTempSum += temp
                    bucket.cpuTempCount += 1
                }
            }

            // Phase 3: GPU 模块
            if module.kind == .gpu {
                if let vram = metricNumeric(module, key: "gpu-memory") {
                    bucket.gpuMemorySum += vram
                    bucket.gpuMemoryCount += 1
                }
                if let render = metricNumeric(module, key: "render") {
                    bucket.gpuRenderSum += render
                    bucket.gpuUtilCount += 1
                }
                if let tiler = metricNumeric(module, key: "tiler") {
                    bucket.gpuTilerSum += tiler
                    bucket.gpuUtilCount += 1
                }
            }

            // Phase 3: 电池模块
            if module.kind == .battery {
                if let health = metricNumeric(module, key: "health") {
                    bucket.batteryHealthSum += health
                    bucket.batteryHealthCount += 1
                }
                if let cycles = metricNumeric(module, key: "cycle-count") {
                    bucket.batteryCycleCount = Int(cycles)
                    bucket.batteryCycleCountSet = true
                }
                if let temp = metricNumeric(module, key: "temperature") {
                    bucket.batteryTempSum += temp
                    bucket.batteryTempCount += 1
                }
                // onBatteryPower: 检查 type 是否为 battery
                let typeMetric = module.metrics.first(where: { $0.name == "type" })
                if typeMetric?.value == "battery" {
                    bucket.onBatteryCount += 1
                }
            }

            buckets[kind] = bucket
        }
    }

    /// 当前小时尚未落库的内存桶快照（供「过去24小时」视图合并显示，避免整点前无数据）。
    /// key 为 `MonitorKind.rawValue`。
    func pendingSnapshot() -> [String: PendingBucket] {
        var result: [String: PendingBucket] = [:]
        for (kind, bucket) in buckets where bucket.count > 0 {
            result[kind] = PendingBucket(
                hour: currentHour,
                avg: bucket.avg,
                peak: bucket.peak,
                low: bucket.low,
                bytesIn: bucket.bytesInSum,
                bytesOut: bucket.bytesOutSum,
                bytesRead: bucket.bytesReadSum,
                bytesWritten: bucket.bytesWrittenSum,
                avgPower: bucket.avgPower,
                // Phase 1
                swapUsed: bucket.swapUsedCount > 0 ? Int64(bucket.swapUsedSum / Double(bucket.swapUsedCount)) : nil,
                memoryPressureLevel: bucket.pressureLevelMax >= 0 ? bucket.pressureLevelMax : nil,
                thermalState: bucket.thermalStateMax >= 0 ? bucket.thermalStateMax : nil,
                swapins: bucket.swapinsDelta > 0 ? bucket.swapinsDelta : nil,
                swapouts: bucket.swapoutsDelta > 0 ? bucket.swapoutsDelta : nil,
                // Phase 2
                cpuSystem: bucket.count > 0 ? bucket.cpuSystemSum / Double(bucket.count) : nil,
                cpuUser: bucket.count > 0 ? bucket.cpuUserSum / Double(bucket.count) : nil,
                cpuIdle: bucket.count > 0 ? bucket.cpuIdleSum / Double(bucket.count) : nil,
                cpuTemperature: bucket.cpuTempCount > 0 ? bucket.cpuTempSum / Double(bucket.cpuTempCount) : nil,
                memoryUsed: bucket.memoryUsedCount > 0 ? Int64(bucket.memoryUsedSum / Double(bucket.memoryUsedCount)) : nil,
                diskFree: bucket.diskFreeCount > 0 ? bucket.diskFree : nil,
                netPeakDownload: bucket.netPeakDownload > 0 ? Int64(bucket.netPeakDownload) : nil,
                netPeakUpload: bucket.netPeakUpload > 0 ? Int64(bucket.netPeakUpload) : nil,
                diskPeakRead: bucket.diskPeakRead > 0 ? Int64(bucket.diskPeakRead) : nil,
                diskPeakWrite: bucket.diskPeakWrite > 0 ? Int64(bucket.diskPeakWrite) : nil,
                // Phase 3
                gpuMemoryUsed: bucket.gpuMemoryCount > 0 ? Int64(bucket.gpuMemorySum / Double(bucket.gpuMemoryCount)) : nil,
                gpuRenderUtil: bucket.gpuUtilCount > 0 ? bucket.gpuRenderSum / Double(bucket.gpuUtilCount) : nil,
                gpuTilerUtil: bucket.gpuUtilCount > 0 ? bucket.gpuTilerSum / Double(bucket.gpuUtilCount) : nil,
                batteryHealth: bucket.batteryHealthCount > 0 ? bucket.batteryHealthSum / Double(bucket.batteryHealthCount) : nil,
                batteryCycleCount: bucket.batteryCycleCountSet ? bucket.batteryCycleCount : nil,
                batteryTemperature: bucket.batteryTempCount > 0 ? bucket.batteryTempSum / Double(bucket.batteryTempCount) : nil,
                onBatteryPower: bucket.count > 0 ? Double(bucket.onBatteryCount) / Double(bucket.count) : nil
            )
        }
        return result
    }

    // MARK: - Flush & Cleanup

    /// 将当前桶写入 HourlySample，清理超过 24 小时的旧数据，聚合成 DailyAggregate
    private func flushCurrentBuckets() {
        let context = ModelContext(container)
        let hour = currentHour

        for (kind, bucket) in buckets {
            guard bucket.count > 0 else { continue }
            let sample = HourlySample(
                hour: hour, kind: kind,
                avg: bucket.avg, peak: bucket.peak, low: bucket.low,
                sampleCount: bucket.count,
                bytesInDelta: bucket.bytesInSum > 0 ? bucket.bytesInSum : nil,
                bytesOutDelta: bucket.bytesOutSum > 0 ? bucket.bytesOutSum : nil,
                bytesReadDelta: bucket.bytesReadSum > 0 ? bucket.bytesReadSum : nil,
                bytesWrittenDelta: bucket.bytesWrittenSum > 0 ? bucket.bytesWrittenSum : nil,
                avgPower: bucket.avgPower,
                // Phase 1
                swapUsed: bucket.swapUsedCount > 0 ? Int64(bucket.swapUsedSum / Double(bucket.swapUsedCount)) : nil,
                memoryPressureLevel: bucket.pressureLevelMax >= 0 ? bucket.pressureLevelMax : nil,
                thermalState: bucket.thermalStateMax >= 0 ? bucket.thermalStateMax : nil,
                swapins: bucket.swapinsDelta > 0 ? bucket.swapinsDelta : nil,
                swapouts: bucket.swapoutsDelta > 0 ? bucket.swapoutsDelta : nil,
                // Phase 2
                cpuSystem: bucket.count > 0 ? bucket.cpuSystemSum / Double(bucket.count) : nil,
                cpuUser: bucket.count > 0 ? bucket.cpuUserSum / Double(bucket.count) : nil,
                cpuIdle: bucket.count > 0 ? bucket.cpuIdleSum / Double(bucket.count) : nil,
                cpuTemperature: bucket.cpuTempCount > 0 ? bucket.cpuTempSum / Double(bucket.cpuTempCount) : nil,
                memoryUsed: bucket.memoryUsedCount > 0 ? Int64(bucket.memoryUsedSum / Double(bucket.memoryUsedCount)) : nil,
                diskFree: bucket.diskFreeCount > 0 ? bucket.diskFree : nil,
                netPeakDownload: bucket.netPeakDownload > 0 ? Int64(bucket.netPeakDownload) : nil,
                netPeakUpload: bucket.netPeakUpload > 0 ? Int64(bucket.netPeakUpload) : nil,
                diskPeakRead: bucket.diskPeakRead > 0 ? Int64(bucket.diskPeakRead) : nil,
                diskPeakWrite: bucket.diskPeakWrite > 0 ? Int64(bucket.diskPeakWrite) : nil,
                // Phase 3
                gpuMemoryUsed: bucket.gpuMemoryCount > 0 ? Int64(bucket.gpuMemorySum / Double(bucket.gpuMemoryCount)) : nil,
                gpuRenderUtil: bucket.gpuUtilCount > 0 ? bucket.gpuRenderSum / Double(bucket.gpuUtilCount) : nil,
                gpuTilerUtil: bucket.gpuUtilCount > 0 ? bucket.gpuTilerSum / Double(bucket.gpuUtilCount) : nil,
                batteryHealth: bucket.batteryHealthCount > 0 ? bucket.batteryHealthSum / Double(bucket.batteryHealthCount) : nil,
                batteryCycleCount: bucket.batteryCycleCountSet ? bucket.batteryCycleCount : nil,
                batteryTemperature: bucket.batteryTempCount > 0 ? bucket.batteryTempSum / Double(bucket.batteryTempCount) : nil,
                onBatteryPower: bucket.count > 0 ? Double(bucket.onBatteryCount) / Double(bucket.count) : nil
            )
            context.insert(sample)
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to flush hourly samples: \(error.localizedDescription, privacy: .public)")
        }

        // 批量事件检测
        detectBatchEvents(context: context, buckets: buckets)

        buckets.removeAll()
        cleanupOldSamples(context: context)
        cleanupOldEvents(context: context)
    }

    // MARK: - Batch Event Detection

    /// 在 flush 时检测趋势性事件
    private func detectBatchEvents(context: ModelContext, buckets: [String: SampleBucket]) {
        // Swap 突增检测（增长 >100%）
        if let memBucket = buckets["memory"], memBucket.swapUsedCount > 0 {
            let currentSwap = memBucket.swapUsedSum / Double(memBucket.swapUsedCount)
            if let prev = previousHourSwapUsed, prev > 0, currentSwap > prev * 2 {
                let event = SystemEvent(
                    timestamp: Date(),
                    eventType: SystemEventType.swapUsageSpike.rawValue,
                    severity: 1,
                    title: SystemEventType.swapUsageSpike.title,
                    detail: String(format: "%.0f MB → %.0f MB", prev / 1_048_576, currentSwap / 1_048_576),
                    value: currentSwap,
                    previousValue: prev
                )
                context.insert(event)
            }
            previousHourSwapUsed = currentSwap
        }

        // 磁盘空间不足检测（<5GB warning, <1GB critical）
        if let storageBucket = buckets["storage"], storageBucket.diskFreeCount > 0 {
            let diskFree = Double(storageBucket.diskFree)
            let threshold5GB: Double = 5 * 1024 * 1024 * 1024
            let threshold1GB: Double = 1 * 1024 * 1024 * 1024
            if diskFree < threshold5GB {
                let severity: Int16 = diskFree < threshold1GB ? 2 : 1
                let freeStr = formatBytes(Int64(diskFree))
                let event = SystemEvent(
                    timestamp: Date(),
                    eventType: SystemEventType.diskSpaceLow.rawValue,
                    severity: severity,
                    title: SystemEventType.diskSpaceLow.title,
                    detail: String(localized: "event.disk-space-low") + ": \(freeStr)",
                    value: diskFree
                )
                context.insert(event)
            }
        }

        // 磁盘 I/O 峰值检测（当前小时总 I/O 超过上一小时 3 倍）
        if let storageBucket = buckets["storage"] {
            let currentIO = Double(storageBucket.bytesReadSum + storageBucket.bytesWrittenSum)
            if let prev = previousHourDiskIO, prev > 0, currentIO > prev * 3, currentIO > 100 * 1024 * 1024 {
                let event = SystemEvent(
                    timestamp: Date(),
                    eventType: SystemEventType.diskIOSpike.rawValue,
                    severity: 1,
                    title: SystemEventType.diskIOSpike.title,
                    detail: formatBytes(Int64(currentIO)),
                    value: currentIO,
                    previousValue: prev
                )
                context.insert(event)
            }
            previousHourDiskIO = currentIO > 0 ? currentIO : previousHourDiskIO
        }

        // 网络流量峰值检测（当前小时总流量超过上一小时 3 倍）
        if let netBucket = buckets["network"] {
            let currentTotal = Double(netBucket.bytesInSum + netBucket.bytesOutSum)
            if let prev = previousHourNetworkTotal, prev > 0, currentTotal > prev * 3, currentTotal > 100 * 1024 * 1024 {
                let event = SystemEvent(
                    timestamp: Date(),
                    eventType: SystemEventType.networkSpike.rawValue,
                    severity: 1,
                    title: SystemEventType.networkSpike.title,
                    detail: formatBytes(Int64(currentTotal)),
                    value: currentTotal,
                    previousValue: prev
                )
                context.insert(event)
            }
            previousHourNetworkTotal = currentTotal > 0 ? currentTotal : previousHourNetworkTotal
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to save batch events: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 清理过期事件（info=30天, warning=90天, critical=永久）
    private func cleanupOldEvents(context: ModelContext) {
        let now = Date()
        let calendar = Calendar.current

        for severity in EventSeverity.allCases {
            guard let retentionDays = severity.retentionDays else { continue } // nil = 永久
            let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now)!
            let severityValue = severity.rawValue
            let descriptor = FetchDescriptor<SystemEvent>(
                predicate: #Predicate { $0.severity == severityValue && $0.timestamp < cutoff }
            )
            do {
                let oldEvents = try context.fetch(descriptor)
                for event in oldEvents {
                    context.delete(event)
                }
            } catch {
                logger.error("Failed to cleanup old events for severity \(severity.rawValue): \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to save after event cleanup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 格式化字节数为可读字符串
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    /// 清理超过 24 小时的 HourlySample，聚合成 DailyAggregate
    private func cleanupOldSamples(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        let descriptor = FetchDescriptor<HourlySample>(
            predicate: #Predicate { $0.hour < cutoff }
        )
        guard let oldSamples = try? context.fetch(descriptor), !oldSamples.isEmpty else { return }

        // 按 (kind, 日期) 分组聚合
        let calendar = Calendar.current
        var grouped: [String: [Date: [HourlySample]]] = [:] // [kind: [startOfDay: [sample]]]
        for sample in oldSamples {
            let dayStart = calendar.startOfDay(for: sample.hour)
            grouped[sample.kind, default: [:]][dayStart, default: []].append(sample)
        }

        for (kind, dateGroups) in grouped {
            for (dayStart, samples) in dateGroups {
                let totalCount = samples.reduce(0) { $0 + $1.sampleCount }
                let weightedAvg = samples.reduce(0.0) { $0 + $1.avg * Double($1.sampleCount) } / Double(totalCount)
                let peakVal = samples.map(\.peak).max() ?? 0
                let lowVal = samples.map(\.low).min() ?? 0

                let agg = DailyAggregate(
                    date: dayStart,
                    kind: kind, avg: weightedAvg, peak: peakVal, low: lowVal,
                    sampleCount: totalCount,
                    bytesInDelta: sumOptionalInt64(samples.map(\.bytesInDelta)),
                    bytesOutDelta: sumOptionalInt64(samples.map(\.bytesOutDelta)),
                    bytesReadDelta: sumOptionalInt64(samples.map(\.bytesReadDelta)),
                    bytesWrittenDelta: sumOptionalInt64(samples.map(\.bytesWrittenDelta)),
                    avgPower: avgOptionalDouble(samples.map(\.avgPower), counts: samples.map(\.sampleCount)),
                    // Phase 1: swap 均值，pressure/thermal 取 max，swapins/swapouts 求和
                    swapUsed: avgOptionalInt64(samples.map(\.swapUsed), counts: samples.map(\.sampleCount)),
                    memoryPressureLevel: samples.compactMap(\.memoryPressureLevel).max(),
                    thermalState: samples.compactMap(\.thermalState).max(),
                    swapins: sumOptionalInt64(samples.map(\.swapins)),
                    swapouts: sumOptionalInt64(samples.map(\.swapouts)),
                    // Phase 2
                    cpuSystem: avgOptionalDouble(samples.map(\.cpuSystem), counts: samples.map(\.sampleCount)),
                    cpuUser: avgOptionalDouble(samples.map(\.cpuUser), counts: samples.map(\.sampleCount)),
                    cpuIdle: avgOptionalDouble(samples.map(\.cpuIdle), counts: samples.map(\.sampleCount)),
                    cpuTemperature: avgOptionalDouble(samples.map(\.cpuTemperature), counts: samples.map(\.sampleCount)),
                    memoryUsed: avgOptionalInt64(samples.map(\.memoryUsed), counts: samples.map(\.sampleCount)),
                    diskFree: samples.compactMap(\.diskFree).last,
                    netPeakDownload: samples.compactMap(\.netPeakDownload).max(),
                    netPeakUpload: samples.compactMap(\.netPeakUpload).max(),
                    diskPeakRead: samples.compactMap(\.diskPeakRead).max(),
                    diskPeakWrite: samples.compactMap(\.diskPeakWrite).max(),
                    // Phase 3
                    gpuMemoryUsed: avgOptionalInt64(samples.map(\.gpuMemoryUsed), counts: samples.map(\.sampleCount)),
                    gpuRenderUtil: avgOptionalDouble(samples.map(\.gpuRenderUtil), counts: samples.map(\.sampleCount)),
                    gpuTilerUtil: avgOptionalDouble(samples.map(\.gpuTilerUtil), counts: samples.map(\.sampleCount)),
                    batteryHealth: avgOptionalDouble(samples.map(\.batteryHealth), counts: samples.map(\.sampleCount)),
                    batteryCycleCount: samples.compactMap(\.batteryCycleCount).last,
                    batteryTemperature: avgOptionalDouble(samples.map(\.batteryTemperature), counts: samples.map(\.sampleCount)),
                    onBatteryPower: avgOptionalDouble(samples.map(\.onBatteryPower), counts: samples.map(\.sampleCount))
                )
                context.insert(agg)
            }
        }

        for sample in oldSamples {
            context.delete(sample)
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to cleanup old samples: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private static func startOfHour(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: date))!
    }

    private func metricInt64(_ module: MonitorModule, key: String) -> Int64? {
        guard let metric = module.metrics.first(where: { $0.name == key }),
              let value = Int64(metric.value) else { return nil }
        return value
    }

    private func metricDouble(_ module: MonitorModule, key: String) -> Double? {
        guard let metric = module.metrics.first(where: { $0.name == key }) else { return nil }
        return Double(metric.value)
    }

    private func metricNumeric(_ module: MonitorModule, key: String) -> Double? {
        guard let metric = module.metrics.first(where: { $0.name == key }) else { return nil }
        return metric.numericValue
    }

    private func sumOptionalInt64(_ values: [Int64?]) -> Int64? {
        let sum = values.compactMap { $0 }.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    private func avgOptionalDouble(_ values: [Double?], counts: [Int]) -> Double? {
        var sum = 0.0
        var totalWeight = 0
        for (val, count) in zip(values, counts) {
            if let v = val {
                sum += v * Double(count)
                totalWeight += count
            }
        }
        return totalWeight > 0 ? sum / Double(totalWeight) : nil
    }

    private func avgOptionalInt64(_ values: [Int64?], counts: [Int]) -> Int64? {
        var sum: Int64 = 0
        var totalWeight = 0
        for (val, count) in zip(values, counts) {
            if let v = val {
                sum += v * Int64(count)
                totalWeight += count
            }
        }
        return totalWeight > 0 ? sum / Int64(totalWeight) : nil
    }
}
