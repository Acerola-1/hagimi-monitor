import Testing
@testable import HagimiMonitorDirect

struct DDCRawConversionTests {
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

    @Test func rawToPercentBasic() {
        #expect(abs(DDCRawConversion.percent(raw: 128, max: 255) - 50.196) < 0.01)
    }

    @Test func rawToPercentWithZeroMaxReturnsZero() {
        #expect(DDCRawConversion.percent(raw: 50, max: 0) == 0)
    }

    @Test func sanitizeMaxClampsExtreme() {
        #expect(DDCRawConversion.sanitize(max: 0) == 1)
        #expect(DDCRawConversion.sanitize(max: 65535) == 32767)
        #expect(DDCRawConversion.sanitize(max: 100) == 100)
    }
}
