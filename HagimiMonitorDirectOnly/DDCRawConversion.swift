import Foundation

enum DDCRawConversion {
    /// 将百分比（0...100）转换为 DDC 16-bit 原始值。
    static func ddcRaw(percent: Double, max: UInt16) -> UInt16 {
        let safeMax = sanitize(max: max)
        let clamped = min(100, Swift.max(0, percent))
        let scaled = clamped / 100.0 * Double(safeMax)
        return UInt16(scaled.rounded())
    }

    /// 将 DDC 原始值转换为百分比。
    static func percent(raw: UInt16, max: UInt16) -> Double {
        guard max > 0 else { return 0 }
        let value = Double(raw) / Double(max) * 100.0
        return min(100, Swift.max(0, value))
    }

    /// 防止异常 max 导致溢出或除零。
    static func sanitize(max: UInt16) -> UInt16 {
        if max == 0 { return 1 }
        if max > 32_767 { return 32_767 }
        return max
    }
}
