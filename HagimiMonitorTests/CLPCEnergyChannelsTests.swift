import Foundation
import Testing
@testable import HagimiMonitorDirect

struct CLPCEnergyChannelsTests {
    @Test func m3DescriptorsUseTheVerifiedDriverAndNanojouleReports() throws {
        let driverID: UInt64 = 0x1_0000_0428
        let channels = CLPCEnergyChannels.descriptors(osMajor: 27,
            driverBundle: "com.apple.driver.AppleT8122CLPC", driverID: driverID)
        #expect(channels.count == 2)
        for (channel, (expectedID, expectedName)) in zip(channels, [
            (UInt64(0x0000_0010_54b5_1c99), "CPU Energy"),
            (UInt64(0x0000_0018_960a_fe2f), "ANE")
        ]) {
            #expect((channel["DriverID"] as? NSNumber)?.uint64Value == driverID)
            let legend = try #require(channel["LegendChannel"] as? [Any])
            #expect((legend[0] as? NSNumber)?.uint64Value == expectedID)
            #expect((legend[1] as? NSNumber)?.uint64Value == 0x0000_0001_0002_0001)
            #expect(legend[2] as? String == expectedName)
            let info = try #require(channel["IOReportChannelInfo"] as? [String: NSNumber])
            let unit = try #require(info["IOReportChannelUnit"]?.uint64Value)
            #expect(IOReportPowerSampler.energyJoulesPerCount(unit: unit) == 1e-9)
        }
    }

    @Test(arguments: [
        (26, "com.apple.driver.AppleT8122CLPC"),
        (28, "com.apple.driver.AppleT8122CLPC"),
        (27, "com.apple.driver.AppleT6030CLPC"),
        (27, "unknown")
    ]) func unverifiedSystemsAndDriversDoNotUseM3Reports(osMajor: Int, bundle: String) {
        #expect(CLPCEnergyChannels.descriptors(osMajor: osMajor, driverBundle: bundle, driverID: 1).isEmpty)
    }

    @Test func displayZeroPolicyIsLimitedToM3OnMacOS27() {
        #expect(CLPCEnergyChannels.displayZeroIsUnavailable(osMajor: 27, cpuBrand: "Apple M3"))
        #expect(!CLPCEnergyChannels.displayZeroIsUnavailable(osMajor: 26, cpuBrand: "Apple M3"))
        #expect(!CLPCEnergyChannels.displayZeroIsUnavailable(osMajor: 27, cpuBrand: "Apple M3 Pro"))
        #expect(!CLPCEnergyChannels.displayZeroIsUnavailable(osMajor: 27, cpuBrand: "Apple M4"))
        #expect(!CLPCEnergyChannels.displayZeroIsUnavailable(osMajor: 27, cpuBrand: nil))
    }

    @Test func nanojoulesAreDividedByTheActualElapsedTime() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: 1_000_000_000, scale: 1e-9, uptime: 100, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 4_000_000_000, scale: 1e-9, uptime: 100.5, maxRate: 1_000) == 6)
    }

    @Test func trustedIdleANECanReturnToZeroAfterLoad() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: 10, scale: 1e-9, uptime: 0, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 10, scale: 1e-9, uptime: 1, maxRate: 1_000) == 0)
        #expect(rate.sample(value: 1_000_000_010, scale: 1e-9, uptime: 2, maxRate: 1_000) == 1)
        #expect(rate.sample(value: 1_000_000_010, scale: 1e-9, uptime: 3, maxRate: 1_000) == 0)
    }

    @Test func frozenLegacyAndDisplayCountersRemainUnavailable() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: 0, scale: 1e-6, uptime: 0, maxRate: 1_000, zeroDeltaIsUnavailable: true) == nil)
        #expect(rate.sample(value: 0, scale: 1e-6, uptime: 1, maxRate: 1_000, zeroDeltaIsUnavailable: true) == nil)
        #expect(rate.sample(value: 1_000_000, scale: 1e-6, uptime: 2, maxRate: 1_000, zeroDeltaIsUnavailable: true) == 1)
    }

    @Test func missingSampleClearsTheBaseline() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: 100, scale: 1e-3, uptime: 0, maxRate: 1_000) == nil)
        #expect(rate.sample(value: nil, scale: 1e-3, uptime: 1, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 50_000, scale: 1e-3, uptime: 2, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 51_000, scale: 1e-3, uptime: 3, maxRate: 1_000) == 1)
    }

    @Test func resetAndSleepRecoveryRebuildTheBaseline() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: 100, scale: 1, uptime: 0, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 10, scale: 1, uptime: 1, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 11, scale: 1, uptime: 2, maxRate: 1_000) == 1)
        #expect(rate.sample(value: 5_000, scale: 1, uptime: 33, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 5_001, scale: 1, uptime: 34, maxRate: 1_000) == 1)
    }

    @Test func invalidCountersIntervalsAndUnitsDoNotProduceSpikes() {
        var rate = IOReportCounterRate()
        #expect(rate.sample(value: -1, scale: 1, uptime: 0, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 10, scale: .nan, uptime: 1, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 10, scale: 1, uptime: .infinity, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 10, scale: 1, uptime: 2, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 11, scale: 1, uptime: 2, maxRate: 1_000) == nil)
        #expect(rate.sample(value: Int64.max, scale: 1, uptime: 3, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 100, scale: 1e-3, uptime: 4, maxRate: 1_000) == nil)
        #expect(rate.sample(value: 1_100, scale: 1e-3, uptime: 5, maxRate: 1_000) == 1)
    }
}
