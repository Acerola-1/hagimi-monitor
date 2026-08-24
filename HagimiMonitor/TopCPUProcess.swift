import AppKit
import Darwin
import Foundation

struct TopCPUProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 进程 CPU 占用百分比。
    let cpuUsage: Double
    let icon: NSImage?
    /// 是否正通过 Rosetta 转译运行(Intel 二进制)。macOS 28 起 Intel 应用将无法运行,
    /// 面板 TOP 进程列表据此打角标并汇总提醒。
    let translated: Bool

    var id: pid_t { pid }

    static func == (lhs: TopCPUProcess, rhs: TopCPUProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.cpuUsage == rhs.cpuUsage
            && lhs.translated == rhs.translated
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
#if DIRECT_DISTRIBUTION
private let psLineRegex = try! NSRegularExpression(pattern: "^(\\d+)\\s+([0-9,.]+)\\s+(.+)$")

/// ps 子进程采样的超时阈值。ps 在极端系统状态下可能挂起不退出,若无防护会永久
/// 堵死 procSampleQueue,连带内存/CPU/GPU/磁盘四类 TOP 列表全部停摆。
/// 参照同仓 system_profiler 探针(蓝牙/SMART/充电上限)的信号量超时 + terminate 模式。
private let psSampleTimeout: TimeInterval = 8
#endif

/// 后台采样 CPU 占用最高的 N 个进程。
/// 直连版使用 `ps -Aceo pid,pcpu,comm -r` 获取每个进程的 CPU%(ps 为平台二进制,
/// 能读到 root 进程的衰减 CPU 值);沙盒版 spawn ps 被拒绝,改用
/// `proc_pidinfo(PROC_PIDTASKINFO)` 累计 CPU 时间在两次采样间的差分。两者均按
/// 宿主 App 合并子进程。
func sampleTopCPUProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawCPUProcess] {
    #if DIRECT_DISTRIBUTION
    return sampleTopCPUViaPS(limit: limit, includeSystemProcesses: includeSystemProcesses)
    #else
    return sampleTopCPUViaTaskInfoDelta(limit: limit, includeSystemProcesses: includeSystemProcesses)
    #endif
}

/// 把逐进程 CPU% 按宿主 App 合并、过滤系统进程、排序截断为 TOP N。
/// 两条数据源(ps / TASKINFO 差分)共用这段归并逻辑,保证两渠道榜单口径一致。
private func assembleTopCPU(perProcessCPU: [pid_t: Double], limit: Int, includeSystemProcesses: Bool) -> [RawCPUProcess] {
    // 按 responsible pid 合并,首次遇到分组时立即捕获宿主路径
    var groups: [pid_t: (path: String, totalCPU: Double)] = [:]
    groups.reserveCapacity(perProcessCPU.count)

    for (pid, cpuPercent) in perProcessCPU {
        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid

        if groups[groupKey] == nil {
            groups[groupKey] = (path: executablePath(for: groupKey), totalCPU: 0)
        }
        groups[groupKey]?.totalCPU += cpuPercent
    }

    // 过滤系统进程,生成结果
    var result: [RawCPUProcess] = []
    result.reserveCapacity(groups.count)

    for (groupKey, group) in groups {
        let hostPath = group.path

        if isSystemProcessPath(hostPath, includeSystemProcesses: includeSystemProcesses) {
            continue
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

#if DIRECT_DISTRIBUTION
/// 直连版 CPU 采样:解析 ps 输出,得到逐进程 CPU% 后交给共享归并逻辑。
private func sampleTopCPUViaPS(limit: Int, includeSystemProcesses: Bool) -> [RawCPUProcess] {
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

    // 读输出放后台线程,信号量等待,超时终止进程并放弃本次结果(保留上一次列表)。
    nonisolated(unsafe) var data: Data?
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        data = pipe.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }
    if done.wait(timeout: .now() + psSampleTimeout) == .timedOut {
        task.terminate()
        return []
    }
    task.waitUntilExit()
    let outputData = data ?? Data()
    pipe.fileHandleForReading.closeFile()

    guard task.terminationStatus == 0,
          let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
        return []
    }

    // ps 输出格式: "  PID  CPU COMMAND"（header）+ "  123  1.5 /path/to/cmd"
    var perProcess: [pid_t: Double] = [:]
    var lineIndex = 0

    output.enumerateLines { line, _ in
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
        perProcess[pid] = cpuPercent
    }

    return assembleTopCPU(perProcessCPU: perProcess, limit: limit, includeSystemProcesses: includeSystemProcesses)
}
#else
/// TASKINFO 累计值快照:pid -> (user 时间, system 时间),单位 mach ticks。
/// 跨采样周期持久,与磁盘/网络快照同为文件级全局状态,线程安全依赖
/// 只被 procSampleQueue 一条串行队列读写。
private var previousCPUSnapshot: [pid_t: (user: UInt64, system: UInt64)] = [:]
private var previousCPUSnapshotTime: Date?

/// mach ticks -> 纳秒的换算系数(Apple Silicon 上为 125/3,Intel 上为 1)。
private let machTimeToNanos: Double = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(timebase.numer) / Double(timebase.denom)
}()

