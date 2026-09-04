import Testing
@testable import HagimiMonitorDirect

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

    @Test func smcReaderRespondsToSystemPowerOnDirect() {
        if let smc = SMCReader() {
            // 在真机环境执行时验证 systemPower 与 dcInputPower 不崩溃且数值合理（nil 或 > 0）
            if let power = smc.systemPower() {
                #expect(power > 0)
            }
            if let dcIn = smc.dcInputPower() {
                #expect(dcIn > 0)
            }
        }
    }

    @Test func desktopAcModuleKeepsPowerInDecoupledFromLoad() {
        let sampler = BatterySampler()
        let module = sampler.sample(previous: nil)
        #expect(module.kind == .battery)

        let powerMetric = module.metrics.first(where: { $0.name == "power" })
        let powerInMetric = module.metrics.first(where: { $0.name == "power-in" })

        if let pVal = powerMetric?.numericValue {
            #expect(pVal > 0)
        }
        if let inVal = powerInMetric?.numericValue {
            #expect(inVal > 0)
        }
        // 如果机器处于仅有负载而无输入轨遥测（如脱离适配器或无输入轨遥测的台式机），
        // 验证系统负载绝不会自动复制给 powerIn
        if powerInMetric?.numericValue == nil {
            #expect(powerInMetric?.value == "--")
        }
    }
}
