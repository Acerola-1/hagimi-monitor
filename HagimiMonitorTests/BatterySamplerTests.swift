import Testing
import Foundation
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

    @Test func systemLoadAndBatteryFlowResolveIndependently() {
        let pureBatteryLoad = BatteryPowerResolver.systemLoad(
            state: .onBattery,
            measuredSystemLoadWatts: 10,
            adapterInputWatts: nil,
            batteryMagnitudeWatts: 6
        )
        let pureBatteryFlow = BatteryPowerResolver.batteryFlow(
            state: .onBattery,
            measuredSystemLoadWatts: 10,
            adapterInputWatts: nil,
            batteryMagnitudeWatts: 6,
            preferMeasuredSystemLoadOnBattery: true
        )
        #expect(pureBatteryLoad.watts == 10)
        #expect(!pureBatteryLoad.isEstimated)
        #expect(pureBatteryFlow.watts == -10)
        #expect(BatteryPowerResolver.systemLoad(
            state: .onBattery,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: nil,
            batteryMagnitudeWatts: 6
        ).watts == 6)

        // 电池方向由 IOPS 状态决定，BatteryPower 原始符号只提供幅度。
        for encodedBatteryPower in [6_000.0, -6_000.0] {
            let magnitude = BatteryPowerResolver.batteryMagnitudeFromTelemetry(milliwatts: encodedBatteryPower)
            let flow = BatteryPowerResolver.batteryFlow(
                state: .onBattery,
                measuredSystemLoadWatts: nil,
                adapterInputWatts: nil,
                batteryMagnitudeWatts: magnitude.watts
            )
            #expect(magnitude.watts == 6)
            #expect(!magnitude.isEstimated)
            #expect(flow.watts == -6)
            #expect(BatteryPowerResolver.batteryFlow(
                state: .charging,
                measuredSystemLoadWatts: nil,
                adapterInputWatts: nil,
                batteryMagnitudeWatts: magnitude.watts
            ).watts == 6)
        }

        let dischargingLoad = BatteryPowerResolver.systemLoad(
            state: .externalPower,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        )
        let dischargingFlow = BatteryPowerResolver.batteryFlow(
            state: .externalPower,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        )
        #expect(dischargingLoad.watts == 55)
        #expect(dischargingLoad.isEstimated)
        #expect(dischargingFlow.watts == -10)

        let chargingLoad = BatteryPowerResolver.systemLoad(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        )
        let chargingFlow = BatteryPowerResolver.batteryFlow(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        )
        #expect(chargingLoad.watts == 35)
        #expect(chargingFlow.watts == 10)
    }

    @Test func resolverPreservesKnownZeroAndRejectsMissingOrInvalidInputs() {
        #expect(BatteryPowerResolver.batteryMagnitudeFromTelemetry(milliwatts: 0).watts == 0)
        #expect(BatteryPowerResolver.batteryMagnitudeFromTelemetry(milliwatts: nil).watts == nil)
        let knownZeroLoad = BatteryPowerResolver.systemLoad(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 0
        )
        let knownZeroFlow = BatteryPowerResolver.batteryFlow(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: nil,
            batteryMagnitudeWatts: 0
        )
        #expect(knownZeroLoad.watts == 45)
        #expect(knownZeroFlow.watts == 0)
        #expect(BatteryPowerResolver.systemLoad(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: nil
        ).watts == nil)
        #expect(BatteryPowerResolver.batteryFlow(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: nil,
            batteryMagnitudeWatts: nil
        ).watts == nil)
        #expect(BatteryPowerResolver.systemLoad(
            state: .charging,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: .infinity
        ).watts == nil)
        #expect(BatteryPowerResolver.systemLoad(
            state: .charging,
            measuredSystemLoadWatts: -1,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        ).watts == 35)
        #expect(BatteryPowerResolver.systemLoad(
            state: .unknown,
            measuredSystemLoadWatts: nil,
            adapterInputWatts: 45,
            batteryMagnitudeWatts: 10
        ).watts == nil)
    }

    @Test func chargingPowerFallbackRequiresValidPackVoltageAndInstantCurrent() {
        let charge = BatteryPowerResolver.packChargingPower(
            packVoltageMillivolts: 12_000,
            signedInstantCurrentMilliamps: -1_000,
            isCharging: true
        )
        #expect(charge.watts == 12)
        #expect(charge.isEstimated)
        #expect(BatteryPowerResolver.packChargingPower(
            packVoltageMillivolts: 12_000,
            signedInstantCurrentMilliamps: 0,
            isCharging: true
        ).watts == 0)
        #expect(BatteryPowerResolver.packChargingPower(
            packVoltageMillivolts: 4_200,
            signedInstantCurrentMilliamps: 1_000,
            isCharging: true
        ).watts == nil)
        #expect(BatteryPowerResolver.packChargingPower(
            packVoltageMillivolts: 12_000,
            signedInstantCurrentMilliamps: nil,
            isCharging: true
        ).watts == nil)
        #expect(BatteryPowerResolver.packChargingPower(
            packVoltageMillivolts: 12_000,
            signedInstantCurrentMilliamps: 1_000,
            isCharging: false
        ).watts == nil)
    }

    @Test func iopsFailureDropsCachedBatteryReadingsAndRecovers() {
        let snapshot = BatteryPowerSourceSnapshot(
            currentCapacity: 45,
            maxCapacity: 100,
            isCharging: false,
            isConnectedToPower: false,
            timeToEmptyMinutes: 120
        )
        let reads = BatteryPowerSourceSequence([.battery(snapshot), .unavailable, .battery(
            BatteryPowerSourceSnapshot(
                currentCapacity: 75,
                maxCapacity: 100,
                isCharging: false,
                isConnectedToPower: false,
                timeToEmptyMinutes: 90
            )
        )])
        let componentPower = IOReportPowerSample(
            displayWatts: 4,
            cpuWatts: 5,
            gpuWatts: 6,
            aneWatts: 7
        )
        let sampler = BatterySampler(
            healthProbe: BatteryHealthProbe(),
            powerSourceReader: { reads.next() },
            componentPowerReader: { componentPower }
        )

        let valid = sampler.sample(previous: nil, power: componentPower)
        let unavailable = sampler.sample(previous: valid, power: componentPower)
        let recovered = sampler.sample(previous: unavailable, power: componentPower)

        #expect(valid.isPlaceholder == false)
        #expect(unavailable.isPlaceholder)
        #expect(unavailable.value == 0)
        #expect(unavailable.summary == "--")
        #expect(unavailable.samples.isEmpty)
        #expect(unavailable.metrics.map(\.name).sorted() == [
            "ane-power", "cpu-power", "display-power", "gpu-power", "status", "type"
        ])
        #expect(unavailable.metrics.first(where: { $0.name == "type" })?.value == "battery-unavailable")
        #expect(unavailable.metrics.first(where: { $0.name == "status" })?.value == "unknown")
        #expect(unavailable.metrics.first(where: { $0.name == "display-power" })?.numericValue == 4)
        #expect(unavailable.metrics.first(where: { $0.name == "cpu-power" })?.numericValue == 5)
        #expect(unavailable.metrics.first(where: { $0.name == "gpu-power" })?.numericValue == 6)
        #expect(unavailable.metrics.first(where: { $0.name == "ane-power" })?.numericValue == 7)
        #expect(unavailable.processEnergy == nil)
        #expect(recovered.isPlaceholder == false)
        #expect(recovered.summary == "75%")
        #expect(recovered.samples == seedSamples(75))
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
        // IOPS 瞬断帧返回缺失态模块(无 power/power-in 指标),本机读数断言不适用。
        guard !module.isPlaceholder else { return }

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

    @Test func hardwarePowerMetricsPresentOnBatteryModel() {
        let sampler = BatterySampler()
        let module = sampler.sample(previous: nil)

        // 仅当硬件为带电池机型（非纯台式机）时验证电池深度度量
        if module.metrics.first(where: { $0.name == "type" })?.value == "battery" {
            let cycleMetric = module.metrics.first(where: { $0.name == "cycle-count" })
            #expect(cycleMetric != nil)
            if let cycles = cycleMetric?.numericValue {
                #expect(cycles >= 0)
                #expect(cycleMetric?.value == "\(Int(cycles))")
            }

            let cellBalanceMetric = module.metrics.first(where: { $0.name == "cell-balance" })
            #expect(cellBalanceMetric != nil)
            if let balanceVal = cellBalanceMetric?.numericValue {
                #expect(balanceVal >= 0)
                #expect(cellBalanceMetric?.value.hasPrefix("Δ") == true)
            }

            let reasonMetric = module.metrics.first(where: { $0.name == "not-charging-reason" })
            #expect(reasonMetric != nil)
            let allowedMetric = module.metrics.first(where: { $0.name == "charging-allowed" })
            #expect(allowedMetric != nil)

            if module.metrics.first(where: { $0.name == "status" })?.value != "on-battery" {
                let contract = module.metrics.first(where: { $0.name == "pd-contract" })?.value
                #expect(contract != nil && contract != "")
            }
        }
    }

    @Test func cycleCountStringFormatting() {
        let sampler = BatterySampler()
        #expect(sampler.cycleCountString(130, design: 1000) == "130")
        #expect(sampler.cycleCountString(130, design: nil) == "130")
        #expect(sampler.cycleCountString(130, design: 0) == "130")
        #expect(sampler.cycleCountString(nil, design: 1000) == "--")
    }

    @Test func cellBalanceMetricCalculationAndRatings() {
        let sampler = BatterySampler()

        // 极差 <= 10: 极佳
        let exc = sampler.cellBalanceMetric([4205, 4204, 4204])
        #expect(exc != nil)
        #expect(exc?.delta == 1)
        #expect(exc?.text.contains("Δ1 mV") == true)

        // 极差 11...30: 良好
        let good = sampler.cellBalanceMetric([4225, 4200])
        #expect(good?.delta == 25)
        #expect(good?.text.contains("Δ25 mV") == true)

        // 极差 31...60: 一般
        let fair = sampler.cellBalanceMetric([4250, 4205])
        #expect(fair?.delta == 45)
        #expect(fair?.text.contains("Δ45 mV") == true)

        // 极差 > 60: 失衡
        let unb = sampler.cellBalanceMetric([4300, 4200])
        #expect(unb?.delta == 100)
        #expect(unb?.text.contains("Δ100 mV") == true)

        // 边界: 电芯数不足 2 个返回 nil
        #expect(sampler.cellBalanceMetric([]) == nil)
        #expect(sampler.cellBalanceMetric([4200]) == nil)
    }

    @Test func pdContractParsingFromUsbHvcMenu() {
        let sampler = BatterySampler()

        let details: [String: Any] = [
            "UsbHvcHvcIndex": 1,
            "UsbHvcMenu": [
                ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 3000],
                ["Index": 1, "MaxVoltage": 20000, "MaxCurrent": 3250]
            ],
            "Watts": 65
        ]

        let contract = sampler.parsePDContract(details)
        #expect(contract == "20V/3.25A/65W")
    }

    @Test func pdContractFallbackToAdapterVoltageAndCurrent() {
        let sampler = BatterySampler()

        let details: [String: Any] = [
            "AdapterVoltage": 5000,
            "Current": 1000,
            "Watts": 5
        ]

        let contract = sampler.parsePDContract(details)
        #expect(contract == "5V/1A/5W")
    }
}

private final class BatteryPowerSourceSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [BatteryPowerSourceReading]

    init(_ readings: [BatteryPowerSourceReading]) {
        self.readings = readings
    }

    func next() -> BatteryPowerSourceReading {
        lock.lock()
        defer { lock.unlock() }
        guard !readings.isEmpty else { return .unavailable }
        return readings.removeFirst()
    }
}
