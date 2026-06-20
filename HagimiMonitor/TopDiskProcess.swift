import AppKit
import Darwin
import Foundation

struct TopDiskProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 自上次采样以来读取的字节数增量。
    let bytesRead: UInt64
    /// 自上次采样以来写入的字节数增量。
    let bytesWritten: UInt64
    let icon: NSImage?

    var id: pid_t { pid }

    static func == (lhs: TopDiskProcess, rhs: TopDiskProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.bytesRead == rhs.bytesRead && lhs.bytesWritten == rhs.bytesWritten
    }
}

struct RawDiskProcess {
    let pid: pid_t
    let path: String
    let fallbackName: String
    let bytesRead: UInt64
    let bytesWritten: UInt64
}

/// 磁盘 I/O 快照，用于计算增量。
private var previousDiskSnapshot: [pid_t: (read: UInt64, write: UInt64)] = [:]

/// 后台采样磁盘 I/O 最高的 N 个进程。
/// 使用 `proc_pid_rusage` 读取 `ri_diskio_bytesread` / `ri_diskio_byteswritten`,
/// 维护快照计算增量，按宿主 App 合并子进程。
func sampleTopDiskProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawDiskProcess] {
    let estimatedCount = proc_listallpids(nil, 0)
    guard estimatedCount > 0 else { return [] }

    let capacity = Int(estimatedCount) * 2
    var pids = [pid_t](repeating: 0, count: capacity)
    let bufferSizeInBytes = Int32(capacity * MemoryLayout<pid_t>.size)
    let pidCount = Int(proc_listallpids(&pids, bufferSizeInBytes))
    guard pidCount > 0 else { return [] }

    // responsiblePid -> (path, readDelta, writeDelta)
    var groups: [pid_t: (path: String, readDelta: UInt64, writeDelta: UInt64)] = [:]
    groups.reserveCapacity(pidCount)

    var currentSnapshot: [pid_t: (read: UInt64, write: UInt64)] = [:]
    currentSnapshot.reserveCapacity(pidCount)

    for i in 0..<min(pidCount, capacity) {
        let pid = pids[i]
        guard pid > 0 else { continue }

        var rusage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &rusage) { structPtr -> Int32 in
            structPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rawPtr)
            }
        }
        guard result == 0 else { continue }

        let totalRead = rusage.ri_diskio_bytesread
        let totalWrite = rusage.ri_diskio_byteswritten
        currentSnapshot[pid] = (read: totalRead, write: totalWrite)

        // 计算增量
        let prev = previousDiskSnapshot[pid]
        let readDelta = prev.map { totalRead >= $0.read ? totalRead - $0.read : 0 } ?? 0
        let writeDelta = prev.map { totalWrite >= $0.write ? totalWrite - $0.write : 0 } ?? 0

        guard readDelta > 0 || writeDelta > 0 else { continue }

        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid

        if groups[groupKey] == nil {
            groups[groupKey] = (path: executablePath(for: groupKey), readDelta: 0, writeDelta: 0)
        }
        groups[groupKey]?.readDelta += readDelta
        groups[groupKey]?.writeDelta += writeDelta
    }

    previousDiskSnapshot = currentSnapshot

    // 过滤系统进程，生成结果
    var result: [RawDiskProcess] = []
    result.reserveCapacity(groups.count)

    for (groupKey, group) in groups {
        let hostPath = group.path

        if !includeSystemProcesses {
            let isAlwaysVisible = alwaysVisibleSystemAppMarkers.contains { hostPath.contains($0) }
            let isSystem = hostPath.isEmpty || systemProcessPathPrefixes.contains { hostPath.hasPrefix($0) }
            if !isAlwaysVisible, isSystem {
                continue
            }
        }

        let fallbackName = hostPath.isEmpty ? "pid \(groupKey)" : (hostPath as NSString).lastPathComponent
        guard !fallbackName.isEmpty else { continue }

        result.append(RawDiskProcess(
            pid: groupKey,
            path: hostPath,
            fallbackName: fallbackName,
            bytesRead: group.readDelta,
            bytesWritten: group.writeDelta
        ))
    }

    return Array(result.sorted {
        max($0.bytesRead, $0.bytesWritten) > max($1.bytesRead, $1.bytesWritten)
    }.prefix(limit))
}

/// 用 NSRunningApplication(pid:) 为磁盘 I/O 采样结果补齐本地化名与 App 图标。
/// 可在任意线程调用,不依赖 NSWorkspace.shared.runningApplications 遍历。
func enrichDisk(_ rawProcesses: [RawDiskProcess]) -> [TopDiskProcess] {
    return rawProcesses.map { raw in
        let app = NSRunningApplication(processIdentifier: pid_t(raw.pid))

        let name: String
        if let localized = app?.localizedName, !localized.isEmpty {
            name = localized
        } else {
            name = raw.fallbackName
        }

        var icon: NSImage? = app?.icon
        if icon == nil, !raw.path.isEmpty {
            icon = NSWorkspace.shared.icon(forFile: raw.path)
        }
        icon?.size = NSSize(width: 16, height: 16)

        return TopDiskProcess(
            pid: raw.pid, name: name,
            bytesRead: raw.bytesRead, bytesWritten: raw.bytesWritten,
            icon: icon
        )
    }
}
