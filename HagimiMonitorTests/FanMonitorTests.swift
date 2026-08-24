import Foundation
import Testing
@testable import HagimiMonitorDirect

// MARK: - Mock SMC Reader

/// 测试用 SMC 替身,实现 FanSMCReading 协议,可控返回风扇数据。
/// 用于 FanSampler 的集成测试:注入预设的 fanCount / allFans 返回值,
/// 验证采样逻辑(命名、状态判断、available 门控)无需真实硬件。
final class MockFanSMCReader: FanSMCReading {
    var fanCountResult: Int?
    var allFansResult: [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)]

    init(fanCount: Int?, allFans: [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)]) {
        self.fanCountResult = fanCount
        self.allFansResult = allFans
    }

    func fanCount() -> Int? { fanCountResult }

    func allFans() -> [(id: Int, currentRPM: Int, minRPM: Int, maxRPM: Int)] { allFansResult }
}

// MARK: - FanInfo.status 单元测试

struct FanStatusTests {

    // MARK: 正常状态

    @Test func normalStatusWhenRPMWithinRange() {
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .normal)
    }

    @Test func normalStatusAtLowBoundary() {
        // RPM = 1(刚过 0),maxRPM 正常 → normal
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 1, minRPM: 0, maxRPM: 6000)
        #expect(fan.status == .normal)
    }

    @Test func normalStatusJustBelowWarningThreshold() {
        // 84% maxRPM = 5040,恰好不触发 warning(>= 85%)
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 5040, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .normal)
    }

    // MARK: 警告状态

    @Test func warningStatusAtThreshold() {
        // 85% maxRPM = 5100,恰好触发 warning
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 5100, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .warning)
    }

    @Test func warningStatusNearMax() {
        // 接近但未超过 maxRPM
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 5999, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .warning)
    }

    @Test func warningStatusAtExactMax() {
        // RPM == maxRPM:不构成 fault(不大于),但 >= 85% → warning
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 6000, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .warning)
    }

    // MARK: 故障状态

    @Test func faultStatusWhenRPMIsZero() {
        // RPM = 0:停转 → fault
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 0, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .fault)
    }

    @Test func faultStatusWhenRPMExceedsMax() {
        // RPM > maxRPM:传感器异常 → fault
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 7000, minRPM: 1000, maxRPM: 6000)
        #expect(fan.status == .fault)
    }

    // MARK: 未知状态

    @Test func unknownStatusWhenMaxRPMIsZero() {
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 0, maxRPM: 0)
        #expect(fan.status == .unknown)
    }

    @Test func unknownStatusWhenMaxRPMIsNegative() {
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 0, maxRPM: -1)
        #expect(fan.status == .unknown)
    }

    // MARK: 边界优先级

    @Test func faultTakesPriorityOverUnknown() {
        // maxRPM = 0 → 通常 unknown,但 RPM = 0 时是否 fault?
        // 设计决策:maxRPM <= 0 优先返回 unknown(传感器数据不足,无法判断)
        let fan = FanInfo(id: 0, name: "Fan #0", currentRPM: 0, minRPM: 0, maxRPM: 0)
        #expect(fan.status == .unknown)
    }
}

// MARK: - FanStatus.overallStatus 聚合测试

struct FanOverallStatusTests {

    @Test func emptyFansReturnsUnknown() {
        #expect(FanInfo.overallStatus(of: []) == .unknown)
    }

    @Test func singleNormalFanReturnsNormal() {
        let fans = [FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 1000, maxRPM: 6000)]
        #expect(FanInfo.overallStatus(of: fans) == .normal)
    }

    @Test func worstStatusAcrossMultipleFans() {
        let fans = [
            FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 1000, maxRPM: 6000),  // normal
            FanInfo(id: 1, name: "Fan #1", currentRPM: 5500, minRPM: 1000, maxRPM: 6000),  // warning
        ]
        #expect(FanInfo.overallStatus(of: fans) == .warning)
    }

    @Test func faultDominatesOverWarning() {
        let fans = [
            FanInfo(id: 0, name: "Fan #0", currentRPM: 5500, minRPM: 1000, maxRPM: 6000),  // warning
            FanInfo(id: 1, name: "Fan #1", currentRPM: 0, minRPM: 1000, maxRPM: 6000),     // fault
        ]
        #expect(FanInfo.overallStatus(of: fans) == .fault)
    }

    @Test func allNormalReturnsNormal() {
        let fans = [
            FanInfo(id: 0, name: "Fan #0", currentRPM: 1200, minRPM: 1000, maxRPM: 6000),
            FanInfo(id: 1, name: "Fan #1", currentRPM: 1500, minRPM: 1000, maxRPM: 6000),
        ]
        #expect(FanInfo.overallStatus(of: fans) == .normal)
    }
}

// MARK: - FanStatus Comparable 排序测试

struct FanStatusComparableTests {

    @Test func orderingFromBestToWorst() {
        #expect(FanStatus.unknown < .normal)
        #expect(FanStatus.normal < .warning)
        #expect(FanStatus.warning < .fault)
    }

