import AppKit

/// 逐进程能耗排名里的一行：宿主进程（子进程已按 responsible pid 合并）的平滑平均功率。
///
/// 口径：`proc_pid_rusage` 的 `ri_energy_nj` 两次差分得到平均功率；`share` 的分母是
/// **全部可读进程**（同用户）的平滑能耗之和。
/// 系统进程（WindowServer、powerd 等）对该计数一律 EPERM，不在统计内——不得用 0
/// 或估算值冒充。采样与权限边界见 `ProcessEnergySampler`。
struct ProcessEnergyShare: Identifiable, Equatable {
    /// 宿主进程 pid（responsible pid）。
    let pid: pid_t
    let name: String
    let icon: NSImage?
    /// 占比 0...1。
    let share: Double
    /// 平滑后的平均功率（W），排名列表按此排序并展示。
    let watts: Double

    var id: pid_t { pid }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.share == rhs.share && lhs.watts == rhs.watts
    }
}

/// 分应用能耗占比的整体结果：前 N 名 + 其余聚合。
struct ProcessEnergyBreakdown: Equatable {
    /// 排名页展示的应用行数：与 `TopProcessList` 的固定 5 行一致，故取前 5 名。
    /// 视图与采样器共用，避免两处写死。
    static let topCount = 5

    let shares: [ProcessEnergyShare]
    /// 前 `ProcessEnergyBreakdown.topCount` 名之外的可读进程合计占比（0 表示没有剩余）。
    let otherShare: Double
    /// 参与统计的可读进程平滑总功率（W）。
    let totalWatts: Double
}
