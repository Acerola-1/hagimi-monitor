import Foundation
import SwiftUI

// MARK: - 时间与粒度

/// 报表时间范围预设
nonisolated enum ReportTimeRange: Sendable, Hashable {
    case today
    case week
    case month
    case year
    case custom(from: Date, to: Date)

    var label: String {
        switch self {
        case .today: return String(localized: "stats.r.rToday")
        case .week: return String(localized: "stats.r.rWeek")
        case .month: return String(localized: "stats.r.rMonth")
        case .year: return String(localized: "stats.r.rYear")
        case .custom: return String(localized: "stats.r.selectRange")
        }
    }

    /// 计算起止时间（开区间 [from, to)）
    func bounds(now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date) {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .week:
            let from = now.addingTimeInterval(-7 * 86400)
            return (from, now)
        case .month:
            let from = now.addingTimeInterval(-30 * 86400)
            return (from, now)
        case .year:
            let from = now.addingTimeInterval(-365 * 86400)
            return (from, now)
        case .custom(let from, let to):
            return (from, to)
        }
    }
}

/// 报表数据源粒度
nonisolated enum ReportSourceGranularity: String, Sendable, Equatable {
    case minutes
    case hours
    case days

    var label: String {
        switch self {
        case .minutes: return String(localized: "stats.r.granMinute")
        case .hours: return String(localized: "stats.r.granHour")
        case .days: return String(localized: "stats.r.granDay")
        }
    }

    var bucketSeconds: TimeInterval {
        switch self {
        case .minutes: return 60
        case .hours: return 3600
        case .days: return 86400
        }
    }
}

// MARK: - 基础快照

/// 报表元信息
nonisolated struct ReportMeta: Sendable, Equatable {
    let deviceName: String
    let modelName: String
    let osVersion: String
    let recordDays: Int
    let appVersion: String
    let isDirect: Bool
}

/// 应用标识与图标数据
nonisolated struct ReportAppIdentity: Sendable, Equatable {
    let appKey: String
    let name: String
    let iconPNG: Data?
}

/// 进程统计与告警快照
nonisolated struct ReportProcessData: Sendable {
    let identities: [String: ReportAppIdentity]
    let dailyRows: [StatisticsProcessStore.DailyAppRow]
    let batteryHistory: [StatisticsProcessStore.BatteryPoint]
    let alerts: [ProcessAlertEpisode]
}

/// 打开报表时一次性后台拉取的完整快照
nonisolated struct ReportSnapshot: Sendable {
    let capturedAt: Date
    let meta: ReportMeta
    let minutes: [StatisticsRow]
    let hours: [StatisticsRow]
    let days: [StatisticsRow]
    let process: ReportProcessData?
    let hardware: HardwareInventory?
}

// MARK: - 聚合展示模型

/// 负载分布统计（5 个档位）
nonisolated struct ReportDistribution: Sendable, Equatable {
    struct Bucket: Sendable, Equatable {
        let index: Int
        let label: String
        let seconds: Double
        let percent: Double
        let hoursText: String
    }

    let buckets: [Bucket]
    let totalCoverSeconds: Double

    var hasData: Bool { totalCoverSeconds > 0 }
}

/// 带断点支持的时间序列点
nonisolated struct ReportTimeSeriesPoint: Sendable, Equatable, Identifiable {
    let id: String
    let date: Date
    let seriesID: String
    let segmentID: Int
    let value: Double?
}

/// CPU 模块指标
nonisolated struct ReportCpuMetrics: Sendable, Equatable {
    let avgUsage: Double?
    let peakUsage: Double?
    let peakTime: Date?
    let sysAvg: Double?
    let userAvg: Double?
    let pCoreAvg: Double?
    let eCoreAvg: Double?
    let distribution: ReportDistribution?
    let highSeconds: Double?
}

/// GPU 模块指标
nonisolated struct ReportGpuMetrics: Sendable, Equatable {
    let avgUsage: Double?
    let peakUsage: Double?
    let memUsedAvg: Double?
    let tilerAvg: Double?
    let distribution: ReportDistribution?
    let highSeconds: Double?
}

/// 内存模块指标
nonisolated struct ReportMemoryMetrics: Sendable, Equatable {
    let usedAvgBytes: Double?
    let compressedAvgBytes: Double?
    let swapAvgBytes: Double?
    let pressureAvgPercent: Double?
    let usedPeakPercent: Double?
    let memPctAvg: Double?
    let hasSwapData: Bool
}

/// 网络模块指标
nonisolated struct ReportNetworkMetrics: Sendable, Equatable {
    struct DailyBar: Sendable, Equatable, Identifiable {
        let id: String
        let date: Date
        let dateText: String
        let downBytes: Double
        let upBytes: Double
    }

    let totalDownBytes: Double?
    let totalUpBytes: Double?
    let peakDownRate: Double?
    let peakUpRate: Double?
    let dailyBars: [DailyBar]
}

/// 磁盘模块指标
nonisolated struct ReportDiskMetrics: Sendable, Equatable {
    struct DailyBar: Sendable, Equatable, Identifiable {
        let id: String
        let date: Date
        let dateText: String
        let readBytes: Double
        let writeBytes: Double
    }

    let totalReadBytes: Double?
    let totalWriteBytes: Double?
    let peakReadRate: Double?
    let peakWriteRate: Double?
    let dailyBars: [DailyBar]
}

/// 电源与功耗指标
nonisolated struct ReportPowerMetrics: Sendable, Equatable {
    let avgPowerWatts: Double?
    let peakPowerWatts: Double?
}

