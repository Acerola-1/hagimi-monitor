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
                MonitorMetric(name: "power", value: wattString(systemPower), numericValue: systemPower),
                MonitorMetric(name: "health", value: smart.healthPercent.map(percent) ?? "--", numericValue: smart.healthPercent),
                MonitorMetric(name: "cycle-count", value: smart.cycleCount.map { "\($0)" } ?? "--", numericValue: smart.cycleCount.map(Double.init)),
                MonitorMetric(name: "temperature", value: smart.temperatureCelsius.map { "\(String(format: "%.0f", $0))°C" } ?? "--", numericValue: smart.temperatureCelsius)
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
            summary: "ac-power",
            metrics: [
                MonitorMetric(name: "type", value: "ac-power"),
                MonitorMetric(name: "status", value: "ac-power"),
                MonitorMetric(name: "adapter", value: wattString(adapterWatts, rounded: true)),
                MonitorMetric(name: "power", value: wattString(powerWatts), numericValue: powerWatts)
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

        // 兼容 macOS 26 / 27 的不同 IORegistry 布局：
        //   - macOS 26 及以前：DesignCapacity / AppleRawMaxCapacity / Temperature 等键直接
        //     挂在 AppleSmartBattery 根节点上，可通过 IORegistryEntryCreateCFProperty 取到。
        //   - macOS 27（2026/06 发布的 beta 起）：这些键被移到子节点 AppleSmartBatteryPack 的
        //     "BatteryData" 字典里，根节点对应属性返回 nil，导致温度 / 健康度读不出来。
        // 这里先收集整棵子树的 BatteryData 并集（根节点优先），再统一查询：
        // 根节点能读到时走 26 原路径；读不到时回退到合并后的 BatteryData，覆盖 27。
        // 参考 docs/stats 的 Modules/Battery/readers.swift —— Stats 在 27 下仍能正常显示，
        // 因为它的容差更大并直接读 BatteryData 字典。
        let batteryData = collectBatteryData(service)
        let lookupDouble: (String) -> Double? = { [self] key in
            doubleRegistryValue(service, key) ?? doubleValue(batteryData[key])
        }
        let lookupInt: (String) -> Int? = { [self] key in
            intRegistryValue(service, key) ?? intValue(batteryData[key])
        }

        let cycleCount = lookupInt("CycleCount")
        let designCapacity = lookupDouble("DesignCapacity")
        // 健康度口径必须与系统设置「最大容量」一致：系统用的是经 powerd 校准平滑的
        // NominalChargeCapacity；AppleRawMaxCapacity 是电池芯片的瞬时原始满充容量，
        // 随温度/近期充放波动，普遍偏低 1~3 个百分点，会导致与系统显示不一致。
        let maxCapacity = lookupDouble("NominalChargeCapacity")
            ?? lookupDouble("AppleRawMaxCapacity")
            ?? lookupDouble("MaxCapacity")
        let voltage = lookupDouble("Voltage")
        let amperage = lookupDouble("Amperage")
        let adapterWatts = adapterWatts(service)
        let systemPowerWatts = systemPowerWatts(service)
        let chargingPowerWatts = chargingPowerWatts(service)
        let telemetryChargingWatts = telemetryChargingWatts(service)
        let temperature = lookupDouble("Temperature").map { $0 / 100 }
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

        // 优先用固件直接给出的整机负载(mW):实测与 SystemPowerIn − |BatteryPower|
        // 逐位相等(固件同口径),但免去差值法两字段采样瞬间错位导致差值为负、
        // 只能返 nil 的失真;且充电/直供/电池三态下都直接有效。
        if let systemLoad = doubleValue(value["SystemLoad"]), systemLoad > 0 {
            return systemLoad / 1_000
        }

        guard let powerIn = doubleValue(value["SystemPowerIn"]), powerIn > 0 else {
            if let bp = signedDoubleValue(value["BatteryPower"]), bp != 0 {
                return abs(bp) / 1_000
            }
            return nil
        }

        let batteryPower = signedDoubleValue(value["BatteryPower"]) ?? 0

        if batteryPower == 0 {
            return powerIn / 1_000
        }

        let systemPower = powerIn - abs(batteryPower)
        if systemPower > 0 {
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

/// 递归收集 AppleSmartBattery 子树中所有 BatteryData 字典的并集。
///
/// 系统差异：
///   - macOS 26 及以前：BatteryData 主要存在于根节点 AppleSmartBattery，子节点信息有限。
///   - macOS 27 起：根节点的 BatteryData 被精简，DesignCapacity / AppleRawMaxCapacity /
///     AppleRawCurrentCapacity / Temperature / InstantAmperage 等键被搬到子节点
///     AppleSmartBatteryPack 的 BatteryData 中。
///
/// 合并策略：先序遍历，遇到先来的键不覆盖（即根节点优先）。这样 26 上等价于原行为，
/// 27 上则能用子节点的值补全根节点缺失的字段。
private func collectBatteryData(_ root: io_registry_entry_t) -> [String: Any] {
    var merged: [String: Any] = [:]

    func walk(_ entry: io_registry_entry_t) {
        if let dict = IORegistryEntryCreateCFProperty(entry, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] {
            for (key, value) in dict where merged[key] == nil {
                merged[key] = value
            }
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            walk(child)
            IOObjectRelease(child)
        }
    }

    walk(root)
    return merged
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
