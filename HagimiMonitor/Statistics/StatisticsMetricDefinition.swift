import Foundation

/// 统计指标的统一标准定义：原始单位、百分比基准、关注门槛、档位边界与数据契约版本。
///
/// 采集与状态机使用原始物理量（百分比、字节、字节/秒），设置、通知、报表与导出
/// 统一依据本定义生成显示标签与对应门槛。
nonisolated enum StatisticsMetricDefinition: Sendable {

    /// 应用级指标。系统级指标(温度、功耗等)不走应用门槛,故不在此列。
    enum Metric: String, CaseIterable, Sendable {
        case cpu
        case gpu
        case memory
        case network
    }

    /// 一个档位:原始单位下的下界(含)与该档位在 UI 中显示的标签。
    struct Band: Sendable, Equatable {
        let lowerBound: Double
        let label: String
    }

    /// 契约版本。落库或导出携带它,用于区分不同口径产生的历史数据。
    static let version = 2

    // MARK: - 原始单位与基准

    /// CPU 与 GPU 的百分比基准说明。CPU 以单个逻辑核 100% 为基准，可超过 100%；
    /// GPU 来源分母为单项指标基准，不可跨应用线性相加。
    enum PercentBasis: Sendable, Equatable {
        /// 单逻辑核 100%,可超过 100%。
        case singleCore
        /// 基准未知或不可跨应用相加。
        case unknownSourceDenominator

        var isInterpretableAsWholeMachineShare: Bool {
            self == .singleCore
        }
    }

    static func percentBasis(for metric: Metric) -> PercentBasis {
        switch metric {
        case .cpu: .singleCore
        case .gpu: .unknownSourceDenominator
        case .memory, .network: .singleCore
        }
    }

    /// 显示用量时使用的单位语义，明确区分二进制容量与十进制吞吐/总量。
    enum UnitKind: Sendable, Equatable {
        /// 百分比(占用率)。
        case percent
        /// 二进制容量(GiB/MiB)。
        case binaryCapacity
        /// 十进制吞吐(MB/s、GB/s)。
        case decimalRate
        /// 十进制总量(GB、TB)。
        case decimalVolume
    }

    static func unitKind(for metric: Metric) -> UnitKind {
        switch metric {
        case .cpu, .gpu: .percent
        case .memory: .binaryCapacity
        case .network: .decimalRate
        }
    }

    // MARK: - 档位

    /// 内存档位边界（1/2/4 GiB）。
    static let memoryBands: [Band] = [
        Band(lowerBound: 1 * gibibyte, label: "1 GiB"),
        Band(lowerBound: 2 * gibibyte, label: "2 GiB"),
        Band(lowerBound: 4 * gibibyte, label: "4 GiB"),
    ]

    /// 网络档位边界（单位：MiB/s），展示时按十进制速率格式化。
    static let networkBandBoundaries: [Double] = [5, 20, 50]

    static let cpuBandBoundaries: [Double] = [30, 50, 80]

    static let gpuBandBoundaries: [Double] = [20, 40, 70]

    /// 返回某指标在原始单位下的档位下界，若低于首档则返回 nil。
    static func band(for metric: Metric, rawValue: Double) -> Band? {
        switch metric {
        case .cpu:
            return band(from: cpuBandBoundaries.map { Band(lowerBound: $0, label: "\(Int($0))%") }, rawValue: rawValue)
        case .gpu:
            return band(from: gpuBandBoundaries.map { Band(lowerBound: $0, label: "\(Int($0))%") }, rawValue: rawValue)
        case .memory:
            return band(from: memoryBands, rawValue: rawValue)
        case .network:
            let bands = networkBandBoundaries.enumerated().map { index, mebibytes -> Band in
                Band(
                    lowerBound: mebibytes * mebibyte,
                    label: StatisticsDisplayFormat.decimalRate(mebibytes * mebibyte)
                )
            }
            return band(from: bands, rawValue: rawValue)
        }
    }

    private static func band(from bands: [Band], rawValue: Double) -> Band? {
        guard rawValue.isFinite, rawValue > 0 else { return nil }
        return bands.last { rawValue >= $0.lowerBound }
    }

    // MARK: - 关注门槛

    /// CPU 关注门槛（单核 60%）。
    static let cpuAttentionThreshold: Double = 60

    /// GPU 关注门槛（40%）。
    static let gpuAttentionThreshold: Double = 40

    /// 内存关注门槛：取 3.5 GiB 与物理内存 20% 的较大值。若物理容量未知则回退至 3.5 GiB。
    static let memoryAttentionFloor: Double = 3.5 * gibibyte
    static let memoryAttentionCapacityFraction: Double = 0.2

    /// 网络关注门槛（20 MiB/s）。
    static let networkAttentionThreshold: Double = 20 * mebibyte

    struct AttentionThreshold: Sendable, Equatable {
        let value: Double
        /// 是否考虑物理内存容量。若为 false 表示无法获取物理内存容量，采用固定门槛。
        let considersPhysicalCapacity: Bool
    }

    static func attentionThreshold(for metric: Metric, physicalMemoryBytes: Double? = nil) -> AttentionThreshold? {
        switch metric {
        case .cpu:
            return AttentionThreshold(value: cpuAttentionThreshold, considersPhysicalCapacity: false)
        case .gpu:
            return AttentionThreshold(value: gpuAttentionThreshold, considersPhysicalCapacity: false)
        case .network:
            return AttentionThreshold(value: networkAttentionThreshold, considersPhysicalCapacity: false)
        case .memory:
            guard let physicalMemoryBytes, physicalMemoryBytes > 0 else {
                return AttentionThreshold(value: memoryAttentionFloor, considersPhysicalCapacity: false)
            }
            return AttentionThreshold(
                value: max(memoryAttentionFloor, physicalMemoryBytes * memoryAttentionCapacityFraction),
                considersPhysicalCapacity: true
            )
        }
    }

    /// 本机物理内存大小（字节）。
    static func physicalMemoryBytes() -> Double? {
        let bytes = ProcessInfo.processInfo.physicalMemory
        guard bytes > 0 else { return nil }
        return Double(bytes)
    }

    // MARK: - 单位常量

    static let gibibyte: Double = 1_073_741_824
    static let mebibyte: Double = 1_048_576
    static let kibibyte: Double = 1_024
}
