import AppKit
import Darwin
import Foundation

/// 逐进程能耗采样：读 `proc_pid_rusage`(V6) 的 `ri_energy_nj`（自进程启动累计的纳焦），
/// 相邻两帧差分得到平均功率，按宿主进程（responsible pid）合并子进程，再做指数平滑
/// 抑制每秒抖动，最后按平滑平均功率排序，产出前 `ProcessEnergyBreakdown.topCount` 名。
///
/// 为什么只属于 Direct target（2026-09 实机实测）：
/// - 该计数受内核 task 属主门控，普通用户只读得到**同用户进程**；WindowServer、powerd
///   等系统进程在 V0–V6 全部返回 EPERM（root 下可读，但本应用无特权组件），因此本区块
///   的分母只能是"可读进程之和"，界面标注不含系统进程；
/// - 沙盒（App Store 版）连**同用户他进程**的 rusage 都拒绝，所以商店版不接入本区块。
///
/// 成本：全量 ~840 个 pid 的 rusage + 路径读取实测 <10 ms，随 BatterySampler 的既有
/// 采样节奏执行，不新增定时器；基线需连续推进，故不随面板可见性启停。
final class ProcessEnergySampler {
    static let shared = ProcessEnergySampler()

    private struct Baseline {
        let energyNJ: UInt64
        let startAbstime: UInt64
        let uptime: TimeInterval
    }

    private struct Smoothed {
        var watts: Double
        var lastSeen: TimeInterval
    }

    private var baselines: [pid_t: Baseline] = [:]
    private var smoothed: [pid_t: Smoothed] = [:]
    private let lock = NSLock()

    /// 每秒一帧下的平滑系数：时间常数约 3 帧，兼顾稳定与响应（占比条不跳变）。
    private static let smoothing = 0.35
    /// 短暂未再出现的进程保留余量，避免列表行闪烁。
    private static let staleGrace: TimeInterval = 3
    /// 与 IOReport 功耗同口径：休眠/长暂停后的跨窗口均值没有实时展示意义。
    private static let maxElapsed: TimeInterval = 30
    /// 单进程功率上界（W）：越界说明计数异常，丢弃该帧而非污染占比。
    private static let maxWatts = 1_000.0

    func sample() -> ProcessEnergyBreakdown? {
        lock.lock()
        defer { lock.unlock() }
        let uptime = ProcessInfo.processInfo.systemUptime

        var joinedWatts: [pid_t: Double] = [:]
        for pid in Self.allPids() {
            var info = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { raw in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, raw)
                }
            }
            guard status == 0 else { continue }

            let energy = info.ri_energy_nj
            let startAbstime = info.ri_proc_start_abstime
            // 基线逐帧推进：即使本帧算不出功率（新进程/窗口过长），也不能让窗口持续拉大。
            defer { baselines[pid] = Baseline(energyNJ: energy, startAbstime: startAbstime, uptime: uptime) }
            guard let baseline = baselines[pid],
                  baseline.startAbstime == startAbstime,
                  energy >= baseline.energyNJ
            else { continue }

            let elapsed = uptime - baseline.uptime
            guard elapsed > 0, elapsed <= Self.maxElapsed else { continue }
            let watts = Double(energy - baseline.energyNJ) / 1e9 / elapsed
            guard watts >= 0, watts <= Self.maxWatts else { continue }

            // 子进程（Safari 的 WebContent、各 Helper）并入宿主 App，与 TOP 进程榜同口径。
            let responsible = responsiblePidResolver(pid)
            let owner: pid_t = responsible > 1 ? responsible : pid
            joinedWatts[owner, default: 0] += watts
        }

        for (owner, watts) in joinedWatts {
            let previous = smoothed[owner]?.watts ?? watts
            smoothed[owner] = Smoothed(
                watts: previous + Self.smoothing * (watts - previous),
                lastSeen: uptime
            )
        }
        smoothed = smoothed.filter { uptime - $0.value.lastSeen <= Self.staleGrace }

        let total = smoothed.values.reduce(0) { $0 + $1.watts }
        guard total > 0 else { return nil }

        let ranked = smoothed.sorted { $0.value.watts > $1.value.watts }.prefix(ProcessEnergyBreakdown.topCount)
        var shares: [ProcessEnergyShare] = []
        var topWatts = 0.0
        for (pid, entry) in ranked {
            let share = entry.watts / total
            guard share > 0 else { continue }
            topWatts += entry.watts
            shares.append(ProcessEnergyShare(
                pid: pid,
                name: Self.displayName(for: pid),
                icon: NSRunningApplication(processIdentifier: pid)?.icon,
                share: share,
                watts: entry.watts
            ))
        }
        guard !shares.isEmpty else { return nil }

        return ProcessEnergyBreakdown(
            shares: shares,
            otherShare: max(0, (total - topWatts) / total),
            totalWatts: total
        )
    }

    /// 枚举全部 pid：`proc_listpids` 不区分属主，属主门控发生在读取时。
    private static func allPids() -> [pid_t] {
        let capacity = 8192
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 1 }
    }

    /// 展示名：优先 App 本地化名，其次可执行文件名（系统守护进程无 NSRunningApplication）。
    private static func displayName(for pid: pid_t) -> String {
        if let localized = NSRunningApplication(processIdentifier: pid)?.localizedName, !localized.isEmpty {
            return localized
        }
        let name = (executablePath(for: pid) as NSString).lastPathComponent
        return name.isEmpty ? "pid \(pid)" : name
    }
}
