import Testing

@testable import HagimiMonitorDirect

/// GPU 时钟态驻留的纯计算覆盖。限频与功耗上限在空闲机器上无法自然触发，
/// 这两条路径只能靠这里钉住；归一化与档位解析则是线上数值正确性的前提。
struct GPUClockStateMathTests {
    // MARK: - 归一化

    @Test func normalizationConvertsTicksToIntervalShare() {
        let result = GPUClockStateMath.normalized([(name: "OFF", ticks: 1), (name: "P3", ticks: 3)])
        #expect(result.count == 2)
        #expect(result[0].name == "OFF")
        #expect(abs(result[0].percent - 25) < 0.0001)
        #expect(abs(result[1].percent - 75) < 0.0001)
    }

    @Test func normalizationOfEmptyIntervalIsAllZero() {
        let result = GPUClockStateMath.normalized([(name: "OFF", ticks: 0), (name: "P3", ticks: 0)])
        #expect(result.allSatisfy { $0.percent == 0 })
    }

    @Test func normalizationClampsNegativeTicks() {
        // 驱动异常返回负 tick 时按 0 计，不得污染区间总量。
        let result = GPUClockStateMath.normalized([(name: "OFF", ticks: 10), (name: "P3", ticks: -5)])
        #expect(abs(result[0].percent - 100) < 0.0001)
        #expect(result[1].percent == 0)
    }

    // MARK: - 主导时钟态

    @Test func dominantStateSkipsOffAndPicksLargestResidency() {
        let states: [(name: String, ticks: Int64)] = [("OFF", 4), ("P3", 12), ("P4", 4)]
        let dominant = GPUClockStateMath.dominantState(states)
        #expect(dominant?.name == "P3")
        #expect(abs((dominant?.percent ?? 0) - 60) < 0.0001)
    }

    @Test func dominantStateIsNilWhenOnlyOff() {
        #expect(GPUClockStateMath.dominantState([(name: "OFF", ticks: 100)]) == nil)
    }

    @Test func dominantStateIsNilWhenTheOnlyStateHasZeroResidency() {
        // 时钟态本身存在（P3）但区间内没有驻留，不算有数据。
        #expect(GPUClockStateMath.dominantState([(name: "OFF", ticks: 5), (name: "P3", ticks: 0)]) == nil)
    }

    // MARK: - 热限频

    @Test func throttlePercentSumsStatesOutsideNoPrefix() {
        let states: [(name: String, ticks: Int64)] = [("NO_CLTM", 90), ("P8", 5), ("P10", 5)]
        #expect(abs(GPUClockStateMath.throttlePercent(states) - 10) < 0.0001)
    }

    @Test func throttlePercentIsZeroWhenOnlyNoCltm() {
        #expect(GPUClockStateMath.throttlePercent([(name: "NO_CLTM", ticks: 100)]) == 0)
    }

    // MARK: - 功耗上限

    @Test func bandValueAcceptsSingleAndRangeNames() {
        #expect(GPUClockStateMath.bandValue("100%") == 100)
        #expect(GPUClockStateMath.bandValue("75%") == 75)
        // 驱动给的是区间档，取中点；抠数字会得到 09 / 1019 这类垃圾值。
        #expect(GPUClockStateMath.bandValue("0-9%") == 4.5)
        #expect(GPUClockStateMath.bandValue("10-19%") == 14.5)
        #expect(GPUClockStateMath.bandValue("70-79%") == 74.5)
        #expect(GPUClockStateMath.bandValue("OFF") == nil)
    }

    @Test func powerCapWeightsBandsByResidency() {
        let states: [(name: String, ticks: Int64)] = [("100%", 50), ("50-59%", 50)]
        // 100 与 54.5 各占一半 → 77.25
        let cap = GPUClockStateMath.powerCapPercent(states)
        #expect(abs((cap ?? 0) - 77.25) < 0.0001)
    }

    @Test func powerCapIgnoresUnparseableStatesAndIsNilIfNoneParse() {
        let mixed = GPUClockStateMath.powerCapPercent([("100%", 50), ("OFF", 50)])
        #expect(mixed == 100)
        #expect(GPUClockStateMath.powerCapPercent([("OFF", 10), ("UNKNOWN", 10)]) == nil)
    }
}
