import Foundation
import SwiftData
import os.log

/// 时间范围选项
enum StatisticsTimeRange: Equatable {
    case last24Hours
    case lastWeek
    case lastMonth
    case lastYear
    case custom(from: Date, to: Date)

    var title: String {
        switch self {
        case .last24Hours: return String(localized: "stats.range.24h")
        case .lastWeek: return String(localized: "stats.range.week")
        case .lastMonth: return String(localized: "stats.range.month")
        case .lastYear: return String(localized: "stats.range.year")
        case .custom: return String(localized: "stats.range.custom")
        }
    }
}

/// 聚合后的数据点
struct StatisticsDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let avg: Double
    let peak: Double
    let low: Double
    /// 网络字节增量（仅 network 模块有值）
    let bytesIn: Int64?
    let bytesOut: Int64?
    /// 磁盘字节增量（仅 storage 模块有值）
    let bytesRead: Int64?
    let bytesWritten: Int64?

    // Phase 1
    let swapUsed: Int64?
    let memoryPressureLevel: Int16?
    let thermalState: Int16?
    let swapins: Int64?
    let swapouts: Int64?

    // Phase 2
    let cpuSystem: Double?
    let cpuUser: Double?
    let cpuIdle: Double?
    let cpuTemperature: Double?
    let memoryUsed: Int64?
    let diskFree: Int64?
    let netPeakDownload: Int64?
    let netPeakUpload: Int64?
    let diskPeakRead: Int64?
    let diskPeakWrite: Int64?

    // Phase 3
    let gpuMemoryUsed: Int64?
    let gpuRenderUtil: Double?
    let gpuTilerUtil: Double?
    let batteryHealth: Double?
    let batteryCycleCount: Int?
    let batteryTemperature: Double?
    let onBatteryPower: Double?
}

/// 当前小时尚未落库的内存桶快照（由 StatisticsRecorder 导出，供 24h 视图合并）。
struct PendingBucket {
    let hour: Date
    let avg: Double
    let peak: Double
    let low: Double
    let bytesIn: Int64
    let bytesOut: Int64
    let bytesRead: Int64
    let bytesWritten: Int64
    let avgPower: Double?

    // Phase 1
    let swapUsed: Int64?
    let memoryPressureLevel: Int16?
    let thermalState: Int16?
    let swapins: Int64?
    let swapouts: Int64?

    // Phase 2
    let cpuSystem: Double?
    let cpuUser: Double?
    let cpuIdle: Double?
    let cpuTemperature: Double?
    let memoryUsed: Int64?
    let diskFree: Int64?
    let netPeakDownload: Int64?
    let netPeakUpload: Int64?
    let diskPeakRead: Int64?
    let diskPeakWrite: Int64?

    // Phase 3
    let gpuMemoryUsed: Int64?
    let gpuRenderUtil: Double?
    let gpuTilerUtil: Double?
    let batteryHealth: Double?
    let batteryCycleCount: Int?
    let batteryTemperature: Double?
    let onBatteryPower: Double?
}

/// 某个模块的统计摘要
struct StatisticsSummary {
    let kind: MonitorKind
    let avg: Double
    let peak: Double
    let low: Double
    let median: Double
    let points: [StatisticsDataPoint]
    /// 网络/磁盘累计增量
    let totalBytesIn: Int64?
    let totalBytesOut: Int64?
    let totalBytesRead: Int64?
    let totalBytesWritten: Int64?
    /// 功耗平均
    let avgPower: Double?

    // Phase 1 聚合字段
    let avgSwapUsed: Int64?
    let peakMemoryPressureLevel: Int16?
    let peakThermalState: Int16?
    /// 压力等级按采样数加权均值（0=normal…3=unknown），用于健康评分，避免 sticky max 剧烈跳变
    let avgMemoryPressureLevel: Double?
    /// 热状态按采样数加权均值（0=nominal…3=critical），用于健康评分
    let avgThermalState: Double?
    let totalSwapins: Int64?
    let totalSwapouts: Int64?

    // Phase 2 聚合字段
    let avgCpuSystem: Double?
    let avgCpuUser: Double?
    let avgCpuIdle: Double?
    let avgCpuTemperature: Double?
    let avgMemoryUsed: Int64?
    let latestDiskFree: Int64?
    let peakNetDownload: Int64?
    let peakNetUpload: Int64?
    let peakDiskRead: Int64?
    let peakDiskWrite: Int64?

    // Phase 3 聚合字段
    let avgGpuMemoryUsed: Int64?
    let avgGpuRenderUtil: Double?
    let avgGpuTilerUtil: Double?
    let avgBatteryHealth: Double?
    let latestBatteryCycleCount: Int?
    let avgBatteryTemperature: Double?
    let avgOnBatteryPower: Double?
}

/// 按时间范围查询聚合数据
@MainActor
final class StatisticsAggregator {
    private let container: ModelContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hagimi", category: "StatisticsAggregator")

    init(container: ModelContainer) {
        self.container = container
    }

