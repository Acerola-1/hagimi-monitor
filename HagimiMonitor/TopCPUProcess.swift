import AppKit
import Darwin
import Foundation

struct TopCPUProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 进程 CPU 占用百分比。
    let cpuUsage: Double
    let icon: NSImage?

    var id: pid_t { pid }

    static func == (lhs: TopCPUProcess, rhs: TopCPUProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.cpuUsage == rhs.cpuUsage
    }
}

struct RawCPUProcess {
    let pid: pid_t
    let path: String
    let fallbackName: String
    let cpuUsage: Double
}

/// ps 输出行的解析正则,提取行首 pid、紧跟的 cpu%。整个采样周期只编译一次,
/// 避免在 enumerateLines 逐行闭包里为每个进程重新编译同一个 pattern。
private let psLineRegex = try! NSRegularExpression(pattern: "^(\\d+)\\s+([0-9,.]+)\\s+(.+)$")

/// 后台采样 CPU 占用最高的 N 个进程。
/// 使用 `ps -Aceo pid,pcpu,comm -r` 获取每个进程的 CPU%,按宿主 App 合并子进程。
func sampleTopCPUProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawCPUProcess] {
    let task = Process()
    task.launchPath = "/bin/ps"
    task.arguments = ["-Aceo pid,pcpu,comm", "-r"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    pipe.fileHandleForReading.closeFile()
    task.waitUntilExit()

    guard task.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8), !output.isEmpty else {
        return []
    }

    // 解析 ps 输出，按 responsible pid 合并
    // ps 输出格式: "  PID  CPU COMMAND"（header）+ "  123  1.5 /path/to/cmd"
    var groups: [pid_t: (path: String, totalCPU: Double)] = [:]
    var lineIndex = 0

    output.enumerateLines { line, stop in
        lineIndex += 1
        if lineIndex == 1 { return } // 跳过 header

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // 用正则提取: pid（行首数字）、cpu%（紧跟的数字）
        guard let match = psLineRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return
        }

        guard let pidRange = Range(match.range(at: 1), in: trimmed),
              let usageRange = Range(match.range(at: 2), in: trimmed),
              let pid = pid_t(trimmed[pidRange]) else { return }

        let cpuPercent = Double(trimmed[usageRange].replacingOccurrences(of: ",", with: ".")) ?? 0
        guard cpuPercent > 0 else { return }

        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid

        if groups[groupKey] == nil {
            groups[groupKey] = (path: executablePath(for: groupKey), totalCPU: 0)
        }
        groups[groupKey]?.totalCPU += cpuPercent
    }

    // 过滤系统进程，生成结果
    var result: [RawCPUProcess] = []
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

        result.append(RawCPUProcess(
            pid: groupKey,
            path: hostPath,
            fallbackName: fallbackName,
            cpuUsage: group.totalCPU
        ))
    }

    return Array(result.sorted { $0.cpuUsage > $1.cpuUsage }.prefix(limit))
}

/// 用 NSRunningApplication(pid:) 为 CPU 采样结果补齐本地化名与 App 图标。
/// 可在任意线程调用,不依赖 NSWorkspace.shared.runningApplications 遍历。
func enrichCPU(_ rawProcesses: [RawCPUProcess]) -> [TopCPUProcess] {
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

        return TopCPUProcess(pid: raw.pid, name: name, cpuUsage: raw.cpuUsage, icon: icon)
    }
}
