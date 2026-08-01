import Testing
@testable import HagimiMonitor

struct BatterySamplerTests {
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
