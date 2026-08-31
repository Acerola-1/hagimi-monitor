import Testing
@testable import HagimiMonitorDirect

struct BatterySamplerTests {
    @Test func signedBatteryCurrentDecodesUInt64TwosComplement() {
        let encoded = UInt64(bitPattern: -1_200)

        #expect(signedDoubleValue(encoded) == -1_200)
        #expect(signedDoubleValue(NSNumber(value: encoded)) == -1_200)
    }

    @Test func ioReportEnergyUnitsUsePerChannelExponent() {
        let cpuUnit: UInt64 = 0x0300007c00000000
        let gpuUnit: UInt64 = 0x0300007600000000

        #expect(IOReportPowerSampler.energyJoulesPerCount(unit: cpuUnit) == 1e-3)
        #expect(IOReportPowerSampler.energyJoulesPerCount(unit: gpuUnit) == 1e-9)
        #expect(IOReportPowerSampler.energyJoulesPerCount(unit: 0) == nil)
    }

    @Test func chargingPowerAcceptsPositiveTelemetryOnM4() {
        let watts = interpretedChargingPowerWatts(
            batteryPowerMilliwatts: 24_898,
            isCharging: true
        )

        #expect(watts.map { abs($0 - 24.898) < 0.000_001 } == true)
    }

    @Test func chargingPowerKeepsSupportingNegativeTelemetry() {
        let watts = interpretedChargingPowerWatts(
            batteryPowerMilliwatts: -24_898,
            isCharging: true
        )

        #expect(watts.map { abs($0 - 24.898) < 0.000_001 } == true)
    }

    @Test func chargingPowerIgnoresTelemetryWhenNotCharging() {
        #expect(interpretedChargingPowerWatts(batteryPowerMilliwatts: 24_898, isCharging: false) == nil)
        #expect(interpretedChargingPowerWatts(batteryPowerMilliwatts: -24_898, isCharging: false) == nil)
    }

    @Test func chargingPowerTreatsZeroAsUnavailable() {
        #expect(interpretedChargingPowerWatts(batteryPowerMilliwatts: 0, isCharging: true) == nil)
    }
}
