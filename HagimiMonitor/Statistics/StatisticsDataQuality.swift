import Foundation

/// 统计结果的数据质量与数据源属性，用于区分无数据、真实零、旧版估算及通道不支持等状态。
/// 同时包含覆盖时长、粒度、数据版本及更新时间等元信息。
nonisolated struct StatisticsDataQuality: OptionSet, Sendable, Equatable {
    let rawValue: Int

    /// 本期有真实观测。
    static let observed = StatisticsDataQuality(rawValue: 1 << 0)
    /// 范围内只有部分覆盖，边界或缺口处没有数据。
    static let partialCoverage = StatisticsDataQuality(rawValue: 1 << 1)
    /// 数值来自旧版日汇总，无法还原分钟明细。
    static let legacyDailyEstimate = StatisticsDataQuality(rawValue: 1 << 2)
    /// 数值来自每分钟前列采样，只是样本均值/估算，不是完整资源账本。
    static let leadingSampleEstimate = StatisticsDataQuality(rawValue: 1 << 3)
    /// 所选范围没有任何有效观测。
    static let noObservation = StatisticsDataQuality(rawValue: 1 << 4)
    /// 当前渠道或系统不支持该指标（例如缺少对应探针）。
    static let sourceUnsupported = StatisticsDataQuality(rawValue: 1 << 5)

    var isEstimate: Bool {
        !intersection([.legacyDailyEstimate, .leadingSampleEstimate]).isEmpty
    }

    /// 是否有可用数值：有真实观测，或存在估算来源。
    var hasUsableValue: Bool {
        !intersection([.observed, .legacyDailyEstimate, .leadingSampleEstimate]).isEmpty
    }

    var isMissing: Bool {
        !hasUsableValue
    }

    static let empty: StatisticsDataQuality = []

    /// 组合多项质量。缺失标记与可用标记不会互相抵消，交由展示层按顺序说明。
    func combining(_ other: StatisticsDataQuality) -> StatisticsDataQuality {
        StatisticsDataQuality(rawValue: rawValue | other.rawValue)
    }
}

/// 统计指标结果，包含数值、数据质量、覆盖时长及来源元信息。
/// `value` 为 nil 表示无可用数值，`value == 0` 表示观测值为零。
nonisolated struct StatisticsMetricResult: Sendable, Equatable {
    let metric: StatisticsMetricDefinition.Metric
    let value: Double?
    let quality: StatisticsDataQuality
    /// 该指标在本期内真正被观测到的秒数。
    let coveredSeconds: Double
    /// 数据来源的粒度（秒）；日汇总为 86400，分钟桶为 60。
    let granularitySeconds: Double
    /// 产生该结果的指标契约版本。
    let sourceVersion: Int
    let updatedAt: Date?

    init(
        metric: StatisticsMetricDefinition.Metric,
        value: Double?,
        quality: StatisticsDataQuality,
        coveredSeconds: Double = 0,
        granularitySeconds: Double = 60,
        sourceVersion: Int = StatisticsMetricDefinition.version,
        updatedAt: Date? = nil
    ) {
        self.metric = metric
        self.value = value
        self.quality = quality
        self.coveredSeconds = coveredSeconds
        self.granularitySeconds = granularitySeconds
        self.sourceVersion = sourceVersion
        self.updatedAt = updatedAt
    }

    /// 覆盖占本期的比例；未提供本期长度时返回 nil，不猜测。
    func coverageRatio(ofPeriodSeconds periodSeconds: Double) -> Double? {
        guard periodSeconds > 0 else { return nil }
        return min(1, max(0, coveredSeconds / periodSeconds))
    }

    /// 数值是否为真实的非零观测（用于区分「真实零」与「无值」）。
    var isRealZero: Bool {
        value == 0 && quality.hasUsableValue
    }
}
