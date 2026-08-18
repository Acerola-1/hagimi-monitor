import Darwin
import Foundation
import IOKit
import IOKit.ps
import OSLog

final class BatterySampler: MonitorSampler {
    var kind: MonitorKind { .battery }

    private var powerTelemetryService: io_service_t = IO_OBJECT_NULL
    private var didSearchPowerTelemetryService = false

    // 充电上限兜底探针:IORegistry 无 ChargeLimit 键的系统版本(macOS 27 实测)
    // 改读 pmset,结果缓存 60s。
    private let chargeLimitProbe = ChargeLimitProbe()

    // 健康度平滑状态:健康度真实变化以天/周为尺度,充放电时的抖动纯属测量噪声。
    // 系统设置显示的是 powerd 低通滤波后的值,这里用 EMA + 整数迟滞复刻其稳定性。
    private var smoothedHealthRatio: Double?   // 平滑后的 maxCapacity/designCapacity
    private var displayedHealthPercent: Double? // 当前对外显示的整数百分比

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

        let smart = smartBatteryInfo(isCharging: isCharging)
        let stableHealth = stabilizedHealth(smart.healthPercent)
        let adapterWatts = smart.adapterWatts ?? externalAdapterWatts()
        let chargingPower = connected
            ? (smart.telemetryChargingWatts ?? smart.chargingPowerWatts)
            : nil
        let systemPower = smart.systemPowerWatts ?? powerTelemetryWatts()

        // 功率流:适配器实际输入、电池流向(正=充电/负=放电)。
        let powerIn = connected ? smart.powerInWatts : nil
        // 电池流向的方向只由 IOPS 状态决定,幅度取 |BatteryPower|(该字段的符号
        // 约定随机型/系统版本不同,本机实测充电为正值)。插电未充电时固件常停报
        // 遥测(充电上限维持期 BatteryPower 恒 0),此时按功率守恒用
        // 「系统负载 − 适配器输入」估算放电量。
        let batteryFlow: Double? = {
            if isCharging {
                return smart.batteryMagnitudeWatts
            }
            if !connected {
                if let magnitude = smart.batteryMagnitudeWatts {
                    return -magnitude
                }
                return systemPower.map { -$0 }
            }
            if let magnitude = smart.batteryMagnitudeWatts {
                return -magnitude
            }
            guard let powerIn, let systemPower, powerIn < systemPower - 1 else { return nil }
            return -(systemPower - powerIn)
        }()