/// 电池与健康指标
nonisolated struct ReportBatteryMetrics: Sendable, Equatable {
    struct DailyHealth: Sendable, Equatable, Identifiable {
        let id: Int64
        let day: Int64
        let date: Date
        let cycleCount: Int?
        let healthPercent: Double?
    }

    let avgLevel: Double?
    let avgTemp: Double?
    let acFraction: Double?
    let chargingFraction: Double?
    let dailyHistory: [DailyHealth]
    let isSupported: Bool
    let hasHistoryInRange: Bool
}

/// 热压力与风扇指标
nonisolated struct ReportThermalMetrics: Sendable, Equatable {
    let cpuThermalAvg: Double?
    let cpuTempAvg: Double?
    let fanAvgRPM: Double?
    let fanMaxRPM: Double?
    let hasFans: Bool
    let fanSensorAvailable: Bool
}

/// 单个应用聚合排行条目
nonisolated struct ReportAppRankingItem: Sendable, Equatable, Identifiable {
    let id: String
    let appKey: String
    let name: String
    let value: Double
    let valueText: String
    let tierHint: String?
    let iconData: Data?
}

/// 各类应用排行聚合
nonisolated struct ReportAppRankings: Sendable, Equatable {
    let cpuList: [ReportAppRankingItem]
    let memList: [ReportAppRankingItem]
    let gpuList: [ReportAppRankingItem]
    let netList: [ReportAppRankingItem]
    let highLoadAlerts: [ReportHighLoadAppGroup]

    var isEmpty: Bool {
        cpuList.isEmpty && memList.isEmpty && gpuList.isEmpty && netList.isEmpty && highLoadAlerts.isEmpty
    }
}

/// 高负载告警按应用聚合组
nonisolated struct ReportHighLoadAppGroup: Sendable, Equatable, Identifiable {
    let id: String
    let appKey: String
    let name: String
    let isOngoing: Bool
    let earliestStart: Date?
    let maxDurationMinutes: Int
    let episodes: [ProcessAlertEpisode]
    let iconData: Data?
}

/// 异常事件条目
nonisolated struct ReportEventItem: Sendable, Equatable, Identifiable {
    nonisolated enum Kind: Sendable, Equatable {
        case memory
        case thermal

        var title: String {
            switch self {
            case .memory: return String(localized: "stats.r.alertMem")
            case .thermal: return String(localized: "stats.r.alertThermal")
            }
        }

        var systemIcon: String {
            switch self {
            case .memory: return "memorychip"
            case .thermal: return "flame"
            }
        }
    }

    nonisolated enum State: Sendable, Equatable {
        case ongoing
        case interrupted
        case recovered

        var label: String {
            switch self {
            case .ongoing: return String(localized: "stats.r.alertOngoing")
            case .interrupted: return String(localized: "stats.r.alertInterrupted")
            case .recovered: return String(localized: "stats.r.alertRecovered")
            }
        }
    }

    let id: String
    let kind: Kind
    let state: State
    let start: Date
    let end: Date
    let pressureSeconds: Double
    let worstLevel: Int
    let detailText: String
}

/// 智能洞察条目
nonisolated struct ReportInsightItem: Sendable, Equatable, Identifiable {
    let id: String
    let systemIcon: String
    let colorName: String
    let title: String
    let detail: String
}

/// 7x24 活动热力图单元格
nonisolated struct ReportHeatmapCell: Sendable, Equatable, Identifiable {
    let id: String
    let weekday: Int // 0=Sun, 1=Mon, ..., 6=Sat
    let hour: Int // 0..23
    let intensity: Double // 0.0 ~ 1.0
    let avgBusy: Double?
    var avgCpu: Double? { avgBusy }
}

/// 活动热力图数据
nonisolated struct ReportHeatmapData: Sendable, Equatable {
    let cells: [ReportHeatmapCell]
}

/// 每日汇总聚合表条目
nonisolated struct ReportDailySummaryRow: Sendable, Equatable, Identifiable {
    let id: Int64
    let date: Date
    let dayKey: String
    let cpuAvg: Double?
    let cpuPeak: Double?
    let memAvgPct: Double?
    let memPressureAvg: Double?
    let netDownTotal: Double?
    let netUpTotal: Double?
    let diskReadTotal: Double?
    let diskWriteTotal: Double?
    let acFrac: Double?
    let powerAvg: Double?
    let coverageHours: Double?
}

/// 当前激活范围的完整聚合视图模型（纯数据，不可变）
nonisolated struct ReportActiveRangeModel: Sendable, Equatable {
    let range: ReportTimeRange
    let granularity: ReportSourceGranularity
    let from: Date
    let to: Date
    let rows: [StatisticsRow]
    /// 所选时间范围内的有效采样覆盖比例（0...1）；无有效范围或无样本时为 nil。
    let coverageRatio: Double?

    var coveragePercent: Double? { coverageRatio.map { $0 * 100 } }


    let healthScore: StatisticsHealthScore.Result?
    let healthScoreNilReason: String?
    let cpu: ReportCpuMetrics
    let gpu: ReportGpuMetrics
    let memory: ReportMemoryMetrics
    let network: ReportNetworkMetrics
    let disk: ReportDiskMetrics
    let power: ReportPowerMetrics
    let battery: ReportBatteryMetrics
    let thermal: ReportThermalMetrics
    let apps: ReportAppRankings
    let events: [ReportEventItem]
    let insights: [ReportInsightItem]
    let heatmap: ReportHeatmapData?
    let dailySummaryRows: [ReportDailySummaryRow]

    var hasData: Bool { !rows.isEmpty }
}

nonisolated extension StatisticsRow: Identifiable {
    public var id: Int64 { t }
}
