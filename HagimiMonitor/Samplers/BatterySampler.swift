import Darwin
import Foundation
import IOKit
import IOKit.ps
import OSLog

final class BatterySampler: MonitorSampler {
    var kind: MonitorKind { .battery }

    private var powerTelemetryService: io_service_t = IO_OBJECT_NULL
    private var didSearchPowerTelemetryService = false

    deinit {
        if powerTelemetryService != IO_OBJECT_NULL {
            IOObjectRelease(powerTelemetryService)
        }
    }

    func sample(previous: MonitorModule?) -> MonitorModule {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            AppLogger.sampler.error("BatterySampler failed to read power source info")
            return externalPowerModule()
        }

        let current = doubleValue(description[kIOPSCurrentCapacityKey]) ?? 0
        let maxCapacity = doubleValue(description[kIOPSMaxCapacityKey]) ?? 100
        let percentage = maxCapacity > 0 ? min(100, max(0, current / maxCapacity * 100)) : 0
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let connected = sourceState == kIOPSACPowerValue

        let smart = smartBatteryInfo()
        let adapterWatts = smart.adapterWatts ?? externalAdapterWatts()
        let chargingPower = connected
            ? (smart.telemetryChargingWatts ?? smart.chargingPowerWatts)
            : nil
        let systemPower = smart.systemPowerWatts ?? powerTelemetryWatts()