        let statusValue: String = if isCharging {
            "charging"
        } else if connected {
            // maintain:插电未充电但电池实际在放电(如充电上限维持期),与真直供区分。
            (batteryFlow ?? 0) < -0.05 ? "maintain" : "ac-power"
        } else {
            "on-battery"
        }
        // 剩余时间(分钟):充电中取充满耗时,电池供电取可用时长;-1 表示系统仍在估算。
        let timeRemaining: Int? = {
            if isCharging {
                return (description[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            }
            if !connected {
                return (description[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            }
            return nil
        }()

        // 转换损耗(W):适配器输入 − 系统负载 − |电池流向|。仅插电时可算;
        // 差值为负说明遥测失衡(典型为电池正在补差),显示"--"。
        let powerLoss: Double? = {
            guard connected, let powerIn, let systemPower else { return nil }
            let flow = batteryFlow.map(abs) ?? 0
            let loss = powerIn - systemPower - flow
            return loss >= 0 ? loss : nil
        }()

        return MonitorModule(
            kind: .battery,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "type", value: "battery"),
                MonitorMetric(name: "status", value: statusValue),
                MonitorMetric(name: "adapter", value: wattString(adapterWatts, rounded: true), numericValue: adapterWatts, unit: " W"),
                MonitorMetric(name: "charging-power", value: connected ? wattStringAllowZero(chargingPower) : "--", unit: connected ? " W" : nil),
                MonitorMetric(name: "power", value: wattString(systemPower), numericValue: systemPower, unit: " W"),
                MonitorMetric(name: "health", value: stableHealth.map(percent) ?? "--", numericValue: stableHealth, unit: "%"),
                MonitorMetric(name: "cycle-count", value: smart.cycleCount.map { "\($0)" } ?? "--", numericValue: smart.cycleCount.map(Double.init)),
                MonitorMetric(name: "temperature", value: smart.temperatureCelsius.map { "\(String(format: "%.0f", $0))°C" } ?? "--", numericValue: smart.temperatureCelsius, unit: "°C"),
                MonitorMetric(name: "voltage", value: voltageString(smart.voltageVolts), numericValue: smart.voltageVolts, unit: " V"),
                MonitorMetric(name: "current", value: currentString(smart.amperageMilliamps), numericValue: smart.amperageMilliamps.map(abs), unit: " mA"),
                // 剩余/满充容量合并为一格斜杠式展示;满充口径取电池芯片实测的
                // FullChargeCapacity(与「健康度」用的 NominalChargeCapacity 分工不同,
                // 后者负责相对设计容量的衰减叙事)。
                MonitorMetric(name: "capacity", value: capacityString(smart.remainingCapacitymAh, full: smart.fullChargeCapacitymAh), numericValue: smart.remainingCapacitymAh.map(Double.init), unit: " mAh"),
                // 功率流数据链(不进指标网格,由展开区功率流图消费)
                MonitorMetric(name: "power-in", value: wattString(powerIn), numericValue: powerIn, unit: " W"),
                MonitorMetric(name: "battery-flow", value: wattString(batteryFlow.map(abs)), numericValue: batteryFlow, unit: " W"),
                MonitorMetric(name: "time-remaining", value: timeRemaining.map { "\($0)" } ?? "--", numericValue: timeRemaining.map(Double.init)),
                // 展开区明细网格新增项:转换损耗/充电限制/低电量模式。
                // charge-limit 为尽力读取(IORegistry 无该键的机型显示"--");
                // low-power-mode 存 on/off 原值,由视图层 localizedMetricValue 本地化。
                MonitorMetric(name: "power-loss", value: wattString(powerLoss), numericValue: powerLoss, unit: " W"),
                MonitorMetric(name: "charge-limit", value: smart.chargeLimit.map { "\($0)%" } ?? "--", numericValue: smart.chargeLimit.map(Double.init), unit: "%"),
                MonitorMetric(name: "low-power-mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")
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
                MonitorMetric(name: "adapter", value: wattString(adapterWatts, rounded: true), numericValue: adapterWatts, unit: " W"),
                MonitorMetric(name: "power", value: wattString(powerWatts), numericValue: powerWatts, unit: " W")
            ],
            samples: seedSamples(100)
        )
    }

    /// 健康度稳定化:EMA 平滑消除瞬时噪声 + 整数迟滞防止边界横跳。
    ///
    /// 系统设置的「最大容量」是 powerd 校准平滑后的结果,IOKit 只能读到电池芯片的
    /// 瞬时原始容量(NominalChargeCapacity/AppleRawMaxCapacity),随温度、内阻、近期
    /// 充放电波动 ±1~2%。真实健康度以天/周为尺度衰减,所以充放电时的抖动全是噪声。
    ///
    /// 两道处理:
    ///   1. EMA(α=0.05):对底层比值做低通,新样本仅占 5%,需连续多次同向偏移才移动。
    ///   2. 整数迟滞(0.6%):平滑值距当前显示整数超过 0.6 个百分点才翻页,避免 88/89 横跳。
    private func stabilizedHealth(_ raw: Double?) -> Double? {
        guard let raw else { return displayedHealthPercent }

        let ratio = raw / 100
        let alpha = 0.05
        if let previous = smoothedHealthRatio {
            smoothedHealthRatio = previous + alpha * (ratio - previous)
        } else {
            smoothedHealthRatio = ratio // 首次采样直接采纳,避免冷启动缓慢爬升
        }
        let smoothedPercent = (smoothedHealthRatio ?? ratio) * 100

        guard let displayed = displayedHealthPercent else {
            let rounded = smoothedPercent.rounded()
            displayedHealthPercent = rounded
            return rounded
        }
        // 迟滞:仅当平滑值越过 显示值±0.6 才更新整数,否则维持不变
        if abs(smoothedPercent - displayed) >= 0.6 {
            displayedHealthPercent = smoothedPercent.rounded()
        }
        return displayedHealthPercent
    }

    private func smartBatteryInfo(isCharging: Bool) -> SmartBatteryInfo {
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
        let chargingPowerWatts = chargingPowerWatts(service, isCharging: isCharging)
        let telemetryChargingWatts = telemetryChargingWatts(service, isCharging: isCharging)
        let powerInWatts = powerInWatts(service)
        let batteryMagnitudeWatts = batteryMagnitudeWatts(service)
        // 充电限制(%):macOS 26.4+ 支持 80/85/90/95/100 五档自选,优化电池充电
        // 也可能随时暂停充电。优先读 IORegistry 的 ChargeLimit 键;键缺失的
        // 系统版本(macOS 27 实测)回退 pmset 探针。
        let chargeLimit = lookupInt("ChargeLimit") ?? chargeLimitProbe.limit()
        let temperature = lookupDouble("Temperature").map { $0 / 100 }
        // 容量(mAh):RemainingCapacity 为当前剩余,FullChargeCapacity 为电池芯片
        // 实测满充值,两者在 macOS 26/27 的 BatteryData 合并后均可读。
        let remainingCapacity = lookupDouble("RemainingCapacity").map { Int($0) }
        let fullChargeCapacity = lookupDouble("FullChargeCapacity").map { Int($0) }
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
            telemetryChargingWatts: telemetryChargingWatts,
            powerInWatts: powerInWatts,
            batteryMagnitudeWatts: batteryMagnitudeWatts,
            chargeLimit: chargeLimit,
            voltageVolts: voltage.map { $0 / 1_000 },
            amperageMilliamps: amperage,
            remainingCapacitymAh: remainingCapacity,
            fullChargeCapacitymAh: fullChargeCapacity
        )
    }

