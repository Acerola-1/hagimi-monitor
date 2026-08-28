import AppKit
import Darwin
import Foundation

struct TopNetworkProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 下载速率（字节/秒）。
    let download: Int
    /// 上传速率（字节/秒）。
    let upload: Int
    let icon: NSImage?

    var id: Int { Int(pid) }

    static func == (lhs: TopNetworkProcess, rhs: TopNetworkProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.download == rhs.download && lhs.upload == rhs.upload
    }
}

struct RawNetworkProcess {
    let pid: pid_t
    let name: String
    /// 宿主可执行文件路径(采样时捕获,enrich 复用——避免每行重复 executablePath 系统调用,
    /// 与 CPU/内存/GPU/磁盘四类 Raw*Process 的 path 字段口径一致)。
    let path: String
    let download: UInt64
    let upload: UInt64
}

/// 网络快照条目。
private struct NetworkSnapshotEntry {
    let rawName: String
    let download: UInt64
    let upload: UInt64
}

/// 网络快照，用于计算增量。
private var previousNetworkSnapshot: [pid_t: NetworkSnapshotEntry] = [:]
private var previousNetworkSnapshotTime: Date?

/// 基线年龄(秒);无基线返回无穷大。展开时据此决定复用还是弃掉重建。
func networkProcessBaselineAge() -> TimeInterval {
    previousNetworkSnapshotTime.map { Date().timeIntervalSince($0) } ?? .infinity
}

/// 弃掉基线:下次采样重建,首拍返空。基线陈旧时调用,避免首帧拿到
/// 「开面板至今」的长窗口均值。
func resetNetworkProcessBaseline() {
    previousNetworkSnapshot = [:]
    previousNetworkSnapshotTime = nil
}

/// nettop 子进程采样的超时阈值。nettop 在异常网络栈/僵尸状态下可能挂起不退出,
/// 若无防护会永久堵死串行采样队列(面板/统计/展开补采全部停摆)。
private let nettopSampleTimeout: TimeInterval = 8