    /// 使用全局共享容器创建。Recorder 与 Aggregator 必须共用同一容器。
    convenience init() {
        self.init(container: StatisticsStore.container)
    }

    /// 查询指定模块在指定时间范围内的统计数据。
    /// - Parameter pending: 当前小时尚未落库的内存桶（仅 24h 视图使用），用于在整点前也能看到当前数据。
    func query(kind: MonitorKind, range: StatisticsTimeRange, pending: PendingBucket? = nil) -> StatisticsSummary {
        let context = ModelContext(container)

        switch range {
        case .last24Hours:
            return queryHourly(kind: kind, context: context, pending: pending)
        case .lastWeek:
            return queryDaily(kind: kind, days: 7, context: context)
        case .lastMonth:
            return queryDaily(kind: kind, days: 30, context: context)
        case .lastYear:
            return queryDaily(kind: kind, days: 365, context: context)
        case .custom(let from, let to):
            // 自定义日期范围最小单位为日，始终查询天级数据
            return queryDaily(kind: kind, from: from, to: to, context: context)
        }
    }

    // MARK: - Event Query

    /// 查询指定时间范围内的系统事件，按时间倒序排列。
    /// - Parameters:
    ///   - range: 时间范围
    ///   - severity: 可选的严重度过滤
    ///   - limit: 返回数量上限（用于分页）
    ///   - offset: 分页偏移
    /// - Returns: 符合条件的系统事件列表
    func queryEvents(range: StatisticsTimeRange, severity: EventSeverity? = nil,
                     limit: Int = 50, offset: Int = 0) -> [SystemEvent] {
        let context = ModelContext(container)
        let (startDate, endDate) = dateRange(for: range)

        var predicate: Predicate<SystemEvent>
        if let severity {
            let severityValue = severity.rawValue
            if let start = startDate {
                predicate = #Predicate { $0.severity == severityValue && $0.timestamp >= start && $0.timestamp <= endDate }
            } else {
                predicate = #Predicate { $0.severity == severityValue && $0.timestamp <= endDate }
            }
        } else {
            if let start = startDate {
                predicate = #Predicate { $0.timestamp >= start && $0.timestamp <= endDate }
            } else {
                predicate = #Predicate { $0.timestamp <= endDate }
            }
        }

        var descriptor = FetchDescriptor<SystemEvent>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to query events: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// 获取指定时间范围内的事件总数
    func countEvents(range: StatisticsTimeRange, severity: EventSeverity? = nil) -> Int {
        let context = ModelContext(container)
        let (startDate, endDate) = dateRange(for: range)

        var predicate: Predicate<SystemEvent>
        if let severity {
            let severityValue = severity.rawValue
            if let start = startDate {
                predicate = #Predicate { $0.severity == severityValue && $0.timestamp >= start && $0.timestamp <= endDate }
            } else {
                predicate = #Predicate { $0.severity == severityValue && $0.timestamp <= endDate }
            }
        } else {
            if let start = startDate {
                predicate = #Predicate { $0.timestamp >= start && $0.timestamp <= endDate }
            } else {
                predicate = #Predicate { $0.timestamp <= endDate }
            }
        }

        let descriptor = FetchDescriptor<SystemEvent>(predicate: predicate)
        do {
            return try context.fetchCount(descriptor)
        } catch {
            logger.error("Failed to count events: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    private func dateRange(for range: StatisticsTimeRange) -> (Date?, Date) {
        let now = Date()
        switch range {
        case .last24Hours:
            return (Calendar.current.date(byAdding: .hour, value: -24, to: now)!, now)
        case .lastWeek:
            return (Calendar.current.date(byAdding: .day, value: -7, to: now)!, now)
        case .lastMonth:
            return (Calendar.current.date(byAdding: .day, value: -30, to: now)!, now)
        case .lastYear:
            return (Calendar.current.date(byAdding: .day, value: -365, to: now)!, now)
        case .custom(let from, let to):
            return (from, to)
        }
    }

    // MARK: - SummaryRow (重构元组为 struct)

    private struct SummaryRow {
        let date: Date
        let avg: Double
        let peak: Double
        let low: Double
        let count: Int
        let bytesIn: Int64?
        let bytesOut: Int64?
        let bytesRead: Int64?
        let bytesWritten: Int64?
        let avgPower: Double?

        // Phase 1
        let swapUsed: Int64?
        let memoryPressureLevel: Int16?
        let thermalState: Int16?
        let swapins: Int64?
        let swapouts: Int64?

        // Phase 2
        let cpuSystem: Double?
        let cpuUser: Double?
        let cpuIdle: Double?
        let cpuTemperature: Double?
        let memoryUsed: Int64?
        let diskFree: Int64?
        let netPeakDownload: Int64?
        let netPeakUpload: Int64?
        let diskPeakRead: Int64?
        let diskPeakWrite: Int64?

        // Phase 3
        let gpuMemoryUsed: Int64?
        let gpuRenderUtil: Double?
        let gpuTilerUtil: Double?
        let batteryHealth: Double?
        let batteryCycleCount: Int?
        let batteryTemperature: Double?
        let onBatteryPower: Double?

        init(sample: HourlySample) {
            self.date = sample.hour
            self.avg = sample.avg
            self.peak = sample.peak
            self.low = sample.low
            self.count = sample.sampleCount
            self.bytesIn = sample.bytesInDelta
            self.bytesOut = sample.bytesOutDelta
            self.bytesRead = sample.bytesReadDelta
            self.bytesWritten = sample.bytesWrittenDelta
            self.avgPower = sample.avgPower
            self.swapUsed = sample.swapUsed
            self.memoryPressureLevel = sample.memoryPressureLevel
            self.thermalState = sample.thermalState
            self.swapins = sample.swapins
            self.swapouts = sample.swapouts
            self.cpuSystem = sample.cpuSystem
            self.cpuUser = sample.cpuUser
            self.cpuIdle = sample.cpuIdle
            self.cpuTemperature = sample.cpuTemperature
            self.memoryUsed = sample.memoryUsed
            self.diskFree = sample.diskFree
            self.netPeakDownload = sample.netPeakDownload
            self.netPeakUpload = sample.netPeakUpload
            self.diskPeakRead = sample.diskPeakRead
            self.diskPeakWrite = sample.diskPeakWrite
            self.gpuMemoryUsed = sample.gpuMemoryUsed
            self.gpuRenderUtil = sample.gpuRenderUtil
            self.gpuTilerUtil = sample.gpuTilerUtil
            self.batteryHealth = sample.batteryHealth
            self.batteryCycleCount = sample.batteryCycleCount
            self.batteryTemperature = sample.batteryTemperature
            self.onBatteryPower = sample.onBatteryPower
        }

        init(aggregate: DailyAggregate) {
            self.date = aggregate.date
            self.avg = aggregate.avg
            self.peak = aggregate.peak
            self.low = aggregate.low
            self.count = aggregate.sampleCount
            self.bytesIn = aggregate.bytesInDelta
            self.bytesOut = aggregate.bytesOutDelta
            self.bytesRead = aggregate.bytesReadDelta
            self.bytesWritten = aggregate.bytesWrittenDelta
            self.avgPower = aggregate.avgPower
            self.swapUsed = aggregate.swapUsed
            self.memoryPressureLevel = aggregate.memoryPressureLevel
            self.thermalState = aggregate.thermalState
            self.swapins = aggregate.swapins
            self.swapouts = aggregate.swapouts
            self.cpuSystem = aggregate.cpuSystem
            self.cpuUser = aggregate.cpuUser
            self.cpuIdle = aggregate.cpuIdle
            self.cpuTemperature = aggregate.cpuTemperature
            self.memoryUsed = aggregate.memoryUsed
            self.diskFree = aggregate.diskFree
            self.netPeakDownload = aggregate.netPeakDownload
            self.netPeakUpload = aggregate.netPeakUpload
            self.diskPeakRead = aggregate.diskPeakRead
            self.diskPeakWrite = aggregate.diskPeakWrite
            self.gpuMemoryUsed = aggregate.gpuMemoryUsed
            self.gpuRenderUtil = aggregate.gpuRenderUtil
            self.gpuTilerUtil = aggregate.gpuTilerUtil
            self.batteryHealth = aggregate.batteryHealth
            self.batteryCycleCount = aggregate.batteryCycleCount
            self.batteryTemperature = aggregate.batteryTemperature
            self.onBatteryPower = aggregate.onBatteryPower
        }

        init(pending: PendingBucket) {
            self.date = pending.hour
            self.avg = pending.avg
            self.peak = pending.peak
            self.low = pending.low
            self.count = 1
            self.bytesIn = pending.bytesIn
            self.bytesOut = pending.bytesOut
            self.bytesRead = pending.bytesRead
            self.bytesWritten = pending.bytesWritten
            self.avgPower = pending.avgPower
            self.swapUsed = pending.swapUsed
            self.memoryPressureLevel = pending.memoryPressureLevel
            self.thermalState = pending.thermalState
            self.swapins = pending.swapins
            self.swapouts = pending.swapouts
            self.cpuSystem = pending.cpuSystem
            self.cpuUser = pending.cpuUser
            self.cpuIdle = pending.cpuIdle
            self.cpuTemperature = pending.cpuTemperature
            self.memoryUsed = pending.memoryUsed
            self.diskFree = pending.diskFree
            self.netPeakDownload = pending.netPeakDownload
            self.netPeakUpload = pending.netPeakUpload
            self.diskPeakRead = pending.diskPeakRead
            self.diskPeakWrite = pending.diskPeakWrite
            self.gpuMemoryUsed = pending.gpuMemoryUsed
            self.gpuRenderUtil = pending.gpuRenderUtil
            self.gpuTilerUtil = pending.gpuTilerUtil
            self.batteryHealth = pending.batteryHealth
            self.batteryCycleCount = pending.batteryCycleCount
            self.batteryTemperature = pending.batteryTemperature
            self.onBatteryPower = pending.onBatteryPower
        }
    }

    // MARK: - Hourly Query

    private func queryHourly(kind: MonitorKind, from: Date? = nil, to: Date? = nil, context: ModelContext, pending: PendingBucket? = nil) -> StatisticsSummary {
        let kindStr = kind.rawValue
        let startDate = from ?? Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        let endDate = to ?? Date()

        let descriptor = FetchDescriptor<HourlySample>(
            predicate: #Predicate { $0.kind == kindStr && $0.hour >= startDate && $0.hour <= endDate },
            sortBy: [SortDescriptor(\.hour)]
        )

        do {
            let samples = try context.fetch(descriptor)
            var rows: [SummaryRow] = samples.map(SummaryRow.init)
            var totalIn = samples.compactMap(\.bytesInDelta).reduce(0, +)
            var totalOut = samples.compactMap(\.bytesOutDelta).reduce(0, +)
            var totalRead = samples.compactMap(\.bytesReadDelta).reduce(0, +)
            var totalWritten = samples.compactMap(\.bytesWrittenDelta).reduce(0, +)
            var powers = samples.map(\.avgPower)
            var powerCounts = samples.map(\.sampleCount)

            // 合并当前小时未落库的内存桶（若该小时已有落库样本则跳过，避免重复）
            if let pending, !samples.contains(where: { $0.hour == pending.hour }) {
                rows.append(SummaryRow(pending: pending))
                totalIn += pending.bytesIn
                totalOut += pending.bytesOut
                totalRead += pending.bytesRead
                totalWritten += pending.bytesWritten
                powers.append(pending.avgPower)
                powerCounts.append(1)
            }

            return buildSummary(kind: kind, rows: rows,
                               totalIn: totalIn, totalOut: totalOut,
                               totalRead: totalRead, totalWritten: totalWritten,
                               avgPower: weightedAvgPower(powers, counts: powerCounts))
        } catch {
            logger.error("Failed to fetch hourly samples: \(error.localizedDescription, privacy: .public)")
            return emptySummary(kind: kind)
        }
    }

    // MARK: - Daily Query

    private func queryDaily(kind: MonitorKind, days: Int? = nil, from: Date? = nil, to: Date? = nil, context: ModelContext) -> StatisticsSummary {
        let kindStr = kind.rawValue
        let calendar = Calendar.current
        let startDate = from ?? calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days ?? 7), to: Date())!)
        let endDate = to ?? Date()

        let descriptor = FetchDescriptor<DailyAggregate>(
            predicate: #Predicate { $0.kind == kindStr && $0.date >= startDate && $0.date <= endDate },
            sortBy: [SortDescriptor(\.date)]
        )

        do {
            let aggregates = try context.fetch(descriptor)
            let rows = aggregates.map(SummaryRow.init)
            return buildSummary(kind: kind, rows: rows,
                               totalIn: aggregates.compactMap(\.bytesInDelta).reduce(0, +),
                               totalOut: aggregates.compactMap(\.bytesOutDelta).reduce(0, +),
                               totalRead: aggregates.compactMap(\.bytesReadDelta).reduce(0, +),
                               totalWritten: aggregates.compactMap(\.bytesWrittenDelta).reduce(0, +),
                               avgPower: weightedAvgPower(aggregates.map(\.avgPower), counts: aggregates.map(\.sampleCount)))
        } catch {
            logger.error("Failed to fetch daily aggregates: \(error.localizedDescription, privacy: .public)")
            return emptySummary(kind: kind)
        }
    }

