import Foundation

// MARK: - HealthLevel

enum HealthLevel: String, CaseIterable {
    case excellent  // 85-100
    case good       // 70-84
    case fair       // 50-69
    case poor       // 30-49
    case critical   // 0-29

    init(score: Double) {
        switch score {
        case 85...100: self = .excellent
        case 70..<85:  self = .good
        case 50..<70:  self = .fair
        case 30..<50:  self = .poor
        default:       self = .critical
        }
    }

    var title: String {
        switch self {
        case .excellent: return String(localized: "health.level.excellent")
        case .good:      return String(localized: "health.level.good")
        case .fair:      return String(localized: "health.level.fair")
        case .poor:      return String(localized: "health.level.poor")
        case .critical:  return String(localized: "health.level.critical")
        }
    }
}

// MARK: - DimensionScore

struct DimensionScore: Identifiable {
    let id = UUID()
    let name: String           // Localized display name
    let rawText: String        // Localized display of the original value (e.g. "32%", "2.3 GB", "正常")
    let rawValue: Double       // Original numeric value (e.g. 72 for 72%, level int for pressure/thermal)
    let healthValue: Double    // Health degree 0-1
    let weight: Double         // Effective weight (after redistribution)
    let level: HealthLevel
    let isAvailable: Bool      // Whether data exists for this dimension
}

// MARK: - HealthTrendPoint

struct HealthTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double          // 0-100
}

// MARK: - HealthScore

struct HealthScore {
    let score: Double          // 0-100
    let level: HealthLevel
    let dimensions: [DimensionScore]
    let thermalCapped: Bool    // Was score capped by thermal throttle
    let timeRange: StatisticsTimeRange
    let isDataAvailable: Bool  // False when the range has no persisted/pending data
    let trend: [HealthTrendPoint]  // Per-bucket score history (oldest → newest)
}

// MARK: - HealthScoreWeights

struct HealthScoreWeights {
    // macOS 内存管理哲学：主动填满 RAM 做缓存，内存占用% 无意义；
    // Swap 也是正常内存管理手段。内存健康只看压力等级。
    var cpu: Double = 0.35
    var gpu: Double = 0.20
    var disk: Double = 0.15
    var pressure: Double = 0.25
    var thermal: Double = 0.05

    var total: Double { cpu + gpu + disk + pressure + thermal }

    /// Normalize weights so they sum to 1.0
    func normalized() -> HealthScoreWeights {
        let t = total
        guard t > 0 else { return Self() }
        return HealthScoreWeights(
            cpu: cpu / t, gpu: gpu / t,
            disk: disk / t, pressure: pressure / t, thermal: thermal / t
        )
    }
}
