import Foundation
import IOKit
import IOKit.ps
import OSLog

/// 读取系统功耗（来自 AppleSmartBattery IORegistry）
final class PowerSampler: MonitorSampler {
    var kind: MonitorKind { .power }

    func sample(previous: MonitorModule?) -> MonitorModule {
        let watts = readSystemPower()
        let value = min(100, watts)
        let summary = wattString(watts)

        let metrics = [
            MonitorMetric(name: "power-watts", value: wattString(watts))
        ]

        return MonitorModule(
            kind: .power,
            value: value,
            summary: summary,
            metrics: metrics,
            samples: seedSamples(value)
        )
    }

    /// 读取系统总功耗（瓦特）
    private func readSystemPower() -> Double {
        // 优先从 AppleSmartBattery 读取 InstantAmperage * Voltage
        if let watts = smartBatteryPower() {
            return watts
        }

        // Fallback: PowerTelemetryData.SystemPowerIn
        if let watts = powerTelemetryWatts() {
            return watts
        }

        // 无法读取时返回基准值
        return 3.0
    }

    /// 从 AppleSmartBattery 读取瞬时功耗
    private func smartBatteryPower() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let amperage = IORegistryEntryCreateCFProperty(service, "InstantAmperage" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber,
              let voltage = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else {
            return nil
        }

        // amperage 单位 mA，voltage 单位 mV
        let watts = abs(amperage.doubleValue) * voltage.doubleValue / 1_000_000
        return nonZeroWatts(watts)
    }

    /// 从 PowerTelemetryData 读取系统功耗
    private func powerTelemetryWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        guard let data = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }

        if let powerIn = doubleValue(data["SystemPowerIn"]), powerIn > 0 {
            return powerIn / 1_000
        }

        if let bp = signedDoubleValue(data["BatteryPower"]), bp != 0 {
            return abs(bp) / 1_000
        }

        return nil
    }
}
