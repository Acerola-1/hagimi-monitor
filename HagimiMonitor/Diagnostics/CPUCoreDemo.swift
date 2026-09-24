import Foundation

#if DEBUG
/// 仅显式调试启动时替换 CPU 逐核读数，便于对比两类与三类核心的原生布局。
/// 普通启动和发布构建不使用这些模拟数据。
nonisolated enum CPUCoreDemo {
    static let variant: Int? = {
        guard let value = ProcessInfo.processInfo.environment["HAGIMI_CPU_CORE_DEMO"],
              let count = Int(value), [2, 3].contains(count) else { return nil }
        return count
    }()

    static func detail(overallUsage: Double) -> CPUCoreDetail? {
        guard let variant else { return nil }

        let eValues = usages(count: 6, centeredAt: overallUsage - 12)
        let pValues = usages(count: 4, centeredAt: overallUsage + (variant == 3 ? 6 : 18))
        let sValues = variant == 3 ? usages(count: 2, centeredAt: overallUsage + 24) : []

        var cores: [CPUCoreLoad] = []
        for (kind, values) in [
            (CPUCoreKind.efficiency, eValues),
            (.performance, pValues),
            (.superCore, sValues)
        ] {
            for usage in values {
                cores.append(CPUCoreLoad(index: cores.count, usage: usage, kind: kind))
            }
        }

        return CPUCoreDetail(
            cores: cores,
            performanceUsage: average(pValues),
            efficiencyUsage: average(eValues),
            superUsage: sValues.isEmpty ? nil : average(sValues)
        )
    }

    private static func usages(count: Int, centeredAt center: Double) -> [Double] {
        let offsets: [Double] = [-5, 3, 8, -3, 1, -4]
        return (0..<count).map { index in
            min(100, max(0, center + offsets[index]))
        }
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}
#endif
