import Foundation

/// 预聚合的图表时间序列：按缺口分段存储，避免 SwiftUI `body` 在交互期间反复遍历并分组。
nonisolated struct ReportChartSeries: Sendable, Equatable {
    let seriesID: String
    let segments: [[ReportTimeSeriesPoint]]
    let bucketSeconds: TimeInterval

    init(seriesID: String, segments: [[ReportTimeSeriesPoint]], bucketSeconds: TimeInterval = 60) {
        self.seriesID = seriesID
        self.segments = segments
        self.bucketSeconds = bucketSeconds
    }

    var isEmpty: Bool { segments.isEmpty || segments.allSatisfy(\.isEmpty) }

    var pointCount: Int {
        segments.reduce(0) { $0 + $1.count }
    }

    /// 同一张图使用相同的原始行数和时间粒度，缺值多少不影响降采样网格。
    func smoothed(targetMaxPoints: Int = 240, referencePointCount: Int) -> ReportChartSeries {
        guard referencePointCount > targetMaxPoints, targetMaxPoints > 0 else { return self }
        let multiplier = Int(ceil(Double(referencePointCount) / Double(targetMaxPoints)))
        let binSeconds = bucketSeconds * Double(multiplier)

        let newSegments: [[ReportTimeSeriesPoint]] = segments.compactMap { seg in
            guard let first = seg.first, let last = seg.last else { return nil }

            var result: [ReportTimeSeriesPoint] = []
            var currentBin: Int64?
            var sum = 0.0
            var count = 0
            let segID = first.segmentID

            func flushBin() {
                guard let bin = currentBin, count > 0 else { return }
                let centerEpoch = (Double(bin) + 0.5) * binSeconds
                let center = Date(timeIntervalSince1970: centerEpoch)
                let date = min(last.date, max(first.date, center))
                result.append(ReportTimeSeriesPoint(
                    id: "\(seriesID)-s-\(segID)-\(bin)",
                    date: date,
                    seriesID: seriesID,
                    segmentID: segID,
                    value: sum / Double(count)
                ))
            }

            for pt in seg {
                guard let val = pt.value else { continue }
                let bin = Int64(floor(pt.date.timeIntervalSince1970 / binSeconds))
                if bin != currentBin {
                    flushBin()
                    currentBin = bin
                    sum = val
                    count = 1
                } else {
                    sum += val
                    count += 1
                }
            }
            flushBin()
            return result.isEmpty ? nil : result
        }
        return ReportChartSeries(seriesID: seriesID, segments: newSegments, bucketSeconds: bucketSeconds)
    }

    /// 由 `ReportDataAggregator.buildTimeSeries` 产出的点数组构造分段集合。
    static func from(
        _ points: [ReportTimeSeriesPoint],
        seriesID: String,
        bucketSeconds: TimeInterval = 60
    ) -> ReportChartSeries {
        guard let first = points.first else {
            return ReportChartSeries(seriesID: seriesID, segments: [], bucketSeconds: bucketSeconds)
        }
        var segments: [[ReportTimeSeriesPoint]] = []
        var currentSegID = first.segmentID
        var current: [ReportTimeSeriesPoint] = []
        for pt in points {
            if pt.segmentID != currentSegID {
                if !current.isEmpty { segments.append(current) }
                current = [pt]
                currentSegID = pt.segmentID
            } else {
                current.append(pt)
            }
        }
        if !current.isEmpty { segments.append(current) }
        return ReportChartSeries(seriesID: seriesID, segments: segments, bucketSeconds: bucketSeconds)
    }
}

/// 趋势图背景高亮区间（用于叠加系统压力事件与跨模块跳转锚定的时间窗）。
nonisolated struct ReportChartHighlightWindow: Sendable, Equatable, Identifiable {
    enum Tone: Sendable, Equatable {
        case warning
        case critical
        case focus
    }

    let id: String
    let start: Date
    let end: Date
    let tone: Tone
    let label: String?
}

/// 所有模块的预计算图表时间序列缓存，随 `ReportActiveRangeModel` 在后台线程一次性生成。
nonisolated struct ReportChartCache: Sendable, Equatable {
    let cpuAvg: ReportChartSeries
    let cpuPeak: ReportChartSeries
    let cpuP: ReportChartSeries
    let cpuE: ReportChartSeries

    let gpuAvg: ReportChartSeries
    let gpuPeak: ReportChartSeries
    let gpuVramMB: ReportChartSeries

    let memUsedGB: ReportChartSeries
    let memCompressedGB: ReportChartSeries
    let memPressure: ReportChartSeries
    let memSwapMB: ReportChartSeries

    let netDownMBps: ReportChartSeries
    let netUpMBps: ReportChartSeries

    let diskReadMBps: ReportChartSeries
    let diskWriteMBps: ReportChartSeries

    let powerWatts: ReportChartSeries
    let batteryLevel: ReportChartSeries
    let batteryTemp: ReportChartSeries

    let cpuTemp: ReportChartSeries
    let thermalState: ReportChartSeries
    let fanRPM: ReportChartSeries

    let memUsagePct: ReportChartSeries

    static let empty = ReportChartCache(
        cpuAvg: ReportChartSeries(seriesID: "cpuAvg", segments: []),
        cpuPeak: ReportChartSeries(seriesID: "cpuPeak", segments: []),
        cpuP: ReportChartSeries(seriesID: "cpuP", segments: []),
        cpuE: ReportChartSeries(seriesID: "cpuE", segments: []),
        gpuAvg: ReportChartSeries(seriesID: "gpuAvg", segments: []),
        gpuPeak: ReportChartSeries(seriesID: "gpuPeak", segments: []),
        gpuVramMB: ReportChartSeries(seriesID: "gpuVramMB", segments: []),
        memUsedGB: ReportChartSeries(seriesID: "memUsedGB", segments: []),
        memCompressedGB: ReportChartSeries(seriesID: "memCompressedGB", segments: []),
        memPressure: ReportChartSeries(seriesID: "memPressure", segments: []),
        memSwapMB: ReportChartSeries(seriesID: "memSwapMB", segments: []),
        netDownMBps: ReportChartSeries(seriesID: "netDownMBps", segments: []),
        netUpMBps: ReportChartSeries(seriesID: "netUpMBps", segments: []),
        diskReadMBps: ReportChartSeries(seriesID: "diskReadMBps", segments: []),
        diskWriteMBps: ReportChartSeries(seriesID: "diskWriteMBps", segments: []),
        powerWatts: ReportChartSeries(seriesID: "powerWatts", segments: []),
        batteryLevel: ReportChartSeries(seriesID: "batteryLevel", segments: []),
        batteryTemp: ReportChartSeries(seriesID: "batteryTemp", segments: []),
        cpuTemp: ReportChartSeries(seriesID: "cpuTemp", segments: []),
        thermalState: ReportChartSeries(seriesID: "thermalState", segments: []),
        fanRPM: ReportChartSeries(seriesID: "fanRPM", segments: []),
        memUsagePct: ReportChartSeries(seriesID: "memUsagePct", segments: [])
    )
}

/// 单个应用跨维度的资源画像摘要（用于在展开行内统一呈现 CPU / 内存 / GPU / 磁盘 / 网络）。
nonisolated struct ReportAppProfile: Sendable, Equatable {
    let cpuText: String?
    let memoryText: String?
    let gpuText: String?
    let diskText: String?
    let networkText: String?

    var hasAny: Bool {
        cpuText != nil || memoryText != nil || gpuText != nil || diskText != nil || networkText != nil
    }
}