    @Test func maxReturnsWorstStatus() {
        let statuses: [FanStatus] = [.normal, .warning, .unknown, .fault]
        #expect(statuses.max() == .fault)
    }

    @Test func severityMapping() {
        #expect(FanStatus.normal.severity == .calm)
        #expect(FanStatus.unknown.severity == .calm)
        #expect(FanStatus.warning.severity == .warning)
        #expect(FanStatus.fault.severity == .critical)
    }
}

// MARK: - FanSampler 集成测试(mock 注入)

struct FanSamplerTests {

    @Test func unavailableWhenFanCountIsNil() {
        let mock = MockFanSMCReader(fanCount: nil, allFans: [])
        let sampler = FanSampler(smcReader: mock)
        #expect(sampler.available == false)
    }

    @Test func unavailableWhenFanCountIsZero() {
        let mock = MockFanSMCReader(fanCount: 0, allFans: [])
        let sampler = FanSampler(smcReader: mock)
        #expect(sampler.available == false)
    }

    @Test func availableWhenFanCountIsPositive() {
        let mock = MockFanSMCReader(fanCount: 1, allFans: [])
        let sampler = FanSampler(smcReader: mock)
        #expect(sampler.available == true)
    }

    @Test func startDoesNothingWhenUnavailable() {
        let mock = MockFanSMCReader(fanCount: nil, allFans: [])
        let sampler = FanSampler(smcReader: mock)
        sampler.start()
        // 不可用时不采样:fans 保持空
        #expect(sampler.fans.isEmpty)
        sampler.stop()
    }

    @Test func startSamplesImmediatelyWhenAvailable() {
        let mock = MockFanSMCReader(
            fanCount: 2,
            allFans: [
                (id: 0, currentRPM: 1200, minRPM: 1000, maxRPM: 6000),
                (id: 1, currentRPM: 1500, minRPM: 1000, maxRPM: 6000),
            ]
        )
        let sampler = FanSampler(smcReader: mock)
        sampler.start()
        // start() 会立即调 sample() 一次
        #expect(sampler.fans.count == 2)
        #expect(sampler.fans[0].name == "Left Fan")
        #expect(sampler.fans[1].name == "Right Fan")
        sampler.stop()
    }

    @Test func singleFanNamedByIndex() {
        let mock = MockFanSMCReader(
            fanCount: 1,
            allFans: [(id: 0, currentRPM: 1200, minRPM: 1000, maxRPM: 6000)]
        )
        let sampler = FanSampler(smcReader: mock)
        sampler.start()
        #expect(sampler.fans[0].name == "Fan #0")
        sampler.stop()
    }

    @Test func statusUpdatesAfterSampling() {
        let mock = MockFanSMCReader(
            fanCount: 1,
            allFans: [(id: 0, currentRPM: 5500, minRPM: 1000, maxRPM: 6000)]  // warning
        )
        let sampler = FanSampler(smcReader: mock)
        sampler.start()
        #expect(sampler.status == .warning)
        sampler.stop()
    }

    @Test func faultStatusWhenFanStopped() {
        let mock = MockFanSMCReader(
            fanCount: 1,
            allFans: [(id: 0, currentRPM: 0, minRPM: 1000, maxRPM: 6000)]  // fault
        )
        let sampler = FanSampler(smcReader: mock)
        sampler.start()
        #expect(sampler.status == .fault)
        sampler.stop()
    }

    @Test func noSamplingWithoutReader() {
        let sampler = FanSampler(smcReader: nil)
        #expect(sampler.available == false)
        sampler.start()
        #expect(sampler.fans.isEmpty)
        #expect(sampler.status == .unknown)
        sampler.stop()
    }
}

// MARK: - MenuBarMetricFormatter.fanRPM 格式化测试

struct FanRPMFormatterTests {

    @Test func normalValueRightAligned() {
        let result = MenuBarMetricFormatter.fanRPM(1200)
        #expect(result == "1200")
    }

    @Test func smallValueNotPadded() {
        let result = MenuBarMetricFormatter.fanRPM(800)
        #expect(result == "800")
    }

    @Test func maxValueNotCapped() {
        let result = MenuBarMetricFormatter.fanRPM(9999)
        #expect(result == "9999")
    }

    @Test func valueAbove9999Capped() {
        let result = MenuBarMetricFormatter.fanRPM(12000)
        #expect(result == "9999")
    }

    @Test func zeroValueNotPadded() {
        let result = MenuBarMetricFormatter.fanRPM(0)
        #expect(result == "0")
    }

    @Test func nilReturnsUnavailablePlaceholder() {
        let result = MenuBarMetricFormatter.fanRPM(nil)
        #expect(result == "--")
    }
}

// MARK: - userSelectableCases(hasFan:) 门控测试

struct FanSelectableCasesTests {

    @Test func fanSpeedIncludedWhenHasFanIsTrue() {
        let cases = MenuBarMetricKind.userSelectableCases(hasFan: true)
        #expect(cases.contains(.fanSpeed))
    }

    @Test func fanSpeedExcludedWhenHasFanIsFalse() {
        let cases = MenuBarMetricKind.userSelectableCases(hasFan: false)
        #expect(!cases.contains(.fanSpeed))
    }
}
