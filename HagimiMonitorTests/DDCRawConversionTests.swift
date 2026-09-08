import Testing
@testable import HagimiMonitorDirect

/// 转换语义:完整 UInt16 可表示(无 32767 截断),拒绝非有限值,
/// 零 max 是无效范围而非静默替换。
struct DDCRawConversionTests {
    // MARK: percent → raw

    @Test func percentToRawClampsBelowZero() {
        #expect(DDCRawConversion.ddcRaw(percent: -10, max: 100) == 0)
    }

    @Test func percentToRawClampsAbove100() {
        #expect(DDCRawConversion.ddcRaw(percent: 150, max: 100) == 100)
    }

    @Test func percentToRawWithMax255() {
        #expect(DDCRawConversion.ddcRaw(percent: 50, max: 255) == 128)
    }

    @Test func percentToRawWithMax1() {
        #expect(DDCRawConversion.ddcRaw(percent: 50, max: 1) == 1)
        #expect(DDCRawConversion.ddcRaw(percent: 0, max: 1) == 0)
    }

    /// 0/100 边界在完整 UInt16 范围下的映射。
    @Test func fullUInt16RangeBoundaries() {
        #expect(DDCRawConversion.ddcRaw(percent: 0, max: 65_535) == 0)
        #expect(DDCRawConversion.ddcRaw(percent: 100, max: 65_535) == 65_535)
        #expect(DDCRawConversion.ddcRaw(percent: 50, max: 65_535) == 32_768)
        #expect(DDCRawConversion.ddcRaw(percent: 100, max: 255) == 255)
        #expect(DDCRawConversion.ddcRaw(percent: 100, max: 100) == 100)
    }

    /// NaN/Infinity 拒绝,不产生垃圾 raw。
    @Test func nonFinitePercentRejected() {
        #expect(DDCRawConversion.ddcRaw(percent: Double.nan, max: 100) == nil)
        #expect(DDCRawConversion.ddcRaw(percent: Double.infinity, max: 100) == nil)
        #expect(DDCRawConversion.ddcRaw(percent: -Double.infinity, max: 100) == nil)
    }

    @Test func rawToPercentBasic() {
        #expect(abs(DDCRawConversion.percent(raw: 128, max: 255)! - 50.196) < 0.01)
    }

    /// 零 max 无效:返回 nil(读回应答中的零 max 表示不支持或坏帧)。
    @Test func rawToPercentWithZeroMaxReturnsNil() {
        #expect(DDCRawConversion.percent(raw: 50, max: 0) == nil)
        #expect(DDCRawConversion.isValidRange(max: 0) == false)
        #expect(DDCRawConversion.isValidRange(max: 1))
        #expect(DDCRawConversion.isValidRange(max: 65_535))
    }
}
