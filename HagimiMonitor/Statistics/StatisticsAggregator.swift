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
}

/// 按时间范围查询聚合数据
@MainActor
final class StatisticsAggregator {
    private let container: ModelContainer
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "hagimi", category: "StatisticsAggregator")

    init(container: ModelContainer) {
        self.container = container
    }

    /// 查询指定模块在指定时间范围内的统计数据
    func query(kind: MonitorKind, range: StatisticsTimeRange) -> StatisticsSummary {
        let context = ModelContext(container)

        switch range {
        case .last24Hours:
            return queryHourly(kind: kind, context: context)
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

    // MARK: - Hourly Query

    private func queryHourly(kind: MonitorKind, from: Date? = nil, to: Date? = nil, context: ModelContext) -> StatisticsSummary {
        let kindStr = kind.rawValue
        let startDate = from ?? Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        let endDate = to ?? Date()

        let descriptor = FetchDescriptor<HourlySample>(
            predicate: #Predicate { $0.kind == kindStr && $0.hour >= startDate && $0.hour <= endDate },
            sortBy: [SortDescriptor(\.hour)]
        )

        do {
            let samples = try context.fetch(descriptor)
            return buildSummary(kind: kind, samples: samples.map { ($0.hour, $0.avg, $0.peak, $0.low, $0.sampleCount) },
                               totalIn: samples.compactMap(\.bytesInDelta).reduce(0, +),
                               totalOut: samples.compactMap(\.bytesOutDelta).reduce(0, +),
                               totalRead: samples.compactMap(\.bytesReadDelta).reduce(0, +),
                               totalWritten: samples.compactMap(\.bytesWrittenDelta).reduce(0, +),
                               avgPower: weightedAvgPower(samples.map(\.avgPower), counts: samples.map(\.sampleCount)))
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
            return buildSummary(kind: kind, samples: aggregates.map { ($0.date, $0.avg, $0.peak, $0.low, $0.sampleCount) },
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

    private func buildSummary(kind: MonitorKind, samples: [(date: Date, avg: Double, peak: Double, low: Double, count: Int)],
                              totalIn: Int64, totalOut: Int64, totalRead: Int64, totalWritten: Int64,
                              avgPower: Double?) -> StatisticsSummary {
        let points = samples.map { StatisticsDataPoint(date: $0.date, avg: $0.avg, peak: $0.peak, low: $0.low) }
        let allAvgs = samples.map(\.avg).sorted()
        let median = allAvgs.isEmpty ? 0 : (allAvgs.count % 2 == 0 ? (allAvgs[allAvgs.count / 2 - 1] + allAvgs[allAvgs.count / 2]) / 2 : allAvgs[allAvgs.count / 2])
        let overallAvg = samples.isEmpty ? 0 : samples.reduce(0.0) { $0 + $1.avg * Double($1.count) } / Double(samples.reduce(0) { $0 + $1.count })
        let overallPeak = samples.map(\.peak).max() ?? 0
        let overallLow = samples.map(\.low).min() ?? 0

        return StatisticsSummary(
            kind: kind, avg: overallAvg, peak: overallPeak, low: overallLow, median: median,
            points: points,
            totalBytesIn: totalIn > 0 ? totalIn : nil,
            totalBytesOut: totalOut > 0 ? totalOut : nil,
            totalBytesRead: totalRead > 0 ? totalRead : nil,
            totalBytesWritten: totalWritten > 0 ? totalWritten : nil,
            avgPower: avgPower
        )
    }

    private func emptySummary(kind: MonitorKind) -> StatisticsSummary {
        StatisticsSummary(kind: kind, avg: 0, peak: 0, low: 0, median: 0, points: [],
                         totalBytesIn: nil, totalBytesOut: nil, totalBytesRead: nil, totalBytesWritten: nil, avgPower: nil)
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
}
