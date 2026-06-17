import Foundation
import SwiftData

/// 小时级采样数据（保留最近 24 小时）
@Model
final class HourlySample {
    var hour: Date
    var kind: String
    var avg: Double
    var peak: Double
    var low: Double
    var sampleCount: Int
    var bytesInDelta: Int64?
    var bytesOutDelta: Int64?
    var bytesReadDelta: Int64?
    var bytesWrittenDelta: Int64?
    var avgPower: Double?

    init(hour: Date, kind: String, avg: Double, peak: Double, low: Double,
         sampleCount: Int, bytesInDelta: Int64? = nil, bytesOutDelta: Int64? = nil,
         bytesReadDelta: Int64? = nil, bytesWrittenDelta: Int64? = nil,
         avgPower: Double? = nil) {
        self.hour = hour
        self.kind = kind
        self.avg = avg
        self.peak = peak
        self.low = low
        self.sampleCount = sampleCount
        self.bytesInDelta = bytesInDelta
        self.bytesOutDelta = bytesOutDelta
        self.bytesReadDelta = bytesReadDelta
        self.bytesWrittenDelta = bytesWrittenDelta
        self.avgPower = avgPower
    }
}

/// 天级聚合数据（永久保留）
@Model
final class DailyAggregate {
    var date: Date
    var kind: String
    var avg: Double
    var peak: Double
    var low: Double
    var sampleCount: Int
    var bytesInDelta: Int64?
    var bytesOutDelta: Int64?
    var bytesReadDelta: Int64?
    var bytesWrittenDelta: Int64?
    var avgPower: Double?

    init(date: Date, kind: String, avg: Double, peak: Double, low: Double,
         sampleCount: Int, bytesInDelta: Int64? = nil, bytesOutDelta: Int64? = nil,
         bytesReadDelta: Int64? = nil, bytesWrittenDelta: Int64? = nil,
         avgPower: Double? = nil) {
        self.date = date
        self.kind = kind
        self.avg = avg
        self.peak = peak
        self.low = low
        self.sampleCount = sampleCount
        self.bytesInDelta = bytesInDelta
        self.bytesOutDelta = bytesOutDelta
        self.bytesReadDelta = bytesReadDelta
        self.bytesWrittenDelta = bytesWrittenDelta
        self.avgPower = avgPower
    }
}