    // MARK: - Helpers

    private func buildSummary(kind: MonitorKind, rows: [SummaryRow],
                              totalIn: Int64, totalOut: Int64, totalRead: Int64, totalWritten: Int64,
                              avgPower: Double?) -> StatisticsSummary {
        let points = rows.map {
            StatisticsDataPoint(
                date: $0.date, avg: $0.avg, peak: $0.peak, low: $0.low,
                bytesIn: $0.bytesIn, bytesOut: $0.bytesOut,
                bytesRead: $0.bytesRead, bytesWritten: $0.bytesWritten,
                swapUsed: $0.swapUsed, memoryPressureLevel: $0.memoryPressureLevel,
                thermalState: $0.thermalState, swapins: $0.swapins, swapouts: $0.swapouts,
                cpuSystem: $0.cpuSystem, cpuUser: $0.cpuUser, cpuIdle: $0.cpuIdle,
                cpuTemperature: $0.cpuTemperature, memoryUsed: $0.memoryUsed,
                diskFree: $0.diskFree, netPeakDownload: $0.netPeakDownload,
                netPeakUpload: $0.netPeakUpload, diskPeakRead: $0.diskPeakRead,
                diskPeakWrite: $0.diskPeakWrite, gpuMemoryUsed: $0.gpuMemoryUsed,
                gpuRenderUtil: $0.gpuRenderUtil, gpuTilerUtil: $0.gpuTilerUtil,
                batteryHealth: $0.batteryHealth, batteryCycleCount: $0.batteryCycleCount,
                batteryTemperature: $0.batteryTemperature, onBatteryPower: $0.onBatteryPower
            )
        }
        let allAvgs = rows.map(\.avg).sorted()
        let median = allAvgs.isEmpty ? 0 : (allAvgs.count % 2 == 0 ? (allAvgs[allAvgs.count / 2 - 1] + allAvgs[allAvgs.count / 2]) / 2 : allAvgs[allAvgs.count / 2])
        let totalCount = rows.reduce(0) { $0 + $1.count }
        let overallAvg = totalCount > 0 ? rows.reduce(0.0) { $0 + $1.avg * Double($1.count) } / Double(totalCount) : 0
        let overallPeak = rows.map(\.peak).max() ?? 0
        let overallLow = rows.map(\.low).min() ?? 0

        // Phase 1 聚合
        let swapRows = rows.filter { $0.swapUsed != nil }
        let avgSwapUsed = !swapRows.isEmpty ? avgInt64Weighted(swapRows.map(\.swapUsed!), counts: swapRows.map(\.count)) : nil
        let peakPressure = rows.compactMap(\.memoryPressureLevel).max()
        let peakThermal = rows.compactMap(\.thermalState).max()
        // 健康评分用加权均值（排除 unknown=3），避免一次峰值永久钉死评分
        let pressureAvgRows = rows.filter { lvl in lvl.memoryPressureLevel.map { $0 < 3 } ?? false }
        let avgPressure = !pressureAvgRows.isEmpty
            ? weightedAvg(pressureAvgRows.map { Double($0.memoryPressureLevel!) }, counts: pressureAvgRows.map(\.count))
            : nil
        let thermalAvgRows = rows.filter { $0.thermalState != nil }
        let avgThermal = !thermalAvgRows.isEmpty
            ? weightedAvg(thermalAvgRows.map { Double($0.thermalState!) }, counts: thermalAvgRows.map(\.count))
            : nil
        let totalSwapins = rows.compactMap(\.swapins).reduce(0, +)
        let totalSwapouts = rows.compactMap(\.swapouts).reduce(0, +)

        // Phase 2 聚合
        let cpuRows = rows.filter { $0.cpuSystem != nil }
        let avgCpuSystem = !cpuRows.isEmpty ? weightedAvg(cpuRows.map(\.cpuSystem!), counts: cpuRows.map(\.count)) : nil
        let avgCpuUser = !cpuRows.isEmpty ? weightedAvg(cpuRows.map(\.cpuUser!), counts: cpuRows.map(\.count)) : nil
        let avgCpuIdle = !cpuRows.isEmpty ? weightedAvg(cpuRows.map(\.cpuIdle!), counts: cpuRows.map(\.count)) : nil
        let tempRows = rows.filter { $0.cpuTemperature != nil }
        let avgCpuTemp = !tempRows.isEmpty ? weightedAvg(tempRows.map(\.cpuTemperature!), counts: tempRows.map(\.count)) : nil
        let memRows = rows.filter { $0.memoryUsed != nil }
        let avgMemUsed = !memRows.isEmpty ? avgInt64Weighted(memRows.map(\.memoryUsed!), counts: memRows.map(\.count)) : nil
        let latestDiskFree = rows.compactMap(\.diskFree).last
        let peakNetDown = rows.compactMap(\.netPeakDownload).max()
        let peakNetUp = rows.compactMap(\.netPeakUpload).max()
        let peakDiskR = rows.compactMap(\.diskPeakRead).max()
        let peakDiskW = rows.compactMap(\.diskPeakWrite).max()

        // Phase 3 聚合
        let gpuMemRows = rows.filter { $0.gpuMemoryUsed != nil }
        let avgGpuMem = !gpuMemRows.isEmpty ? avgInt64Weighted(gpuMemRows.map(\.gpuMemoryUsed!), counts: gpuMemRows.map(\.count)) : nil
        let gpuUtilRows = rows.filter { $0.gpuRenderUtil != nil }
        let avgGpuRender = !gpuUtilRows.isEmpty ? weightedAvg(gpuUtilRows.map(\.gpuRenderUtil!), counts: gpuUtilRows.map(\.count)) : nil
        let avgGpuTiler = !gpuUtilRows.isEmpty ? weightedAvg(gpuUtilRows.map(\.gpuTilerUtil!), counts: gpuUtilRows.map(\.count)) : nil
        let battHealthRows = rows.filter { $0.batteryHealth != nil }
        let avgBattHealth = !battHealthRows.isEmpty ? weightedAvg(battHealthRows.map(\.batteryHealth!), counts: battHealthRows.map(\.count)) : nil
        let latestBattCycles = rows.compactMap(\.batteryCycleCount).last
        let battTempRows = rows.filter { $0.batteryTemperature != nil }
        let avgBattTemp = !battTempRows.isEmpty ? weightedAvg(battTempRows.map(\.batteryTemperature!), counts: battTempRows.map(\.count)) : nil
        let battPowerRows = rows.filter { $0.onBatteryPower != nil }
        let avgBattPower = !battPowerRows.isEmpty ? weightedAvg(battPowerRows.map(\.onBatteryPower!), counts: battPowerRows.map(\.count)) : nil

        return StatisticsSummary(
            kind: kind, avg: overallAvg, peak: overallPeak, low: overallLow, median: median,
            points: points,
            totalBytesIn: totalIn > 0 ? totalIn : nil,
            totalBytesOut: totalOut > 0 ? totalOut : nil,
            totalBytesRead: totalRead > 0 ? totalRead : nil,
            totalBytesWritten: totalWritten > 0 ? totalWritten : nil,
            avgPower: avgPower,
            avgSwapUsed: avgSwapUsed, peakMemoryPressureLevel: peakPressure,
            peakThermalState: peakThermal,
            avgMemoryPressureLevel: avgPressure, avgThermalState: avgThermal,
            totalSwapins: totalSwapins > 0 ? totalSwapins : nil,
            totalSwapouts: totalSwapouts > 0 ? totalSwapouts : nil,
            avgCpuSystem: avgCpuSystem, avgCpuUser: avgCpuUser, avgCpuIdle: avgCpuIdle,
            avgCpuTemperature: avgCpuTemp, avgMemoryUsed: avgMemUsed,
            latestDiskFree: latestDiskFree, peakNetDownload: peakNetDown,
            peakNetUpload: peakNetUp, peakDiskRead: peakDiskR, peakDiskWrite: peakDiskW,
            avgGpuMemoryUsed: avgGpuMem, avgGpuRenderUtil: avgGpuRender,
            avgGpuTilerUtil: avgGpuTiler, avgBatteryHealth: avgBattHealth,
            latestBatteryCycleCount: latestBattCycles, avgBatteryTemperature: avgBattTemp,
            avgOnBatteryPower: avgBattPower
        )
    }

