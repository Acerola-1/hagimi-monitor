import Foundation
import SwiftData

// MARK: - System Event Types

/// 系统事件类型枚举
enum SystemEventType: String, Codable, CaseIterable {
    // CPU 事件
    case cpuSustainedHigh
    case cpuSpike

    // GPU 事件
    case gpuSustainedHigh

    // 内存事件
    case memoryPressureUpgrade
    case memoryPressureDowngrade
    case swapUsageSpike

    // 热压力事件
    case thermalUpgrade
    case thermalDowngrade

    // 电池事件
    case batteryOverheat
    case batteryHealthLow
    case powerSourceChange

    // 磁盘事件
    case diskSpaceLow
    case diskIOSpike

    // 网络事件
    case networkSpike

    var title: String {
        switch self {
        case .cpuSustainedHigh: String(localized: "event.cpu-sustained-high")
        case .cpuSpike: String(localized: "event.cpu-spike")
        case .gpuSustainedHigh: String(localized: "event.gpu-sustained-high")
        case .memoryPressureUpgrade: String(localized: "event.memory-pressure-upgrade")
        case .memoryPressureDowngrade: String(localized: "event.memory-pressure-downgrade")
        case .swapUsageSpike: String(localized: "event.swap-usage-spike")
        case .thermalUpgrade: String(localized: "event.thermal-upgrade")
        case .thermalDowngrade: String(localized: "event.thermal-downgrade")
        case .batteryOverheat: String(localized: "event.battery-overheat")
        case .batteryHealthLow: String(localized: "event.battery-health-low")
        case .powerSourceChange: String(localized: "event.power-source-change")
        case .diskSpaceLow: String(localized: "event.disk-space-low")
        case .diskIOSpike: String(localized: "event.disk-io-spike")
        case .networkSpike: String(localized: "event.network-spike")
        }
    }
}

/// 系统事件严重度
enum EventSeverity: Int16, CaseIterable {
    case info = 0
    case warning = 1
    case critical = 2

    var title: String {
        switch self {
        case .info: String(localized: "event.severity.info")
        case .warning: String(localized: "event.severity.warning")
        case .critical: String(localized: "event.severity.critical")
        }
    }

    /// 保留天数（nil = 永久保留）
    var retentionDays: Int? {
        switch self {
        case .info: return 30
        case .warning: return 90
        case .critical: return nil
        }
    }
}

// MARK: - System Event Model

/// 系统事件记录
@Model
final class SystemEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var eventType: String
    var severity: Int16
    var title: String
    var detail: String
    var topProcesses: String?
    var value: Double?
    var previousValue: Double?
    var duration: Double?

    init(id: UUID = UUID(), timestamp: Date, eventType: String, severity: Int16,
         title: String, detail: String, topProcesses: String? = nil,
         value: Double? = nil, previousValue: Double? = nil, duration: Double? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.severity = severity
        self.title = title
        self.detail = detail
        self.topProcesses = topProcesses
        self.value = value
        self.previousValue = previousValue
        self.duration = duration
    }
}

// MARK: - Statistics Data Models

/// 小时级采样数据（保留最近 24 小时）
@Model
final class HourlySample {
    var hour: Date
    var kind: String
    var avg: Double
    var peak: Double
    var low: Double
    var sampleCount: Int
    var bytesInDelta: Int64?
    var bytesOutDelta: Int64?
    var bytesReadDelta: Int64?
    var bytesWrittenDelta: Int64?
    var avgPower: Double?

    // Phase 1: 高优先级字段
    var swapUsed: Int64?
    var memoryPressureLevel: Int16?
    var thermalState: Int16?
    var swapins: Int64?
    var swapouts: Int64?

    // Phase 2: 中优先级字段
    var cpuSystem: Double?
    var cpuUser: Double?
    var cpuIdle: Double?
    var cpuTemperature: Double?
    var memoryUsed: Int64?
    var diskFree: Int64?
    var netPeakDownload: Int64?
    var netPeakUpload: Int64?
    var diskPeakRead: Int64?
    var diskPeakWrite: Int64?

    // Phase 3: 低优先级字段
    var gpuMemoryUsed: Int64?
    var gpuRenderUtil: Double?
    var gpuTilerUtil: Double?
    var batteryHealth: Double?
    var batteryCycleCount: Int?
    var batteryTemperature: Double?
    var onBatteryPower: Double?