    /// 电池端电压(V):IORegistry Voltage 为 mV。
    private func voltageString(_ volts: Double?) -> String {
        volts.map { String(format: "%.2f V", $0) } ?? "--"
    }

    /// 电池电流(mA):Amperage 的符号约定随机型/系统版本不一致,
    /// 展示一律取绝对值,方向信息由充电状态承担。
    private func currentString(_ milliamps: Double?) -> String {
        milliamps.map { "\(Int(abs($0).rounded())) mA" } ?? "--"
    }

    /// 剩余/满充容量合并展示:两者齐备时「剩余 / 满充 mAh」,
    /// 满充缺失时只展剩余,全缺显示 "--"。
    private func capacityString(_ remaining: Int?, full: Int?) -> String {
        guard let remaining else { return "--" }
        return full.map { "\(remaining) / \($0) mAh" } ?? "\(remaining) mAh"
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

    private func chargingPowerWatts(_ service: io_service_t, isCharging: Bool) -> Double? {
        // 优先用 PowerTelemetryData.BatteryPower（电池包级别，准确）。
        // 注意符号约定因机型/系统而异：实测本机充电时 BatteryPower 为正值
        // （= SystemPowerIn − SystemLoad，流入电池的功率），不能单凭符号判方向。
        // BatteryPower 的符号在不同硬件 / macOS 版本上并不一致，
        // 因此用 IOPS 的充电状态判断方向，只把绝对值当作充电功率。
        if let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
           let watts = interpretedChargingPowerWatts(
               batteryPowerMilliwatts: signedDoubleValue(value["BatteryPower"]),
               isCharging: isCharging
           ) {
            return watts
        }
        // Fallback: ChargerData 的 ChargingCurrent * ChargingVoltage
        // 注意 ChargingVoltage 是单节电芯电压，结果会偏低
        guard isCharging,
              let value = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let current = doubleValue(value["ChargingCurrent"]),
              let voltage = doubleValue(value["ChargingVoltage"]) else {
            return nil
        }
        return nonZeroWatts(current * voltage / 1_000_000)
    }

    private func telemetryChargingWatts(_ service: io_service_t, isCharging: Bool) -> Double? {
        // 同 chargingPowerWatts：取 BatteryPower 绝对值作充电功率，兼容正/负符号约定。
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return interpretedChargingPowerWatts(
            batteryPowerMilliwatts: signedDoubleValue(value["BatteryPower"]),
            isCharging: isCharging
        )
    }

    /// 适配器实际输入功率(W):PowerTelemetryData.SystemPowerIn,仅插电时有意义。
    private func powerInWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let powerIn = doubleValue(value["SystemPowerIn"]), powerIn > 0 else {
            return nil
        }
        return powerIn / 1_000
    }

    /// 电池流向功率幅度(W,恒非负):|PowerTelemetryData.BatteryPower|。
    /// 方向由采样主流程依据 IOPS 状态赋予,这里只给大小。
    private func batteryMagnitudeWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let bp = signedDoubleValue(value["BatteryPower"]), bp != 0 else {
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
    var powerInWatts: Double?
    var batteryMagnitudeWatts: Double?
    var chargeLimit: Int?
    var voltageVolts: Double?
    var amperageMilliamps: Double?
    var remainingCapacitymAh: Int?
    var fullChargeCapacitymAh: Int?
}