    private func emptySummary(kind: MonitorKind) -> StatisticsSummary {
        StatisticsSummary(kind: kind, avg: 0, peak: 0, low: 0, median: 0, points: [],
                         totalBytesIn: nil, totalBytesOut: nil, totalBytesRead: nil, totalBytesWritten: nil, avgPower: nil,
                         avgSwapUsed: nil, peakMemoryPressureLevel: nil, peakThermalState: nil,
                         avgMemoryPressureLevel: nil, avgThermalState: nil,
                         totalSwapins: nil, totalSwapouts: nil,
                         avgCpuSystem: nil, avgCpuUser: nil, avgCpuIdle: nil, avgCpuTemperature: nil,
                         avgMemoryUsed: nil, latestDiskFree: nil, peakNetDownload: nil, peakNetUpload: nil,
                         peakDiskRead: nil, peakDiskWrite: nil,
                         avgGpuMemoryUsed: nil, avgGpuRenderUtil: nil, avgGpuTilerUtil: nil,
                         avgBatteryHealth: nil, latestBatteryCycleCount: nil, avgBatteryTemperature: nil, avgOnBatteryPower: nil)
    }

    // MARK: - Health Score

    private static let defaultWeights = HealthScoreWeights()

    /// 各维度健康度计算（与 Display/趋势线共用，避免公式分叉）
    private enum HealthCalc {
        /// CPU：低负载接近满分，70% 后加速下降（0→1.0, 70→0.85, 90→0.30, 100→0.0）
        static func cpu(_ usage: Double) -> Double {
            let u = clamp(usage, 0, 100)
            if u <= 70 { return 1.0 - (u / 70.0) * 0.15 }
            if u <= 90 { return 0.85 - ((u - 70) / 20.0) * 0.55 }
            return max(0, 0.30 - ((u - 90) / 10.0) * 0.30)
        }
        /// 内存 / GPU：线性（越高越不健康）
        static func linear(_ usage: Double) -> Double {
            clamp((100.0 - clamp(usage, 0, 100)) / 100.0, 0, 1)
        }
        /// 磁盘：剩余空间 ≥15% 满分，低于 15% 线性下降到 0（占用本身不等于不健康）
        static func disk(_ usage: Double) -> Double {
            let free = 100.0 - clamp(usage, 0, 100)
            if free >= 15 { return 1.0 }
            return max(0, free / 15.0)
        }
        /// 内存压力等级均值（0 normal,1 warning,2 critical）→ 1.0/0.5/0.0
        static func pressure(_ avgLevel: Double) -> Double {
            let v = clamp(avgLevel, 0, 2)
            if v <= 1 { return 1.0 - v * 0.5 }
            return max(0, 0.5 - (v - 1) * 0.5)
        }
        /// 热状态均值（0 nominal,1 fair,2 serious,3 critical）→ 1.0/0.75/0.5/0.0
        static func thermal(_ avgState: Double) -> Double {
            let v = clamp(avgState, 0, 3)
            if v <= 1 { return 1.0 - v * 0.25 }
            if v <= 2 { return 0.75 - (v - 1) * 0.25 }
            return max(0, 0.5 - (v - 2) * 0.5)
        }
        static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            min(max(v, lo), hi)
        }
    }

    /// 热压力硬帽：当整段窗口的平均热状态 ≥ serious（2.0）时，说明持续过热，
    /// 将评分限制在 40（软化为旧的 20，避免一次瞬时峰值把评分钉死）。
    private static let thermalCapScore: Double = 40
    private static let thermalCapThreshold: Double = 2.0

    /// Compute a health score for the given time range.
    /// - Parameter pending: 当前小时的内存桶字典，key 为 MonitorKind.rawValue。所有范围都会合并「今天」的 pending。
    func queryHealthScore(range: StatisticsTimeRange, pending: [String: PendingBucket]? = nil) -> HealthScore {
        let cpuSummary = query(kind: .cpu, range: range, pending: pending?[MonitorKind.cpu.rawValue])
        let memSummary = query(kind: .memory, range: range, pending: pending?[MonitorKind.memory.rawValue])
        let gpuSummary = query(kind: .gpu, range: range, pending: pending?[MonitorKind.gpu.rawValue])
        let diskSummary = query(kind: .storage, range: range, pending: pending?[MonitorKind.storage.rawValue])

        // 数据可用性：CPU 是每秒采样的主指标，作为整段窗口是否有数据的判据。
        let hasData = !cpuSummary.points.isEmpty || pending?[MonitorKind.cpu.rawValue] != nil
        guard hasData else {
            return HealthScore(score: 0, level: .critical, dimensions: [], thermalCapped: false,
                               timeRange: range, isDataAvailable: false, trend: [])
        }

        let weights = Self.defaultWeights

        let cpuAvail = !cpuSummary.points.isEmpty || pending?[MonitorKind.cpu.rawValue] != nil
        let gpuAvail = !gpuSummary.points.isEmpty || pending?[MonitorKind.gpu.rawValue] != nil
        let diskAvail = !diskSummary.points.isEmpty || pending?[MonitorKind.storage.rawValue] != nil

        let pressureLevel: Double? = memSummary.avgMemoryPressureLevel
        let thermalState: Double? = cpuSummary.avgThermalState

        let pressureAvail = pressureLevel != nil
        let thermalAvail = thermalState != nil

        // 各维度（名称 / 原始值文案 / 原始数值 / 健康度 / 是否可用）
        let cpuHealth = HealthCalc.cpu(cpuSummary.avg)
        let gpuHealth = HealthCalc.linear(gpuSummary.avg)
        let diskHealth = HealthCalc.disk(diskSummary.avg)
        let pressureHealth = pressureLevel.map { HealthCalc.pressure($0) }
        let thermalHealth = thermalState.map { HealthCalc.thermal($0) }

        let dims: [(name: String, rawText: String, rawValue: Double, health: Double, weight: Double, avail: Bool)] = [
            (String(localized: "health.dimension.cpu"), "\(safeIntDisplay(cpuSummary.avg))%", cpuSummary.avg, cpuHealth, weights.cpu, cpuAvail),
            (String(localized: "health.dimension.gpu"), "\(safeIntDisplay(gpuSummary.avg))%", gpuSummary.avg, gpuHealth, weights.gpu, gpuAvail),
            (String(localized: "health.dimension.disk"), "\(safeIntDisplay(diskSummary.avg))%", diskSummary.avg, diskHealth, weights.disk, diskAvail),
            (String(localized: "health.dimension.pressure"),
             pressureLevel.map { Self.pressureLabel($0) } ?? "--",
             pressureLevel ?? 0, pressureHealth ?? 0, weights.pressure, pressureAvail),
            (String(localized: "health.dimension.thermal"),
             thermalState.map { Self.thermalLabel($0) } ?? "--",
             thermalState ?? 0, thermalHealth ?? 0, weights.thermal, thermalAvail),
        ]

        // 可用维度权重重分配
        let availWeight = dims.filter(\.avail).reduce(0.0) { $0 + $1.weight }
        let scale = availWeight > 0 ? 1.0 / availWeight : 0

        let dimensions: [DimensionScore] = dims.map { d in
            DimensionScore(
                name: d.name,
                rawText: d.rawText,
                rawValue: d.rawValue,
                healthValue: d.health,
                weight: d.avail ? d.weight * scale : 0,
                level: HealthLevel(score: d.health * 100),
                isAvailable: d.avail
            )
        }

        // 加权原始分（缺失维度自动剔除并重分配）
        let rawScore = Self.scoreFrom(
            cpu: cpuAvail ? cpuSummary.avg : nil,
            gpu: gpuAvail ? gpuSummary.avg : nil,
            disk: diskAvail ? diskSummary.avg : nil,
            pressure: pressureAvail ? pressureLevel : nil,
            thermal: thermalAvail ? thermalState : nil
        ) ?? 0

        // 热压力硬帽（基于平均热状态，而非一次峰值）
        let thermalCapped = thermalState.map { $0 >= Self.thermalCapThreshold } ?? false
        let finalScore = thermalCapped ? min(rawScore, Self.thermalCapScore) : rawScore

        // 趋势：按时间桶（24h 逐小时 / 日级逐天）复算分量分
        let trend = buildTrend(cpu: cpuSummary, mem: memSummary, gpu: gpuSummary, disk: diskSummary)

        return HealthScore(
            score: finalScore,
            level: HealthLevel(score: finalScore),
            dimensions: dimensions,
            thermalCapped: thermalCapped,
            timeRange: range,
            isDataAvailable: true,
            trend: trend
        )
    }

    /// 由各维度原始值（可缺）加权计算 0-100 分，缺失维度自动剔除并重分配权重。
    private static func scoreFrom(cpu: Double?, gpu: Double?, disk: Double?,
                                  pressure: Double?, thermal: Double?) -> Double? {
        let w = HealthScoreWeights()
        var items: [(health: Double, weight: Double)] = []
        if let cpu { items.append((HealthCalc.cpu(cpu), w.cpu)) }
        if let gpu { items.append((HealthCalc.linear(gpu), w.gpu)) }
        if let disk { items.append((HealthCalc.disk(disk), w.disk)) }
        if let pressure { items.append((HealthCalc.pressure(pressure), w.pressure)) }
        if let thermal { items.append((HealthCalc.thermal(thermal), w.thermal)) }
        guard !items.isEmpty else { return nil }
        let totalW = items.reduce(0.0) { $0 + $1.weight }
        guard totalW > 0 else { return nil }
        return items.reduce(0.0) { $0 + $1.health * $1.weight } / totalW * 100
    }

    /// 按时间桶复算分量分，用于趋势线。
    private func buildTrend(cpu: StatisticsSummary, mem: StatisticsSummary, gpu: StatisticsSummary,
                            disk: StatisticsSummary) -> [HealthTrendPoint] {
        let cpuByDate = Dictionary(cpu.points.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let memByDate = Dictionary(mem.points.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let gpuByDate = Dictionary(gpu.points.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let diskByDate = Dictionary(disk.points.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        var points: [HealthTrendPoint] = []
        for date in Set(cpuByDate.keys).sorted() {
            guard let cp = cpuByDate[date] else { continue }
            let mp = memByDate[date]
            let gp = gpuByDate[date]
            let dp = diskByDate[date]
            let pressure = mp?.memoryPressureLevel.map(Double.init)
            let thermal = cp.thermalState.map(Double.init)
            guard let score = Self.scoreFrom(
                cpu: cp.avg, gpu: gp?.avg, disk: dp?.avg,
                pressure: pressure, thermal: thermal
            ) else { continue }
            points.append(HealthTrendPoint(date: date, score: score))
        }
        return points
    }

    private static func formatBytes(_ bytes: Double) -> String {
        let b = Int64(bytes)
        if b < 1024 { return "\(b) B" }
        if b < 1_048_576 { return String(format: "%.1f KB", bytes / 1024) }
        if b < 1_073_741_824 { return String(format: "%.1f MB", bytes / 1_048_576) }
        return String(format: "%.2f GB", bytes / 1_073_741_824)
    }

    private static func pressureLabel(_ avgLevel: Double) -> String {
        switch avgLevel {
        case ..<0.5: return String(localized: "event.pressure.normal")
        case ..<1.5: return String(localized: "event.pressure.warning")
        default:     return String(localized: "event.pressure.critical")
        }
    }

    private static func thermalLabel(_ avgState: Double) -> String {
        switch avgState {
        case ..<0.5: return String(localized: "event.thermal.nominal")
        case ..<1.5: return String(localized: "event.thermal.fair")
        case ..<2.5: return String(localized: "event.thermal.serious")
        default:     return String(localized: "event.thermal.critical")
        }
    }

    private func weightedAvgPower(_ values: [Double?], counts: [Int]) -> Double? {
        var sum = 0.0
        var total = 0
        for (val, count) in zip(values, counts) {
            if let v = val {
                sum += v * Double(count)
                total += count
            }
        }
        return total > 0 ? sum / Double(total) : nil
    }

    private func weightedAvg(_ values: [Double], counts: [Int]) -> Double {
        var sum = 0.0
        var total = 0
        for (val, count) in zip(values, counts) {
            sum += val * Double(count)
            total += count
        }
        return total > 0 ? sum / Double(total) : 0
    }

    private func avgInt64Weighted(_ values: [Int64], counts: [Int]) -> Int64 {
        var sum: Int64 = 0
        var total = 0
        for (val, count) in zip(values, counts) {
            sum += val * Int64(count)
            total += count
        }
        return total > 0 ? sum / Int64(total) : 0
    }
}
