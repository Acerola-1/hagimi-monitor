import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 指标定义合同：单位、档位、容量相关门槛与百分比基准。
/// 这些断言是设置、通知、报表和导出共用的唯一口径来源。
struct StatisticsMetricDefinitionTests {
    private let gib = StatisticsMetricDefinition.gibibyte

    // MARK: - 内存档位

    @Test func memoryBandBoundariesUseBinaryCapacityAndTopBandIsFourGiB() {
        // 5.8 GiB 必须落在 4 GiB+ 段，而不是旧实现里的「8 GB+」。
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 5.8 * gib)?.label == "4 GiB")
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 4 * gib)?.label == "4 GiB")
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 2 * gib)?.label == "2 GiB")
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 1 * gib)?.label == "1 GiB")
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 1 * gib - 1) == nil)
        #expect(StatisticsMetricDefinition.band(for: .memory, rawValue: 0) == nil)
    }

    @Test func memoryBandBoundariesMatchDeclaredBands() {
        let bounds = StatisticsMetricDefinition.memoryBands.map(\.lowerBound)
        #expect(bounds == [1 * gib, 2 * gib, 4 * gib])
        // 展示标签不再出现旧实现的 8+ 段。
        #expect(StatisticsMetricDefinition.memoryBands.allSatisfy { !$0.label.contains("8") })
    }

    // MARK: - 网络单位与门槛

    @Test func networkBandLabelsConvertRawBoundariesToDecimalUnits() {
        // 原始边界是 MiB/s，标签换算成十进制 MB/s，门槛本身不变。
        #expect(StatisticsMetricDefinition.networkBandBoundaries == [5, 20, 50])
        #expect(StatisticsMetricDefinition.band(for: .network, rawValue: 5 * StatisticsMetricDefinition.mebibyte)?.label == "5.2 MB/s")
        #expect(StatisticsMetricDefinition.band(for: .network, rawValue: 20 * StatisticsMetricDefinition.mebibyte)?.label == "21 MB/s")
        #expect(StatisticsMetricDefinition.band(for: .network, rawValue: 50 * StatisticsMetricDefinition.mebibyte)?.label == "52 MB/s")
        #expect(StatisticsMetricDefinition.band(for: .network, rawValue: 5 * StatisticsMetricDefinition.mebibyte - 1) == nil)
    }

    @Test func networkAttentionThresholdKeepsOriginalRawBytes() {
        let threshold = StatisticsMetricDefinition.attentionThreshold(for: .network)
        #expect(threshold?.value == 20 * StatisticsMetricDefinition.mebibyte)
        // 1 MiB/s 远低于门槛，不因单位换算被放大成关注事件。
        #expect((threshold?.value ?? 0) > 1 * StatisticsMetricDefinition.mebibyte)
    }

    // MARK: - 容量相关内存门槛

    @Test func memoryThresholdScalesWithPhysicalCapacity() {
        let floor = StatisticsMetricDefinition.memoryAttentionFloor
        #expect(floor == 3.5 * gib)

        let sixteen = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 16 * gib)
        #expect(sixteen?.value == 3.5 * gib)          // 16 GiB × 20% = 3.2 GiB，低于绝对下限
        #expect(sixteen?.considersPhysicalCapacity == true)

        let sixtyFour = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 64 * gib)
        #expect(sixtyFour?.value == 12.8 * gib)       // 64 GiB × 20% 高于下限
        #expect(sixtyFour?.considersPhysicalCapacity == true)

        let thirtyTwo = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 32 * gib)
        #expect(thirtyTwo?.value == 6.4 * gib)
    }

    @Test func memoryThresholdAtEightGiBStaysOnAbsoluteFloor() {
        // 8 GiB × 20% = 1.6 GiB，低于 3.5 GiB 下限，因此仍用绝对门槛。
        let eight = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 8 * gib)
        #expect(eight?.value == 3.5 * gib)
        #expect(eight?.considersPhysicalCapacity == true)
    }

    @Test func memoryThresholdBoundaryIsInclusiveOnTheFormula() {
        // 门槛本身按 >= 比较：刚好等于门槛应被判定为关注。
        let threshold = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 16 * gib)?.value ?? 0
        #expect(threshold == 3.5 * gib)
        #expect(threshold - 1 < threshold)
    }

    @Test func memoryThresholdFallsBackToFloorWhenCapacityUnknown() {
        let unknown = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: nil)
        #expect(unknown?.value == 3.5 * gib)
        #expect(unknown?.considersPhysicalCapacity == false)

        let zero = StatisticsMetricDefinition.attentionThreshold(for: .memory, physicalMemoryBytes: 0)
        #expect(zero?.considersPhysicalCapacity == false)
    }

    @Test func physicalMemoryIsReadableOnThisMachine() {
        let capacity = StatisticsMetricDefinition.physicalMemoryBytes()
        #expect(capacity != nil)
        #expect((capacity ?? 0) > 0)
    }

    // MARK: - 百分比基准

    @Test func cpuPercentBasisIsSingleCoreAndNotClamped() {
        #expect(StatisticsMetricDefinition.percentBasis(for: .cpu) == .singleCore)
        #expect(StatisticsMetricDefinition.percentBasis(for: .cpu).isInterpretableAsWholeMachineShare)
        // 240% 保留原值，不截断成 100%。
        #expect(StatisticsDisplayFormat.applicationObservationValue(240, metric: .cpu) == "240%")
        // 80% 段是占用区间，不是整机满载。
        #expect(StatisticsMetricDefinition.band(for: .cpu, rawValue: 80)?.label == "80%")
    }

    @Test func gpuBasisIsMarkedUninterpretable() {
        #expect(StatisticsMetricDefinition.percentBasis(for: .gpu) == .unknownSourceDenominator)
        #expect(StatisticsMetricDefinition.percentBasis(for: .gpu).isInterpretableAsWholeMachineShare == false)
    }

    // MARK: - 单位种类

    @Test func unitKindsSeparateCapacityRateAndPercent() {
        #expect(StatisticsMetricDefinition.unitKind(for: .cpu) == .percent)
        #expect(StatisticsMetricDefinition.unitKind(for: .memory) == .binaryCapacity)
        #expect(StatisticsMetricDefinition.unitKind(for: .network) == .decimalRate)
    }

    @Test func decimalVolumeAndBinaryCapacityDoNotShareDivisors() {
        // 同一 156,000,000,000 字节：总量用十进制 GB，容量用二进制 GiB。
        #expect(StatisticsDisplayFormat.decimalVolume(156_000_000_000) == "156 GB")
        #expect(StatisticsDisplayFormat.binaryCapacity(156_000_000_000) == "145 GiB")
        // 1 MiB/s 的十进制表达。
        #expect(StatisticsDisplayFormat.decimalRate(StatisticsMetricDefinition.mebibyte) == "1.0 MB/s")
    }

    @Test func contractVersionIsDeclared() {
        #expect(StatisticsMetricDefinition.version >= 2)
    }
}
