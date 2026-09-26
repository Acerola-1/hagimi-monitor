import Foundation

/// Game HUD 负载历史:为 CPU/GPU 曲线维护独立的滚动序列。
///
/// `MonitorModule.samples` 是主面板 sparkline 的历史,长度跟随主面板
/// 显示逻辑;HUD 需要隐藏期间不积累(隐藏不重绘、恢复时从当前值重新
/// 生长),故独立维护,不复用也不改写主面板序列。
nonisolated struct GameHUDSampleHistory {
    /// 曲线容量:与主面板 sparklineMaxPoints(24)同一档口径,点数一致
    /// 时视觉密度相当;HUD 卡片更紧凑,不另设更大窗口。
    static let capacity = MonitorConstants.sparklineMaxPoints

    private(set) var cpuUsage: [Double] = []
    private(set) var gpuRender: [Double] = []
    private(set) var fpsHistory: [Double] = []
    /// 用一轮快照推进历史。只消费百分比条目;值为 nil 的轮次跳过,
    /// 不往曲线里塞 0(缺值不是满载为 0)。
    mutating func record(_ snapshot: GameHUDSnapshot) {
        for reading in snapshot.readings {
            guard let percent = reading.percent else { continue }
            switch reading.metricID {
            case GameHUDMetricID.cpuUsage.rawValue:
                append(&cpuUsage, percent)
            case GameHUDMetricID.gpuRender.rawValue:
                append(&gpuRender, percent)
            default:
                break
            }
        }
    }

    /// 记录一轮实时 FPS 样本用于绘制帧率曲线。
    mutating func recordFPS(_ fps: Double) {
        guard fps > 0, fps.isFinite else { return }
        append(&fpsHistory, fps)
    }

    /// HUD 隐藏时清空:恢复显示后曲线从零点开始重新积累,不回放陈旧历史。
    mutating func reset() {
        cpuUsage = []
        gpuRender = []
        fpsHistory = []
    }

    private func append(_ array: inout [Double], _ value: Double) {
        array.append(value)
        let maxCapacity = Self.capacity
        if array.count > maxCapacity {
            array.removeFirst(array.count - maxCapacity)
        }
    }
}