/// 沙盒版 CPU 采样:枚举全部进程并读 TASKINFO 累计 CPU 时间,与上一周期快照差分
/// 得到窗口内占用率。TASKINFO 受内核权限检查只放行同用户进程,root 守护进程
/// 不进入榜单(与沙盒内任何第三方工具的能力边界一致)。首采无基线时返回空,
/// 由面板预热/补采链路在下一拍补上数据。
private func sampleTopCPUViaTaskInfoDelta(limit: Int, includeSystemProcesses: Bool) -> [RawCPUProcess] {
    let snapshot = taskInfoCPUSnapshot()
    let now = Date()
    defer {
        previousCPUSnapshot = snapshot
        previousCPUSnapshotTime = now
    }

    guard let previousTime = previousCPUSnapshotTime else { return [] }
    let wall = now.timeIntervalSince(previousTime)
    // 窗口过短(如预热与展开几乎同时发生)差分噪声过大,延后一拍再出数。
    guard wall > 0.1 else { return [] }

    var perProcess: [pid_t: Double] = [:]
    perProcess.reserveCapacity(snapshot.count)

    for (pid, current) in snapshot {
        guard let previous = previousCPUSnapshot[pid],
              current.user >= previous.user, current.system >= previous.system else { continue }
        // pid 复用时新进程累计值可能小于旧快照,饱和相减归零即可。
        let ticks = (current.user - previous.user) + (current.system - previous.system)
        let cpuPercent = Double(ticks) * machTimeToNanos / (wall * 1_000_000_000) * 100
        guard cpuPercent > 0 else { continue }
        perProcess[pid] = cpuPercent
    }

    return assembleTopCPU(perProcessCPU: perProcess, limit: limit, includeSystemProcesses: includeSystemProcesses)
}

/// 枚举全部进程并读取各自的 TASKINFO 累计 CPU 时间。
/// 枚举走 sysctl(KERN_PROC_ALL):双渠道均放行,且一次调用即得全部 pid。
private func taskInfoCPUSnapshot() -> [pid_t: (user: UInt64, system: UInt64)] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [:] }

    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [:] }

    let count = size / MemoryLayout<kinfo_proc>.stride
    var snapshot: [pid_t: (user: UInt64, system: UInt64)] = [:]
    snapshot.reserveCapacity(count)

    buffer.withUnsafeBytes { raw in
        let procs = raw.bindMemory(to: kinfo_proc.self)
        for i in 0..<count {
            let pid = procs[i].kp_proc.p_pid
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            guard result > 0 else { continue }
            snapshot[pid] = (user: taskInfo.pti_total_user, system: taskInfo.pti_total_system)
        }
    }

    return snapshot
}
#endif

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

        let icon = ProcessIconCache.icon(forPID: pid_t(raw.pid), path: raw.path)

        return TopCPUProcess(
            pid: raw.pid,
            name: name,
            cpuUsage: raw.cpuUsage,
            icon: icon,
            translated: isTranslatedProcess(raw.pid)
        )
    }
}

/// 查询指定进程是否正通过 Rosetta 转译运行。
/// 走官方推荐的 `sysctl.proc_translated`(传入 pid 作为输入参数),仅查询不干预,
/// 沙盒下同样可用;失败/不支持一律视为非转译。
func isTranslatedProcess(_ pid: pid_t) -> Bool {
    #if arch(arm64)
    var translated: Int32 = 0
    var size = MemoryLayout<Int32>.size
    var pidValue = pid
    let result = sysctlbyname(
        "sysctl.proc_translated",
        &translated,
        &size,
        &pidValue,
        MemoryLayout<pid_t>.size
    )
    return result == 0 && translated == 1
    #else
    _ = pid
    return false
    #endif
}
