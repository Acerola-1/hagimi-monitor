import Foundation

/// 健康评分 V2:「健康时间占比」语义——高负载不扣分,只对不健康状态扣分。
/// 四个应力维度(0~1)在落库时按帧算好存列(见 StatisticsRecorder),评分只做
/// 线性重组,消除「非线性曲线 × 桶均值」的抹平偏差;旧库无应力列时按桶均值
/// 回退同套曲线(近似,仅影响升级前历史)。电池健康度不纳入:它是硬件属性而非
/// 窗口内状态,由报表电池区与洞察单独呈现。
enum StatisticsHealthScore {
    /// 权重(和为 1):内存压力是 macOS 最真实的健康信号,热次之,饱和项低权重。
    static let memWeight = 0.45
    static let thermalWeight = 0.30
    static let cpuWeight = 0.15
    static let gpuWeight = 0.10

    /// 软帽:窗口过热应力均值 ≥0.01(≈1% critical / 2% serious 时长)评级至多良好。
    static let thermalSoftCapStress = 0.01

    enum Level: String {
        case excellent
        case good
        case fair
        case poor
        case critical

        /// 语义改为健康时间占比后分布上移,阈值收紧到 95/85/70/50。
        init(score: Double) {
            switch score {
            case 95...: self = .excellent
            case 85..<95: self = .good
            case 70..<85: self = .fair
            case 50..<70: self = .poor
            default: self = .critical
            }
        }

        var title: String {
            switch self {
            case .excellent: String(localized: "stats.r.levelExcellent")
            case .good: String(localized: "stats.r.levelGood")
            case .fair: String(localized: "stats.r.levelFair")
            case .poor: String(localized: "stats.r.levelPoor")
            case .critical: String(localized: "stats.r.levelCritical")
            }
        }
    }

    struct Dimension: Identifiable {
        let name: String
        let rawText: String
        /// 严重度加权的不健康时长占比(0~1)。
        let stressShare: Double
        let isAvailable: Bool
        var id: String { name }

        var level: Level { levelForShare(stressShare) }
    }

    struct Result {
        let score: Double
        let level: Level
        let dimensions: [Dimension]
        let thermalCapped: Bool
    }

    /// 对一段范围的行评分;无任何相关数据返回 nil。
    static func evaluate(rows: [StatisticsRow]) -> Result? {
        let hasSignal = rows.contains {
            $0.stressCpuAvg != nil || $0.cpuAvg != nil
        }
        guard hasSignal else { return nil }

        // 逐行取应力(存列优先,旧行按桶均值回退),再按帧数加权平均。
        var memSum = 0.0, thermalSum = 0.0, cpuSum = 0.0, gpuSum = 0.0
        var memW = 0, thermalW = 0, cpuW = 0, gpuW = 0
        for row in rows where row.n > 0 {
            let w = Double(row.n)
            if let m = row.stressMemAvg ?? fallbackMem(row) { memSum += m * w; memW += row.n }
            if let t = row.stressThermalAvg ?? fallbackThermal(row) { thermalSum += t * w; thermalW += row.n }
            if let c = row.stressCpuAvg ?? row.cpuAvg.map(stressCPU) { cpuSum += c * w; cpuW += row.n }
            if let g = row.stressGpuAvg ?? row.gpuAvg.map(stressGPU) { gpuSum += g * w; gpuW += row.n }
        }
        let m = memW > 0 ? memSum / Double(memW) : nil
        let t = thermalW > 0 ? thermalSum / Double(thermalW) : nil
        let c = cpuW > 0 ? cpuSum / Double(cpuW) : nil
        let g = gpuW > 0 ? gpuSum / Double(gpuW) : nil
        guard m != nil || t != nil || c != nil || g != nil else { return nil }

        // 缺维度不扣分也不归一:没观测到不健康信号即不罚,保守诚实。
        let stress = (m ?? 0) * memWeight + (t ?? 0) * thermalWeight
            + (c ?? 0) * cpuWeight + (g ?? 0) * gpuWeight
        let score = max(0, min(100, 100 * (1 - stress)))

        let capped = (t ?? 0) >= thermalSoftCapStress
        var level = Level(score: score)
        if capped, level == .excellent { level = .good }

        var dimensions: [Dimension] = []
        if let c {
            dimensions.append(Dimension(
                name: String(localized: "stats.r.dimCpu"),
                rawText: shareText(c), stressShare: c, isAvailable: true))
        }
        if let g {
            dimensions.append(Dimension(
                name: String(localized: "stats.r.dimGpu"),
                rawText: shareText(g), stressShare: g, isAvailable: true))
        }
        if let m {
            dimensions.append(Dimension(
                name: String(localized: "stats.r.dimPressure"),
                rawText: shareText(m), stressShare: m, isAvailable: true))
        }
        if let t {
            dimensions.append(Dimension(
                name: String(localized: "stats.r.dimThermal"),
                rawText: shareText(t), stressShare: t, isAvailable: true))
        }

        return Result(score: score, level: level, dimensions: dimensions, thermalCapped: capped)
    }

    // MARK: - 帧级应力曲线(记录器落库与旧行回退共用;报表 JS 同口径)

    /// CPU 饱和:85% 以下不罚,85~100 线性到 1。中低负载是完全健康的工作状态。
    static func stressCPU(_ usage: Double) -> Double {
        usage <= 85 ? 0 : min(1, (usage - 85) / 15)
    }

    /// GPU 饱和:90% 以下不罚。持续满载渲染是尽职而非病态。
    static func stressGPU(_ usage: Double) -> Double {
        usage <= 90 ? 0 : min(1, (usage - 90) / 10)
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

    // MARK: - 旧行回退(无应力列的升级前历史,按桶均值近似)

    private static func fallbackMem(_ row: StatisticsRow) -> Double? {
        guard row.memPressureAvg != nil else { return nil }
        return stressMem(percent: row.memPressureAvg, level: nil)
    }

    private static func fallbackThermal(_ row: StatisticsRow) -> Double? {
        guard row.cpuThermalAvg != nil || row.cpuTempAvg != nil else { return nil }
        return stressThermal(state: row.cpuThermalAvg, temp: row.cpuTempAvg)
    }

    // MARK: - 展示辅助

    /// 维度徽章等级:按不健康时长占比分档。
    static func levelForShare(_ share: Double) -> Level {
        switch share * 100 {
        case ..<1: return .excellent
        case ..<5: return .good
        case ..<15: return .fair
        case ..<30: return .poor
        default: return .critical
        }
    }

    private static func shareText(_ share: Double) -> String {
        let pct = share * 100
        return pct < 0.05 ? "0%" : String(format: "%.1f%%", pct)
    }
}
