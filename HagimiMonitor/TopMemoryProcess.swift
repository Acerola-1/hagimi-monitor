import AppKit
import Foundation

struct TopMemoryProcess: Identifiable {
    let pid: pid_t
    let name: String
    let memoryUsage: UInt64

    var id: pid_t { pid }
}

/// 返回内存占用最高的 N 个进程
func sampleTopMemoryProcesses(limit: Int = 5) -> [TopMemoryProcess] {
    var result: [TopMemoryProcess] = []

    for app in NSWorkspace.shared.runningApplications {
        let pid = app.processIdentifier
        let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? "\(pid)"
        guard !name.isEmpty else { continue }

        var info = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.stride))
        let memory = size > 0 ? info.pti_resident_size : 0

        result.append(TopMemoryProcess(pid: pid, name: name, memoryUsage: memory))
    }

    return result
        .sorted { $0.memoryUsage > $1.memoryUsage }
        .prefix(limit)
        .map { $0 }
}