/// 后台采样网络流量最高的 N 个进程。
/// 使用 `nettop -P -L 1 -n` 获取每个进程的上下行字节，维护快照计算速率（字节/秒）。
/// 返回的 RawNetworkProcess 不含图标——图标由主线程 enrichNetwork(_:) 补齐。
func sampleTopNetworkProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawNetworkProcess] {
    let task = Process()
    task.launchPath = "/usr/bin/nettop"
    task.arguments = [
        "-P", "-L", "1", "-n", "-k",
        "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"
    ]
    task.environment = ["NSUnbufferedIO": "YES", "LC_ALL": "en_US.UTF-8"]

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    task.standardInput = inputPipe
    task.standardOutput = outputPipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
    } catch {
        return []
    }

    inputPipe.fileHandleForWriting.closeFile()
    // 读输出放后台线程,信号量等待,超时终止进程并放弃本次结果(保留上一次列表)。
    nonisolated(unsafe) var data: Data?
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }
    if done.wait(timeout: .now() + nettopSampleTimeout) == .timedOut {
        task.terminate()
        return []
    }
    task.waitUntilExit()
    let outputData = data ?? Data()
    outputPipe.fileHandleForReading.closeFile()

    guard task.terminationStatus == 0,
          let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
        return []
    }

    // 解析 nettop CSV 输出
    var currentList: [pid_t: NetworkSnapshotEntry] = [:]
    var firstLine = true

    output.enumerateLines { line, _ in
        if firstLine { firstLine = false; return }

        let parts = line.split(separator: ",")
        guard parts.count >= 3 else { return }

        // 进程名格式: "com.apple.Safari.12345" 最后一段是 pid
        let nameParts = parts[0].split(separator: ".")
        guard let lastPart = nameParts.last, let pid = pid_t(lastPart) else { return }

        let download = UInt64(parts[1]) ?? 0
        let upload = UInt64(parts[2]) ?? 0

        let rawName = nameParts.dropLast().joined(separator: ".")
        currentList[pid] = NetworkSnapshotEntry(rawName: rawName, download: download, upload: upload)
    }

    // 计算增量与速率（字节/秒）。dt 在此路径上必然 > 0（首次采样已被 continue 拦截），无需额外下限保护。
    let now = Date()
    let dt = previousNetworkSnapshotTime.map { now.timeIntervalSince($0) } ?? 0
    var perProcessRate: [pid_t: (download: UInt64, upload: UInt64)] = [:]

    for (pid, current) in currentList {
        let prev = previousNetworkSnapshot[pid]
        let downloadDelta = prev.map { current.download >= $0.download ? current.download - $0.download : 0 } ?? 0
        let uploadDelta = prev.map { current.upload >= $0.upload ? current.upload - $0.upload : 0 } ?? 0

        // 首次采样没有增量，跳过
        if prev == nil { continue }

        // 将累计字节增量转换为速率（字节/秒），与 Stats 等行业惯例对齐
        let downloadRate = UInt64(Double(downloadDelta) / dt)
        let uploadRate = UInt64(Double(uploadDelta) / dt)
        guard downloadDelta > 0 || uploadDelta > 0 else { continue }
        perProcessRate[pid] = (downloadRate, uploadRate)
    }

    // 按 responsible pid 归并:助手进程(浏览器渲染进程、各类 Helper)的流量并入宿主
    // 应用,与 CPU/内存/GPU/磁盘四类 TOP 列表口径一致——否则 Safari 的 WebContent 子进程
    // 会逐条单列,真实流量被拆散到截断线以下,宿主应用可能不进榜单。
    var groups: [pid_t: (name: String, download: UInt64, upload: UInt64)] = [:]
    for (pid, rate) in perProcessRate {
        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid
        if groups[groupKey] == nil {
            groups[groupKey] = (name: currentList[groupKey]?.rawName ?? "", download: 0, upload: 0)
        }
        groups[groupKey]?.download += rate.download
        groups[groupKey]?.upload += rate.upload
    }

    // 系统进程过滤 + 生成结果
    var result: [RawNetworkProcess] = []
    result.reserveCapacity(groups.count)

    for (groupKey, group) in groups {
        let path = executablePath(for: groupKey)
        if isSystemProcessPath(path, includeSystemProcesses: includeSystemProcesses) {
            continue
        }

        let name = group.name.isEmpty ? "pid \(groupKey)" : group.name
        result.append(RawNetworkProcess(
            pid: groupKey, name: name, path: path,
            download: group.download, upload: group.upload
        ))
    }

    previousNetworkSnapshot = currentList
    previousNetworkSnapshotTime = now

    // 排序: max(download, upload) 降序
    return Array(result.sorted {
        let firstMax = max($0.download, $0.upload)
        let secondMax = max($1.download, $1.upload)
        if firstMax == secondMax {
            return min($0.download, $0.upload) > min($1.download, $1.upload)
        }
        return firstMax > secondMax
    }.prefix(limit))
}

/// 用 NSRunningApplication(pid:) 为网络采样结果补齐本地化名与 App 图标。
/// 可在任意线程调用,不依赖 NSWorkspace.shared.runningApplications 遍历。
func enrichNetwork(_ rawProcesses: [RawNetworkProcess]) -> [TopNetworkProcess] {
    return rawProcesses.map { raw in
        let app = NSRunningApplication(processIdentifier: pid_t(raw.pid))

        let name: String
        if let localized = app?.localizedName, !localized.isEmpty {
            name = localized
        } else {
            name = raw.name
        }

        let icon = ProcessIconCache.icon(forPID: pid_t(raw.pid), path: raw.path)

        return TopNetworkProcess(
            pid: raw.pid, name: name,
            download: Int(clamping: raw.download), upload: Int(clamping: raw.upload),
            icon: icon
        )
    }
}
