import AppKit
import Darwin
import Foundation

struct TopNetworkProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 自上次采样以来下载的字节增量。
    let download: Int
    /// 自上次采样以来上传的字节增量。
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

/// 后台采样网络流量最高的 N 个进程。
/// 使用 `nettop -P -L 1 -n` 获取每个进程的上下行字节，维护快照计算增量。
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
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    outputPipe.fileHandleForReading.closeFile()
    task.waitUntilExit()

    guard task.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8), !output.isEmpty else {
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

    // 计算增量
    var result: [RawNetworkProcess] = []

    for (pid, current) in currentList {
        let prev = previousNetworkSnapshot[pid]
        let downloadDelta = prev.map { current.download >= $0.download ? current.download - $0.download : 0 } ?? 0
        let uploadDelta = prev.map { current.upload >= $0.upload ? current.upload - $0.upload : 0 } ?? 0

        // 首次采样没有增量，跳过
        if prev == nil { continue }
        guard downloadDelta > 0 || uploadDelta > 0 else { continue }

        // 系统进程过滤
        if !includeSystemProcesses {
            let path = executablePath(for: pid)
            let isAlwaysVisible = alwaysVisibleSystemAppMarkers.contains { path.contains($0) }
            let isSystem = path.isEmpty || systemProcessPathPrefixes.contains { path.hasPrefix($0) }
            if !isAlwaysVisible, isSystem {
                continue
            }
        }

        let name = current.rawName.isEmpty ? "pid \(pid)" : current.rawName
        result.append(RawNetworkProcess(
            pid: pid, name: name,
            download: downloadDelta, upload: uploadDelta
        ))
    }

    previousNetworkSnapshot = currentList

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

/// 【必须主线程调用】用 NSWorkspace 为网络采样结果补齐本地化名与 App 图标。
@MainActor
func enrichNetwork(_ rawProcesses: [RawNetworkProcess]) -> [TopNetworkProcess] {
    let appsByPid = Dictionary(
        NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    return rawProcesses.map { raw in
        let app = appsByPid[raw.pid]

        let name: String
        if let localized = app?.localizedName, !localized.isEmpty {
            name = localized
        } else {
            name = raw.name
        }

        var icon: NSImage? = app?.icon
        if icon == nil {
            let path = executablePath(for: raw.pid)
            if !path.isEmpty {
                icon = NSWorkspace.shared.icon(forFile: path)
            }
        }
        icon?.size = NSSize(width: 16, height: 16)

        return TopNetworkProcess(
            pid: raw.pid, name: name,
            download: Int(clamping: raw.download), upload: Int(clamping: raw.upload),
            icon: icon
        )
    }
}
