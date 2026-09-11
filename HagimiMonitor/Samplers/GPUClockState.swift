import Foundation

/// GPU 时钟态驻留、热限速与功耗上限的读数。
///
/// 三个字段都来自 IOReport "GPU Stats" 的状态通道：状态通道给出的不是计数器，
/// 而是「区间内各状态各占多少 tick」。因此这里以原始 tick 为输入，只在产出
/// 占比时按区间总 tick 归一化——脱离归一化的原始 tick 是自开机起的累计量，
/// 直接读会得到一条几乎不动的曲线。
struct GPUClockStateReadout: Equatable {
    /// 区间内驻留最大的非 OFF 时钟态（如 "P3"）。OFF 表示 GPU 时钟停摆，
    /// 是停机档而非工作档，故不作为时钟态上报。
    var dominantState: String?
    /// 主导时钟态的区间占比，0...100。
    var dominantResidencyPercent: Double?
    /// 区间内被热管理压低时钟的占比，0...100。
    var throttlePercent: Double
    /// 按驻留加权的功耗上限（占最大 GPU 功耗的百分比）。nil 表示该机型无此通道。
    var powerCapPercent: Double?
}

/// 与渠道无关的纯计算，便于单测覆盖。IOReport 的实际读取在 Direct 版
/// `IOReportPowerSampler`，本文件不引入任何私有 API。
enum GPUClockStateMath {
    /// 把各状态的原始 tick 换算成区间占比（合计 100）。区间内无 tick 时
    /// 全部为 0，由调用方按「无数据」处理。
    static func normalized(_ states: [(name: String, ticks: Int64)]) -> [(name: String, percent: Double)] {
        let clamped = states.map { (name: $0.name, ticks: max(0, $0.ticks)) }
        let total = clamped.reduce(Int64(0)) { $0 + $1.ticks }
        guard total > 0 else { return clamped.map { ($0.name, 0) } }
        return clamped.map { ($0.name, Double($0.ticks) / Double(total) * 100) }
    }

    /// 主导时钟态：排除 OFF 后驻留最大者。全为 OFF 时返回 nil。
    static func dominantState(_ states: [(name: String, ticks: Int64)]) -> (name: String, percent: Double)? {
        normalized(states)
            .filter { $0.name.uppercased() != "OFF" && $0.percent > 0 }
            .max { $0.percent < $1.percent }
    }

    /// 热限速占比：CLTM 状态里凡不以 `NO_` 开头的，都是「时钟被压低」的区间。
    static func throttlePercent(_ states: [(name: String, ticks: Int64)]) -> Double {
        normalized(states)
            .filter { !$0.name.uppercased().hasPrefix("NO_") }
            .reduce(0) { $0 + $1.percent }
    }

    /// 功耗上限：状态名即档位（`"100%"` 或区间 `"0-9%"`），按驻留加权取代表值。
    /// 名称无法解析时忽略该状态；全部无法解析时返回 nil。
    static func powerCapPercent(_ states: [(name: String, ticks: Int64)]) -> Double? {
        var weighted = 0.0
        var weight = 0.0
        for state in normalized(states) {
            guard let value = bandValue(state.name), state.percent > 0 else { continue }
            weighted += value * state.percent
            weight += state.percent
        }
        guard weight > 0 else { return nil }
        return weighted / weight
    }

    /// 档位名 → 代表值：`"100%"` → 100，`"0-9%"` → 4.5（取区间中点）。
    /// 驱动给出的名称在同一组里既有单值又有区间，必须都认。
    static func bandValue(_ name: String) -> Double? {
        let digits = name.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !digits.isEmpty else { return nil }
        let bounds = digits.split(separator: "-").compactMap { Double(String($0)) }
        switch bounds.count {
        case 1: return bounds[0]
        case 2: return (bounds[0] + bounds[1]) / 2
        default: return nil
        }
    }
}