    init(hour: Date, kind: String, avg: Double, peak: Double, low: Double,
         sampleCount: Int, bytesInDelta: Int64? = nil, bytesOutDelta: Int64? = nil,
         bytesReadDelta: Int64? = nil, bytesWrittenDelta: Int64? = nil,
         avgPower: Double? = nil,
         swapUsed: Int64? = nil, memoryPressureLevel: Int16? = nil,
         thermalState: Int16? = nil, swapins: Int64? = nil, swapouts: Int64? = nil,
         cpuSystem: Double? = nil, cpuUser: Double? = nil, cpuIdle: Double? = nil,
         cpuTemperature: Double? = nil, memoryUsed: Int64? = nil, diskFree: Int64? = nil,
         netPeakDownload: Int64? = nil, netPeakUpload: Int64? = nil,
         diskPeakRead: Int64? = nil, diskPeakWrite: Int64? = nil,
         gpuMemoryUsed: Int64? = nil, gpuRenderUtil: Double? = nil, gpuTilerUtil: Double? = nil,
         batteryHealth: Double? = nil, batteryCycleCount: Int? = nil,
         batteryTemperature: Double? = nil, onBatteryPower: Double? = nil) {
        self.hour = hour
        self.kind = kind
        self.avg = avg
        self.peak = peak
        self.low = low
        self.sampleCount = sampleCount
        self.bytesInDelta = bytesInDelta
        self.bytesOutDelta = bytesOutDelta
        self.bytesReadDelta = bytesReadDelta
        self.bytesWrittenDelta = bytesWrittenDelta
        self.avgPower = avgPower
        self.swapUsed = swapUsed
        self.memoryPressureLevel = memoryPressureLevel
        self.thermalState = thermalState
        self.swapins = swapins
        self.swapouts = swapouts
        self.cpuSystem = cpuSystem
        self.cpuUser = cpuUser
        self.cpuIdle = cpuIdle
        self.cpuTemperature = cpuTemperature
        self.memoryUsed = memoryUsed
        self.diskFree = diskFree
        self.netPeakDownload = netPeakDownload
        self.netPeakUpload = netPeakUpload
        self.diskPeakRead = diskPeakRead
        self.diskPeakWrite = diskPeakWrite
        self.gpuMemoryUsed = gpuMemoryUsed
        self.gpuRenderUtil = gpuRenderUtil
        self.gpuTilerUtil = gpuTilerUtil
        self.batteryHealth = batteryHealth
        self.batteryCycleCount = batteryCycleCount
        self.batteryTemperature = batteryTemperature
        self.onBatteryPower = onBatteryPower
    }
}

/// 天级聚合数据（永久保留）
@Model
final class DailyAggregate {
    var date: Date
    var kind: String
    var avg: Double
    var peak: Double
    var low: Double
    var sampleCount: Int
    var bytesInDelta: Int64?
    var bytesOutDelta: Int64?
    var bytesReadDelta: Int64?
    var bytesWrittenDelta: Int64?
    var avgPower: Double?

    // Phase 1: 高优先级字段
    var swapUsed: Int64?
    var memoryPressureLevel: Int16?
    var thermalState: Int16?
    var swapins: Int64?
    var swapouts: Int64?

    // Phase 2: 中优先级字段
    var cpuSystem: Double?
    var cpuUser: Double?
    var cpuIdle: Double?
    var cpuTemperature: Double?
    var memoryUsed: Int64?
    var diskFree: Int64?
    var netPeakDownload: Int64?
    var netPeakUpload: Int64?
    var diskPeakRead: Int64?
    var diskPeakWrite: Int64?

    // Phase 3: 低优先级字段
    var gpuMemoryUsed: Int64?
    var gpuRenderUtil: Double?
    var gpuTilerUtil: Double?
    var batteryHealth: Double?
    var batteryCycleCount: Int?
    var batteryTemperature: Double?
    var onBatteryPower: Double?

    init(date: Date, kind: String, avg: Double, peak: Double, low: Double,
         sampleCount: Int, bytesInDelta: Int64? = nil, bytesOutDelta: Int64? = nil,
         bytesReadDelta: Int64? = nil, bytesWrittenDelta: Int64? = nil,
         avgPower: Double? = nil,
         swapUsed: Int64? = nil, memoryPressureLevel: Int16? = nil,
         thermalState: Int16? = nil, swapins: Int64? = nil, swapouts: Int64? = nil,
         cpuSystem: Double? = nil, cpuUser: Double? = nil, cpuIdle: Double? = nil,
         cpuTemperature: Double? = nil, memoryUsed: Int64? = nil, diskFree: Int64? = nil,
         netPeakDownload: Int64? = nil, netPeakUpload: Int64? = nil,
         diskPeakRead: Int64? = nil, diskPeakWrite: Int64? = nil,
         gpuMemoryUsed: Int64? = nil, gpuRenderUtil: Double? = nil, gpuTilerUtil: Double? = nil,
         batteryHealth: Double? = nil, batteryCycleCount: Int? = nil,
         batteryTemperature: Double? = nil, onBatteryPower: Double? = nil) {
        self.date = date
        self.kind = kind
        self.avg = avg
        self.peak = peak
        self.low = low
        self.sampleCount = sampleCount
        self.bytesInDelta = bytesInDelta
        self.bytesOutDelta = bytesOutDelta
        self.bytesReadDelta = bytesReadDelta
        self.bytesWrittenDelta = bytesWrittenDelta
        self.avgPower = avgPower
        self.swapUsed = swapUsed
        self.memoryPressureLevel = memoryPressureLevel
        self.thermalState = thermalState
        self.swapins = swapins
        self.swapouts = swapouts
        self.cpuSystem = cpuSystem
        self.cpuUser = cpuUser
        self.cpuIdle = cpuIdle
        self.cpuTemperature = cpuTemperature
        self.memoryUsed = memoryUsed
        self.diskFree = diskFree
        self.netPeakDownload = netPeakDownload
        self.netPeakUpload = netPeakUpload
        self.diskPeakRead = diskPeakRead
        self.diskPeakWrite = diskPeakWrite
        self.gpuMemoryUsed = gpuMemoryUsed
        self.gpuRenderUtil = gpuRenderUtil
        self.gpuTilerUtil = gpuTilerUtil
        self.batteryHealth = batteryHealth
        self.batteryCycleCount = batteryCycleCount
        self.batteryTemperature = batteryTemperature
        self.onBatteryPower = onBatteryPower
    }
}
