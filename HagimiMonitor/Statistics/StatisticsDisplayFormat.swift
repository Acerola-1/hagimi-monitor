import Foundation

/// 概览与详情共用的展示转换:把底层真实数值(秒、字节、比例)折成用户可读文本。
/// 只做展示,不改动统计数据本身;零值、缺失与非零短时长在这里有明确区分
/// (需求:没有有效观测显示「暂无数据」,真实非零但不足一分钟显示「不足 1 分钟」)。
enum StatisticsDisplayFormat {
    /// 时长的结构分解,便于单测分支(小时/分钟/不足一分钟),渲染另走文本模板。
    struct DurationParts: Equatable {
        let hours: Int
        let minutes: Int
        /// 真实非零但不足一分钟(渲染为「不足 1 分钟」而不是「0 分钟」)。
        let isUnderMinute: Bool

        var isZero: Bool { hours == 0 && minutes == 0 && !isUnderMinute }
    }

    static func durationParts(_ seconds: Double) -> DurationParts {
        let clamped = max(0, seconds)
        if clamped > 0, clamped < 60 {
            return DurationParts(hours: 0, minutes: 0, isUnderMinute: true)
        }
        let totalMinutes = Int((clamped / 60).rounded())
        return DurationParts(hours: totalMinutes / 60, minutes: totalMinutes % 60, isUnderMinute: false)
    }

    /// 「12 分钟」「1 小时 20 分钟」「不足 1 分钟」;0 显示「0 分钟」。
    /// 时长一律以分钟为最小单位,不出现「4800 秒」这类展示。
    static func duration(_ seconds: Double) -> String {
        let parts = durationParts(seconds)
        if parts.isUnderMinute {
            return String(localized: "overview.duration.underMinute")
        }
        if parts.hours > 0, parts.minutes > 0 {
            return String(localized: "overview.duration.hoursMinutes \(parts.hours) \(parts.minutes)")
        }
        if parts.hours > 0 {
            return String(localized: "overview.duration.hours \(parts.hours)")
        }
        return String(localized: "overview.duration.minutes \(parts.minutes)")
    }

    /// 百分比:整数不带小数位,其余保留一位(「24%」而不是「24.0%」);
    /// 调用方负责区分「暂无数据」与真实 0。
    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f%%", rounded)
        }
        return String(format: "%.1f%%", rounded)
    }

    /// 字节量:自动单位,小数位随量级收敛——10 个单位以上取整,否则保留一位
    /// (「124 GB」「1.8 GB」);总量不堆无意义的小数。
    static func bytes(_ value: Double) -> String {
        guard value > 0 else { return "0 B" }
        let units: [(threshold: Double, name: String)] = [
            (1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB"),
        ]
        for unit in units where value >= unit.threshold {
            let scaled = value / unit.threshold
            let text = scaled >= 10 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)
            return "\(text) \(unit.name)"
        }
        return String(format: "%.0f B", value)
    }

    /// 时钟时刻(事件起止、最后观测时间)。
    static func timeOfDay(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
