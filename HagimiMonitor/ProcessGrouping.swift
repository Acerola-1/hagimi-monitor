import Darwin
import Foundation

/// 进程归属分组。
///
/// `responsibility_get_pid_responsible_for_pid` 是主口径,能覆盖 Safari 的 XPC 网页进程
/// 这类 ppid 已被 launchd 接管的子进程。但 Chromium 系应用(Chrome、Electron 等)在 spawn
/// helper 时调用 `responsibility_spawnattrs_setdisclaim` 主动放弃责任归属,helper 的
/// responsible pid 会指回自己;此时只按 responsible pid 分组,同一 App 的十几个 helper
/// 会各自成组,合计占用被拆到 TOP N 截断线以下,宿主 App 反而完全不显示。
///
/// 兜底沿 ppid 上溯,但只认同一个 `.app` 包内的祖先:既能把 helper 收回宿主,
/// 又不会把被别的 App 拉起的独立 App(启动器拉起的子应用、终端里的命令行工具等)
/// 误并进父进程。

/// 可执行文件路径所属的 `.app` 包根(含尾部斜杠)。不在 App 包内返回 nil。
nonisolated func appBundleRoot(of path: String) -> String? {
    guard let range = path.range(of: ".app/") else { return nil }
    return String(path[..<range.upperBound])
}

/// 在同一 `.app` 包内沿祖先链找到宿主 App 的 pid;找不到返回进程自身。
/// helper 与宿主之间可能还隔着 zygote 一类的中转进程,因此取包内最高的祖先,
/// 而不是最近的一层——分组名称与图标都以宿主的路径为准。
nonisolated func enclosingAppOwner(
    for pid: pid_t,
    parentOf: (pid_t) -> pid_t?,
    pathOf: (pid_t) -> String
) -> pid_t {
    guard let bundleRoot = appBundleRoot(of: pathOf(pid)) else { return pid }

    var owner = pid
    var current = pid
    // 正常进程树不会成环,上限只用于兜住异常数据。
    for _ in 0 ..< 32 {
        guard let parent = parentOf(current), parent > 1,
              appBundleRoot(of: pathOf(parent)) == bundleRoot
        else { break }
        owner = parent
        current = parent
    }
    return owner
}

/// 进程所属分组的 pid。responsible pid 有效(大于 0 且不是自身)时直接采用;
/// 否则按 `enclosingAppOwner` 兜底。
nonisolated func processGroupKey(
    for pid: pid_t,
    responsiblePid: pid_t,
    parentOf: (pid_t) -> pid_t?,
    pathOf: (pid_t) -> String
) -> pid_t {
    if responsiblePid > 0, responsiblePid != pid { return responsiblePid }
    return enclosingAppOwner(for: pid, parentOf: parentOf, pathOf: pathOf)
}

/// 进程 -> 父进程 pid 的惰性索引。只有遇到放弃 responsibility 的进程才需要祖先链,
/// 因此首次查询时才枚举 sysctl(KERN_PROC_ALL)(双渠道均放行),没有这类进程的机器
/// 不增加每拍固定开销。实例只在单条采样队列内使用。
nonisolated final class ProcessParentIndex {
    private var parents: [pid_t: pid_t]?

    func parent(of pid: pid_t) -> pid_t? {
        if parents == nil { parents = Self.loadParents() }
        return parents?[pid]
    }

    private static func loadParents() -> [pid_t: pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [:] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var parents: [pid_t: pid_t] = [:]
        parents.reserveCapacity(count)
        buffer.withUnsafeBytes { raw in
            let procs = raw.bindMemory(to: kinfo_proc.self)
            for index in 0 ..< count {
                let pid = procs[index].kp_proc.p_pid
                guard pid > 0 else { continue }
                parents[pid] = procs[index].kp_eproc.e_ppid
            }
        }
        return parents
    }
}