        return MonitorModule(
            kind: .battery,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "type", value: "battery"),
                MonitorMetric(name: "status", value: isCharging ? "charging" : (connected ? "ac-power" : "on-battery")),
                MonitorMetric(name: "adapter", value: wattString(adapterWatts, rounded: true)),
                MonitorMetric(name: "charging-power", value: connected ? wattStringAllowZero(chargingPower) : "--"),
                MonitorMetric(name: "power", value: wattString(systemPower)),
                MonitorMetric(name: "health", value: smart.healthPercent.map(percent) ?? "--"),
                MonitorMetric(name: "cycle-count", value: smart.cycleCount.map { "\($0)" } ?? "--"),
                MonitorMetric(name: "temperature", value: smart.temperatureCelsius.map { "\(String(format: "%.0f", $0))°C" } ?? "--")
            ],
            samples: seedSamples(percentage)
        )
    }

    private func externalPowerModule() -> MonitorModule {
        let adapterWatts = externalAdapterWatts()
        let powerWatts = powerTelemetryWatts()
        return MonitorModule(
            kind: .battery,
            value: 100,
            summary: batteryStateTitle("ac-power"),
            metrics: [
                MonitorMetric(name: "type", value: "ac-power"),
                MonitorMetric(name: "status", value: "ac-power"),
                MonitorMetric(name: "adapter", value: wattString(adapterWatts, rounded: true)),
                MonitorMetric(name: "power", value: wattString(powerWatts))
            ],
            samples: seedSamples(100)
        )
    }

    private func smartBatteryInfo() -> SmartBatteryInfo {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            return SmartBatteryInfo()
        }
        defer { IOObjectRelease(service) }

        let cycleCount = intRegistryValue(service, "CycleCount")
        let designCapacity = doubleRegistryValue(service, "DesignCapacity")
        let maxCapacity = doubleRegistryValue(service, "AppleRawMaxCapacity")
            ?? doubleRegistryValue(service, "MaxCapacity")
        let voltage = doubleRegistryValue(service, "Voltage")
        let amperage = doubleRegistryValue(service, "Amperage")
        let adapterWatts = adapterWatts(service)
        let systemPowerWatts = systemPowerWatts(service)
        let chargingPowerWatts = chargingPowerWatts(service)
        let telemetryChargingWatts = telemetryChargingWatts(service)
        let temperature = doubleRegistryValue(service, "Temperature").map { $0 / 100 }
        let health = if let maxCapacity, let designCapacity, designCapacity > 0 {
            min(100, max(0, maxCapacity / designCapacity * 100))
        } else {
            nil as Double?
        }
        let batteryWatts = if let voltage, let amperage {
            nonZeroWatts(abs(voltage * amperage / 1_000_000))
        } else {
            nil as Double?
        }

        return SmartBatteryInfo(
            cycleCount: cycleCount,
            healthPercent: health,
            batteryPowerWatts: batteryWatts,
            adapterWatts: adapterWatts,
            systemPowerWatts: systemPowerWatts,
            chargingPowerWatts: chargingPowerWatts,
            temperatureCelsius: temperature,
            telemetryChargingWatts: telemetryChargingWatts
        )
    }

    private func adapterWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return doubleValue(value["Watts"])
    }

    private func externalAdapterWatts() -> Double? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return doubleValue(details[kIOPSPowerAdapterWattsKey])
    }

    private func chargingPowerWatts(_ service: io_service_t) -> Double? {
        // 优先用 PowerTelemetryData.BatteryPower（电池包级别，准确）
        if let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
           let bp = signedDoubleValue(value["BatteryPower"]), bp < 0 {
            return abs(bp) / 1_000
        }
        // Fallback: ChargerData 的 ChargingCurrent * ChargingVoltage
        // 注意 ChargingVoltage 是单节电芯电压，结果会偏低
        guard let value = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let current = doubleValue(value["ChargingCurrent"]),
              let voltage = doubleValue(value["ChargingVoltage"]) else {
            return nil
        }
        return nonZeroWatts(current * voltage / 1_000_000)
    }

    private func telemetryChargingWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let bp = signedDoubleValue(value["BatteryPower"]), bp < 0 else {
            return nil
        }
        return abs(bp) / 1_000
    }

    private func powerTelemetryWatts() -> Double? {
        if powerTelemetryService == IO_OBJECT_NULL, !didSearchPowerTelemetryService {
            powerTelemetryService = serviceWithProperty("PowerTelemetryData")
            didSearchPowerTelemetryService = true
        }
        guard powerTelemetryService != IO_OBJECT_NULL else {
            return nil
        }
        return systemPowerWatts(powerTelemetryService)
    }

    private func systemPowerWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let powerIn = doubleValue(value["SystemPowerIn"]), powerIn > 0 else {
            // 电池供电：用 BatteryPower
            if let bp = signedDoubleValue(value["BatteryPower"]), bp != 0 {
                return abs(bp) / 1_000
            }
            return nil
        }

        let batteryPower = signedDoubleValue(value["BatteryPower"]) ?? 0

        if batteryPower == 0 {
            // 未充电：SystemPowerIn 就是系统功耗
            return powerIn / 1_000
        }

        let systemPower = powerIn - abs(batteryPower)
        if systemPower > 0 {
            // 充电时：系统功耗 = 适配器输入 - 充电功率
            return systemPower / 1_000
        }

        // 遥测瞬时不同步导致差值为负，返回 nil 而非跳到完整 powerIn
        return nil
    }

    private func serviceWithProperty(_ key: String) -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOService"), &iterator) == KERN_SUCCESS else {
            return IO_OBJECT_NULL
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else {
                return IO_OBJECT_NULL
            }

            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
                value.release()
                return service
            }

            IOObjectRelease(service)
        }
    }

    private func intRegistryValue(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return intValue(value)
    }

    private func doubleRegistryValue(_ service: io_service_t, _ key: String) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return doubleValue(value)
    }
}

private func batteryStateTitle(_ id: String) -> String {
    let key = "battery-state.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

private struct SmartBatteryInfo {
    var cycleCount: Int?
    var healthPercent: Double?
    var batteryPowerWatts: Double?
    var adapterWatts: Double?
    var systemPowerWatts: Double?
    var chargingPowerWatts: Double?
    var temperatureCelsius: Double?
    var telemetryChargingWatts: Double?
}
