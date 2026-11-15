import Foundation

/// IOPS 给出的电池供电状态；电池方向由此状态确定，BatteryPower 只提供幅度。
nonisolated enum BatteryPowerSourceState: Sendable {
    case charging
    case externalPower
    case onBattery
    case unknown
}

/// IOPS 读取入口解析后的最小快照，允许测试注入接口失败与恢复帧。
nonisolated struct BatteryPowerSourceSnapshot: Sendable {
    let currentCapacity: Double?
    let maxCapacity: Double?
    let isCharging: Bool
    let isConnectedToPower: Bool
    let timeToFullChargeMinutes: Int?
    let timeToEmptyMinutes: Int?

    init(
        currentCapacity: Double? = nil,
        maxCapacity: Double? = nil,
        isCharging: Bool = false,
        isConnectedToPower: Bool = false,
        timeToFullChargeMinutes: Int? = nil,
        timeToEmptyMinutes: Int? = nil
    ) {
        self.currentCapacity = currentCapacity
        self.maxCapacity = maxCapacity
        self.isCharging = isCharging
        self.isConnectedToPower = isConnectedToPower
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
    }
}

/// 电源状态读取结果。空电源列表表示无电池机型，接口失败表示未知状态。
nonisolated enum BatteryPowerSourceReading: Sendable {
    case unavailable
    case noBattery
    case battery(BatteryPowerSourceSnapshot)
}

/// 纯函数功率结果。`watts == nil` 表示缺失；已确认的零瓦以 `0` 保留。
nonisolated struct BatteryPowerResolution: Equatable, Sendable {
    let watts: Double?
    let isEstimated: Bool

    static let missing = BatteryPowerResolution(watts: nil, isEstimated: false)
}

/// 整机负载与电池流向分别解算，两者只读取各自的原始测量。
nonisolated enum BatteryPowerResolver {
    private static let maxPlausibleWatts = 1_000.0
    private static let flowZeroToleranceWatts = 0.05

    /// `measuredSystemLoadWatts` 接收 PSTR/SystemLoad 等整机负载，PDTR 走适配器输入。
    static func systemLoad(
        state: BatteryPowerSourceState,
        measuredSystemLoadWatts: Double?,
        adapterInputWatts: Double?,
        batteryMagnitudeWatts: Double?
    ) -> BatteryPowerResolution {
        if let measured = validWatts(measuredSystemLoadWatts) {
            return BatteryPowerResolution(watts: measured, isEstimated: false)
        }

        switch state {
        case .charging:
            guard let input = validWatts(adapterInputWatts),
                  let battery = validWatts(batteryMagnitudeWatts) else {
                return .missing
            }
            // 适配器输入 = 整机负载 + 流入电池的功率。
            guard let watts = validWatts(input - battery) else { return .missing }
            return BatteryPowerResolution(watts: watts, isEstimated: true)
        case .externalPower:
            guard let input = validWatts(adapterInputWatts),
                  let battery = validWatts(batteryMagnitudeWatts) else {
                return .missing
            }
            // 电池未充电但仍在放电：负载由输入与电池共同承担。
            guard let watts = validWatts(input + battery) else { return .missing }
            return BatteryPowerResolution(watts: watts, isEstimated: true)
        case .onBattery:
            guard let battery = validWatts(batteryMagnitudeWatts) else { return .missing }
            return BatteryPowerResolution(watts: battery, isEstimated: true)
        case .unknown:
            return .missing
        }
    }

    /// 只读取原始实测负载，与 `systemLoad` 的派生结果保持隔离。
    static func batteryFlow(
        state: BatteryPowerSourceState,
        measuredSystemLoadWatts: Double?,
        adapterInputWatts: Double?,
        batteryMagnitudeWatts: Double?,
        batteryMagnitudeIsEstimated: Bool = false,
        preferMeasuredSystemLoadOnBattery: Bool = false
    ) -> BatteryPowerResolution {
        let measured = validWatts(measuredSystemLoadWatts)
        let magnitude = validWatts(batteryMagnitudeWatts)

        switch state {
        case .charging:
            guard let magnitude else { return .missing }
            return BatteryPowerResolution(watts: magnitude, isEstimated: batteryMagnitudeIsEstimated)

        case .externalPower:
            if let magnitude {
                return BatteryPowerResolution(watts: -magnitude, isEstimated: batteryMagnitudeIsEstimated)
            }
            guard let measured,
                  let input = validWatts(adapterInputWatts) else {
                return .missing
            }
            let difference = measured - input
            if difference > 1 {
                return BatteryPowerResolution(watts: -difference, isEstimated: true)
            }
            if abs(difference) <= flowZeroToleranceWatts {
                return BatteryPowerResolution(watts: 0, isEstimated: true)
            }
            return .missing

        case .onBattery:
            if preferMeasuredSystemLoadOnBattery, let measured {
                return BatteryPowerResolution(watts: -measured, isEstimated: false)
            }
            if let magnitude {
                return BatteryPowerResolution(watts: -magnitude, isEstimated: batteryMagnitudeIsEstimated)
            }
            guard let measured else { return .missing }
            return BatteryPowerResolution(watts: -measured, isEstimated: true)

        case .unknown:
            return .missing
        }
    }

    /// 仅使用明确的电池包电压与瞬时电流计算充电幅度；低于 5V 的电压视为单电芯/不明口径。
    static func packChargingPower(
        packVoltageMillivolts: Double?,
        signedInstantCurrentMilliamps: Double?,
        isCharging: Bool
    ) -> BatteryPowerResolution {
        guard isCharging,
              let voltage = packVoltageMillivolts,
              voltage.isFinite,
              (5_000...30_000).contains(voltage),
              let current = signedInstantCurrentMilliamps,
              current.isFinite,
              abs(current) <= 20_000 else {
            return .missing
        }

        let watts = abs(voltage * current / 1_000_000)
        guard let valid = validWatts(watts) else { return .missing }
        return BatteryPowerResolution(watts: valid, isEstimated: true)
    }

    /// BatteryPower 的符号随硬件/系统变化；仅保留幅度，方向留给 IOPS 状态。
    static func batteryMagnitudeFromTelemetry(milliwatts: Double?) -> BatteryPowerResolution {
        guard let milliwatts, milliwatts.isFinite,
              let watts = validWatts(abs(milliwatts) / 1_000) else {
            return .missing
        }
        return BatteryPowerResolution(watts: watts, isEstimated: false)
    }

    static func validWatts(_ value: Double?) -> Double? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= maxPlausibleWatts else {
            return nil
        }
        return value
    }
}
