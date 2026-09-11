import Foundation

/// 状态评分:只在内存与系统热状态「同时有效」的交集 J 上计算两项压力负担再线性
/// 重组——负担 = Σ(档位权重 × 档位秒数) ÷ 交集有效观测秒数(模型 §6)。原始档位
/// 秒数落库(StatisticsRow 秒数列),权重只参与展示侧计算,便于按回放校准演进。
/// CPU/GPU 使用率是工作强度,内存占用与温度是解释项:都不参与评分,满载不扣分。
/// 升级前历史没有档位秒数,整段按旧应力口径呈现(近似),不与新口径混合。
/// 电池健康度不纳入:它是硬件属性而非窗口内状态,由报表电池区与洞察单独呈现。
enum StatisticsHealthScore {
    /// 两项负担的权重(和为 1):内存压力是 macOS 最真实的健康信号,热次之。
    static let memWeight = 0.6
    static let thermalWeight = 0.4

    /// 档位权重(候选初始值,待真实记录回放校准,不是硬件安全标准):
    /// 内存 normal/warning/critical = 0/0.6/1;热 nominal/fair/serious/critical = 0/0.2/0.6/1。
    static let memoryLevelWeights: [Double] = [0, 0.6, 1]
    static let thermalLevelWeights: [Double] = [0, 0.2, 0.6, 1]

    /// 工作强度阈值:CPU 85%、GPU 90% 起算高负载秒数(旧口径曲线同线起罚)。
    static let cpuHighThreshold = 85.0
    static let gpuHighThreshold = 90.0

    /// 最低交集观测时长与覆盖比例(模型 §6):交集不足 30 分钟、或不足监控应
    /// 覆盖时长的 90% 不出范围总分——样本太薄与缺失都不生成满分。
    static let minIntersectionSeconds: TimeInterval = 30 * 60
    static let minCoverageRatio = 0.9

    enum Level: String, CaseIterable {
        case low
        case mild
        case elevated
        case high

        /// 分数标签(模型 §6 候选):只描述压力负担,避免「优秀/健康」暗示硬件质量。
        init(score: Double) {
            switch score {
            case 95...: self = .low
            case 85..<95: self = .mild
            case 70..<85: self = .elevated
            default: self = .high
            }
        }

        var title: String {
            switch self {
            case .low: String(localized: "stats.r.levelLow")
            case .mild: String(localized: "stats.r.levelMild")
            case .elevated: String(localized: "stats.r.levelElevated")
            case .high: String(localized: "stats.r.levelHigh")
            }
        }
    }

    struct Dimension: Identifiable {
        /// 维度类型:视图据此取模块配色,不依赖本地化后的名称。
        enum Kind {
            case cpu
            case gpu
            case memory
            case thermal
        }

        let kind: Kind
        let name: String
        let rawText: String
        /// 该维度的压力负担(0~1)。
        let stressShare: Double
        let isAvailable: Bool
        var id: String { name }

        var level: Level { levelForShare(stressShare) }
    }

    struct Result {
        let score: Double
        let level: Level
        let dimensions: [Dimension]
    }

    /// 对一段范围的行评分;两种口径都取不到数据返回 nil。
    static func evaluate(rows: [StatisticsRow]) -> Result? {
        let intersection = rows.compactMap(\.validMemThermalS).reduce(0, +)
        guard intersection > 0 else { return evaluateLegacyStress(rows) }
        guard intersection >= minIntersectionSeconds else { return nil }
        let covered = rows.compactMap(\.coverS).reduce(0, +)
        if covered > 0, intersection < covered * minCoverageRatio { return nil }

        let memBurden = weightedBurden(
            seconds: [sum(rows, \.memNormalJS), sum(rows, \.memWarnJS), sum(rows, \.memCritJS)],
            weights: memoryLevelWeights,
            intersection: intersection
        )
        let thermalBurden = weightedBurden(
            seconds: [sum(rows, \.thNominalJS), sum(rows, \.thFairJS), sum(rows, \.thSeriousJS), sum(rows, \.thCritJS)],
            weights: thermalLevelWeights,
            intersection: intersection
        )

        let stress = memBurden * memWeight + thermalBurden * thermalWeight
        let score = max(0, min(100, 100 * (1 - stress)))
        let dimensions = [
            Dimension(kind: .memory, name: String(localized: "stats.r.dimPressure"), rawText: shareText(memBurden),
                      stressShare: memBurden, isAvailable: true),
            Dimension(kind: .thermal, name: String(localized: "stats.r.dimThermal"), rawText: shareText(thermalBurden),
                      stressShare: thermalBurden, isAvailable: true),
        ]
        return Result(score: score, level: Level(score: score), dimensions: dimensions)
    }

    private static func sum(_ rows: [StatisticsRow], _ keyPath: KeyPath<StatisticsRow, Double?>) -> Double {
        rows.compactMap { $0[keyPath: keyPath] }.reduce(0, +)
    }

    private static func weightedBurden(seconds: [Double], weights: [Double], intersection: Double) -> Double {
        zip(seconds, weights).map(*).reduce(0, +) / intersection
    }

    // MARK: - 旧口径(升级前历史:无档位秒数,按帧级应力列近似)

