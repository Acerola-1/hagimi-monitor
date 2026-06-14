import AppKit
import Darwin
import Foundation

struct TopMemoryProcess: Identifiable {
    let pid: pid_t
    let name: String
    /// 进程真实内存占用(phys_footprint),与活动监视器"内存"列口径一致。
    let memoryUsage: UInt64

    var id: pid_t { pid }
}

/// 系统进程的可执行文件所在路径前缀。匹配这些前缀的视为系统进程,
/// 在用户关闭"显示系统进程"时过滤掉。参考活动监视器的进程分类。
private let systemProcessPathPrefixes: [String] = [
    "/System/",
    "/usr/",
    "/sbin/",
    "/bin/",
    "/private/",
    "/Library/Apple/",
    "/Library/Filesystems/",
]

/// 返回内存占用最高的 N 个进程。
/// - Parameters:
///   - limit: 返回的进程数量上限
///   - includeSystemProcesses: 是否包含系统进程(kernel_task、守护进程等)。
///     默认 false——大多数用户关心的是第三方 App 的内存占用,系统进程数字
///     大但没有可操作性。开启后与活动监视器口径一致。
///
/// 用 `proc_listallpids` 枚举全部进程(含后台守护进程),用 `proc_pid_rusage`
/// 读取 `ri_phys_footprint`(对齐活动监视器"内存"列),而非 `pti_resident_size`
/// (常驻内存,数值偏大且与活动监视器不一致)。
func sampleTopMemoryProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [TopMemoryProcess] {
    // 先获取全部 pid。proc_listallpids 传 nil 仅返回数量,据此分配缓冲区。
    let numberOfPids = proc_listallpids(nil, 0)
    guard numberOfPids > 0 else { return [] }

    let pidBufferSize = Int32(numberOfPids)
    var pids = [pid_t](repeating: 0, count: Int(pidBufferSize))
    let actualCount = proc_listallpids(&pids, pidBufferSize)
    guard actualCount > 0 else { return [] }

    var result: [TopMemoryProcess] = []
    result.reserveCapacity(Int(actualCount))

    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

    for i in 0..<Int(actualCount) {
        let pid = pids[i]
        guard pid > 0 else { continue }

        // 可执行文件路径:用于取友好名 + 判断是否系统进程
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        let path: String = pathLength > 0 ? String(cString: pathBuffer) : ""

        // 系统进程过滤:路径匹配系统目录前缀的跳过(除非用户要求显示)。
        // 路径为空通常是内核级进程(如 kernel_task),也归为系统进程。
        if !includeSystemProcesses {
            if path.isEmpty || systemProcessPathPrefixes.contains(where: { path.hasPrefix($0) }) {
                continue
            }
        }

        let name = friendlyName(for: pid, path: path)
        guard !name.isEmpty else { continue }

        // phys_footprint:进程真实物理内存占用(含压缩/置换),与活动监视器
        // "内存"列口径一致。proc_taskinfo 没有该字段,需用 proc_pid_rusage。
        // libproc 的 rusage_info_t 是 void*;传入缓冲区指针,成功后绑定回结构体。
        var rusage = rusage_info_current()
        let rusageResult = withUnsafeMutablePointer(to: &rusage) { structPtr -> Int32 in
            structPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rawPtr)
            }
        }
        guard rusageResult == 0 else { continue }
        let memory = rusage.ri_phys_footprint

        result.append(TopMemoryProcess(pid: pid, name: name, memoryUsage: memory))
    }

    return Array(result.sorted { $0.memoryUsage > $1.memoryUsage }.prefix(limit))
}

/// 生成进程的显示名:优先用 NSWorkspace 的本地化名(如"谷歌浏览器"),
/// 其次取路径末尾组件,最后回退到 pid。
private func friendlyName(for pid: pid_t, path: String) -> String {
    // NSWorkspace 能给出 bundle 的本地化名,体验最好
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
       let name = app.localizedName, !name.isEmpty
    {
        return name
    }
    if !path.isEmpty {
        let last = (path as NSString).lastPathComponent
        if !last.isEmpty { return last }
    }
    return "pid \(pid)"
}
