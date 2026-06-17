import Foundation
import SwiftData
import os.log

/// 内存桶：累加当前小时的采样值
private struct SampleBucket {
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
    private var lastCumulative: [String: (bytesIn: Int64, bytesOut: Int64, bytesRead: Int64, bytesWritten: Int64)] = [:]

    init(container: ModelContainer) {
        self.container = container
        self.currentHour = StatisticsRecorder.startOfHour(Date())
    }

    /// 从 ModelContainer 创建，默认使用共享容器
    convenience init() {
        let schema = Schema([HourlySample.self, DailyAggregate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            self.init(container: container)
        } catch {
            fatalError("Failed to create ModelContainer for statistics: \(error)")
        }
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
                                            bytesWritten: prev?.bytesWritten ?? 0)
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
                                            bytesWritten: bytesWritten)
                }
            }

            // 功耗：从 metrics 读取瓦特
            if module.kind == .power {
                if let watts = metricDouble(module, key: "power-watts") {
                    bucket.addPower(watts)
                }
            }

            buckets[kind] = bucket
        }
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
                avgPower: bucket.avgPower
            )
            context.insert(sample)
        }

        do {
            try context.save()
        } catch {
            logger.error("Failed to flush hourly samples: \(error.localizedDescription, privacy: .public)")
        }

        buckets.removeAll()
        cleanupOldSamples(context: context)
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
                    avgPower: avgOptionalDouble(samples.map(\.avgPower), counts: samples.map(\.sampleCount))
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
}