    /// 旧口径:四个应力维度的帧数加权均值,CPU/GPU 在其中参与扣分。
    private static func evaluateLegacyStress(_ rows: [StatisticsRow]) -> Result? {
        let hasSignal = rows.contains {
            $0.stressCpuAvg != nil || $0.cpuAvg != nil
        }
        guard hasSignal else { return nil }

        // 逐行取应力(存列优先,旧行按桶均值回退),再按帧数加权平均。
        var memSum = 0.0, thermalSum = 0.0, cpuSum = 0.0, gpuSum = 0.0
        var memW = 0, thermalW = 0, cpuW = 0, gpuW = 0
        for row in rows where row.n > 0 {
            let w = Double(row.n)
            if let m = row.stressMemAvg ?? row.stressFallback(column: "stress_mem_avg") {
                memSum += m * w; memW += row.n
            }
            if let t = row.stressThermalAvg ?? row.stressFallback(column: "stress_thermal_avg") {
                thermalSum += t * w; thermalW += row.n
            }
            if let c = row.stressCpuAvg ?? row.stressFallback(column: "stress_cpu_avg") {
                cpuSum += c * w; cpuW += row.n
            }
            if let g = row.stressGpuAvg ?? row.stressFallback(column: "stress_gpu_avg") {
                gpuSum += g * w; gpuW += row.n
            }
        }
        let m = memW > 0 ? memSum / Double(memW) : nil
        let t = thermalW > 0 ? thermalSum / Double(thermalW) : nil
        let c = cpuW > 0 ? cpuSum / Double(cpuW) : nil
        let g = gpuW > 0 ? gpuSum / Double(gpuW) : nil
        guard m != nil || t != nil || c != nil || g != nil else { return nil }

        // 缺维度不扣分也不归一:没观测到不健康信号即不罚,保守诚实。
        let stress = (m ?? 0) * 0.45 + (t ?? 0) * 0.30 + (c ?? 0) * 0.15 + (g ?? 0) * 0.10
        let score = max(0, min(100, 100 * (1 - stress)))

        var dimensions: [Dimension] = []
        if let c {
            dimensions.append(Dimension(
                kind: .cpu, name: String(localized: "stats.r.dimCpu"),
                rawText: shareText(c), stressShare: c, isAvailable: true))
        }
        if let g {
            dimensions.append(Dimension(
                kind: .gpu, name: String(localized: "stats.r.dimGpu"),
                rawText: shareText(g), stressShare: g, isAvailable: true))
        }
        if let m {
            dimensions.append(Dimension(
                kind: .memory, name: String(localized: "stats.r.dimPressure"),
                rawText: shareText(m), stressShare: m, isAvailable: true))
        }
        if let t {
            dimensions.append(Dimension(
                kind: .thermal, name: String(localized: "stats.r.dimThermal"),
                rawText: shareText(t), stressShare: t, isAvailable: true))
        }

        return Result(score: score, level: Level(score: score), dimensions: dimensions)
    }

    /// 旧口径帧级应力曲线(记录器给报表落 stress 列、旧行回退共用;报表 JS 同口径):
    /// CPU 饱和:85% 以下不罚,85~100 线性到 1。中低负载是完全健康的工作状态。
    static func stressCPU(_ usage: Double) -> Double {
        usage <= cpuHighThreshold ? 0 : min(1, (usage - cpuHighThreshold) / (100 - cpuHighThreshold))
    }

    /// GPU 饱和:90% 以下不罚。持续满载渲染是尽职而非病态。
    static func stressGPU(_ usage: Double) -> Double {
        usage <= gpuHighThreshold ? 0 : min(1, (usage - gpuHighThreshold) / (100 - gpuHighThreshold))
    }

    /// 内存:内核裁定的压力档位为主(warning 0.6 / critical 1.0),
    /// 连续水位只做 60% 起点的缓变塑形(至多 0.55)——「忙但无压力」零扣分。
    static func stressMem(percent: Double?, level: Double?) -> Double {
        var stress: Double
        switch level {
        case .some(2): stress = 1.0
        case .some(1): stress = 0.6
        default: stress = 0
        }
        if let percent, percent > 60 {
            stress = max(stress, min(0.55, (percent - 60) / 40 * 0.55))
        }
        return stress
    }

    /// 热:thermal-pressure 档位是系统自己的裁定(0/1/2/3 → 0/0.2/0.6/1.0);
    /// 温度仅在档位缺失时作回退(沙盒场景),85°C 起罚——不作并行放大器,
    /// 避免「高温但健康」重新惩罚忙碌。
    static func stressThermal(state: Double?, temp: Double?) -> Double {
        if let state {
            switch state {
            case ..<0.5: return 0
            case ..<1.5: return 0.2
            case ..<2.5: return 0.6
            default: return 1.0
            }
        }
        guard let temp else { return 0 }
        return temp <= 85 ? 0 : min(1, (temp - 85) / 15)
    }

    // MARK: - 展示辅助

    /// 维度徽章等级:按压力负担分档。
    static func levelForShare(_ share: Double) -> Level {
        switch share * 100 {
        case ..<1: return .low
        case ..<5: return .mild
        case ..<15: return .elevated
        default: return .high
        }
    }

    private static func shareText(_ share: Double) -> String {
        let pct = share * 100
        return pct < 0.05 ? "0%" : String(format: "%.1f%%", pct)
    }
}
