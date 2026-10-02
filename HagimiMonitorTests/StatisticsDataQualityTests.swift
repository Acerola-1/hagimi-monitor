import Foundation
import Testing
@testable import HagimiMonitorDirect

/// M05 相关：质量标注必须能区分缺失、真实零、旧版估算、前列样本估算与不支持。
struct StatisticsDataQualityTests {
    @Test func missingValueIsDistinctFromRealZero() {
        let missing = StatisticsMetricResult(
            metric: .cpu,
            value: nil,
            quality: [.noObservation],
            coveredSeconds: 0
        )
        #expect(missing.quality.isMissing)
        #expect(missing.quality.hasUsableValue == false)
        #expect(missing.isRealZero == false)

        let realZero = StatisticsMetricResult(
            metric: .cpu,
            value: 0,
            quality: [.observed],
            coveredSeconds: 600
        )
        #expect(realZero.quality.isMissing == false)
        #expect(realZero.isRealZero)
    }

    @Test func legacyDailyEstimateIsFlaggedAsEstimate() {
        let legacy = StatisticsMetricResult(
            metric: .memory,
            value: 4.2 * StatisticsMetricDefinition.gibibyte,
            quality: [.observed, .legacyDailyEstimate],
            coveredSeconds: 3600,
            granularitySeconds: 86400
        )
        #expect(legacy.quality.isEstimate)
        #expect(legacy.quality.hasUsableValue)
        #expect(legacy.isRealZero == false)
    }

    @Test func leadingSampleEstimateIsFlaggedSeparately() {
        let sample = StatisticsMetricResult(
            metric: .cpu,
            value: 42,
            quality: [.observed, .leadingSampleEstimate, .partialCoverage],
            coveredSeconds: 300
        )
        #expect(sample.quality.contains(.leadingSampleEstimate))
        #expect(sample.quality.contains(.partialCoverage))
        #expect(sample.quality.isEstimate)
    }

    @Test func unsupportedSourceHasNoUsableValue() {
        let unsupported = StatisticsMetricResult(
            metric: .network,
            value: nil,
            quality: [.sourceUnsupported]
        )
        #expect(unsupported.quality.isMissing)
        #expect(unsupported.quality.hasUsableValue == false)
    }

    @Test func coverageRatioRequiresKnownPeriodAndClamps() {
        let result = StatisticsMetricResult(
            metric: .cpu,
            value: 10,
            quality: [.observed],
            coveredSeconds: 1800
        )
        #expect(result.coverageRatio(ofPeriodSeconds: 3600) == 0.5)
        #expect(result.coverageRatio(ofPeriodSeconds: 0) == nil)
        #expect(result.coverageRatio(ofPeriodSeconds: 600) == 1)
        #expect(result.coverageRatio(ofPeriodSeconds: -1) == nil)
    }

    @Test func qualityFlagsCombineWithoutLosingUsability() {
        let combined = StatisticsDataQuality.observed
            .combining(.partialCoverage)
            .combining(.leadingSampleEstimate)
        #expect(combined.contains(.observed))
        #expect(combined.contains(.partialCoverage))
        #expect(combined.contains(.leadingSampleEstimate))
        #expect(combined.hasUsableValue)
    }

    @Test func contractVersionTravelsWithResult() {
        let result = StatisticsMetricResult(metric: .cpu, value: 1, quality: [.observed])
        #expect(result.sourceVersion == StatisticsMetricDefinition.version)
    }

    // MARK: - 报表聚合层如何判定质量

    private func row(coverSeconds: Double, n: Int = 60) -> StatisticsRow {
        var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
        values[0] = 12
        let coverIndex = StatisticsRow.columns.firstIndex { $0.name == "cover_s" }!
        values[coverIndex] = coverSeconds
        return StatisticsRow(t: 1_700_000_000, n: n, values: values)
    }

    @Test func noRowsMeansNoObservation() {
        let quality = ReportDataAggregator.dataQuality(
            rows: [], coverageRatio: nil, granularity: .minutes, appsEstimateLeadingSample: false)
        #expect(quality.contains(.noObservation))
        #expect(quality.hasUsableValue == false)
    }

    @Test func dayGranularityIsFlaggedAsLegacyDaily() {
        let quality = ReportDataAggregator.dataQuality(
            rows: [row(coverSeconds: 86400)],
            coverageRatio: 1.0,
            granularity: .days,
            appsEstimateLeadingSample: false
        )
        #expect(quality.contains(.legacyDailyEstimate))
        #expect(quality.contains(.partialCoverage) == false)
    }

    @Test func lowCoverageIsFlaggedPartial() {
        let quality = ReportDataAggregator.dataQuality(
            rows: [row(coverSeconds: 600)],
            coverageRatio: 0.4,
            granularity: .minutes,
            appsEstimateLeadingSample: false
        )
        #expect(quality.contains(.partialCoverage))
        #expect(quality.contains(.legacyDailyEstimate) == false)
    }

    @Test func leadingSampleEstimateFollowsAppDataPresence() {
        let withApps = ReportDataAggregator.dataQuality(
            rows: [row(coverSeconds: 3600)], coverageRatio: 1.0,
            granularity: .minutes, appsEstimateLeadingSample: true)
        #expect(withApps.contains(.leadingSampleEstimate))

        let withoutApps = ReportDataAggregator.dataQuality(
            rows: [row(coverSeconds: 3600)], coverageRatio: 1.0,
            granularity: .minutes, appsEstimateLeadingSample: false)
        #expect(withoutApps.contains(.leadingSampleEstimate) == false)
    }
}
