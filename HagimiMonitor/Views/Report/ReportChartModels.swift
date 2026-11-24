import Foundation

/// 预聚合的图表时间序列：按缺口分段存储，避免 SwiftUI `body` 在交互期间反复遍历并分组。
nonisolated struct ReportChartSeries: Sendable, Equatable {
    let seriesID: String
    let segments: [[ReportTimeSeriesPoint]]

    var isEmpty: Bool { segments.isEmpty || segments.allSatisfy(\.isEmpty) }

    var pointCount: Int {
        segments.reduce(0) { $0 + $1.count }
    }

    /// 按已有分段构造平滑降采样序列，既消除分钟高频锯齿，又保留睡眠缺口与原始时间顺序。
    func smoothed(targetMaxPoints: Int = 240) -> ReportChartSeries {
        let total = pointCount
        guard total > targetMaxPoints, targetMaxPoints > 0 else { return self }
        let bucketSize = max(2, Int(ceil(Double(total) / Double(targetMaxPoints))))

        let newSegments: [[ReportTimeSeriesPoint]] = segments.compactMap { seg in
            guard !seg.isEmpty else { return nil }
            if seg.count <= 2 { return seg }
            var result: [ReportTimeSeriesPoint] = []
            var idx = 0
            while idx < seg.count {
                let end = min(idx + bucketSize, seg.count)
                let slice = seg[idx..<end]
                let valid = slice.compactMap(\.value)
                if !valid.isEmpty {
                    let avg = valid.reduce(0, +) / Double(valid.count)
                    let mid = slice[slice.startIndex + (slice.count / 2)]
                    result.append(ReportTimeSeriesPoint(
                        id: "\(mid.id)-s",
                        date: mid.date,
                        seriesID: seriesID,
                        segmentID: mid.segmentID,
                        value: avg
                    ))
                }
                idx = end
            }
            return result.isEmpty ? nil : result
        }
        return ReportChartSeries(seriesID: seriesID, segments: newSegments)
    }

    /// 由 `ReportDataAggregator.buildTimeSeries` 产出的点数组构造分段集合。
    static func from(_ points: [ReportTimeSeriesPoint], seriesID: String) -> ReportChartSeries {
        guard !points.isEmpty else { return ReportChartSeries(seriesID: seriesID, segments: []) }
        var segments: [[ReportTimeSeriesPoint]] = []
        var currentSegID = points[0].segmentID
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
        return ReportChartSeries(seriesID: seriesID, segments: segments)
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
