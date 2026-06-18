import Foundation
import IOKit
import IOKit.ps
import OSLog

/// 读取系统功耗（来自 AppleSmartBattery IORegistry）
final class PowerSampler: MonitorSampler {
    var kind: MonitorKind { .power }

    func sample(previous: MonitorModule?) -> MonitorModule {
        let watts = readSystemPower()
        // value 保留真实瓦特用于统计；环形图等显示侧若需归一化自行处理。
        let summary = watts > 0 ? wattString(watts) : "--"

        let metrics = [
            MonitorMetric(name: "power-watts", value: String(format: "%.2f", watts))
        ]

        return MonitorModule(
            kind: .power,
            value: watts,
            summary: summary,
            metrics: metrics,
            samples: seedSamples(watts)
        )
    }

    /// 读取系统总功耗（瓦特）。无法读取（如无电池的台式机）时返回 0，
    /// 由统计层据此判定为"无功耗数据"，而非记录伪造的固定值。
    private func readSystemPower() -> Double {
        // 优先从 AppleSmartBattery 读取 InstantAmperage * Voltage
        if let watts = smartBatteryPower() {
            return watts
        }

        // Fallback: PowerTelemetryData.SystemPowerIn
        if let watts = powerTelemetryWatts() {
            return watts
        }

        return 0
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
