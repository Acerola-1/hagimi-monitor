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

/// nettop 子进程采样的超时阈值。nettop 在异常网络栈/僵尸状态下可能挂起不退出,
/// 若无防护会永久堵死串行采样队列(面板/统计的网络 TOP 全部停摆)。
private let nettopSampleTimeout: TimeInterval = 8

/// 网络差分游标:自持上拍字节快照,各使用方(面板 2s、统计 60s)各用独立游标,
/// 互不截断对方的差分窗口。线程安全依赖每个游标只被 nettopQueue 一条串行队列读写。
final class NetworkDeltaCursor {
    private var previousSnapshot: [pid_t: NetworkSnapshotEntry] = [:]
    private var previousTime: Date?

    /// 后台采样网络流量最高的 N 个进程。
    /// 使用 `nettop -P -L 1 -n` 获取每个进程的上下行字节，维护快照计算速率（字节/秒）。
    /// 返回的 RawNetworkProcess 不含图标——图标由主线程 enrichNetwork(_:) 补齐。
    func sample(limit: Int, includeSystemProcesses: Bool) -> [RawNetworkProcess] {
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

        // 计算增量与速率（字节/秒）。
        //
        // `dt` 必须显式校验,不能只靠「首拍没有 prev」来保证它为正:`Date()` 是**墙钟**,
        // 同一瞬间的两次采样会得到 dt == 0(`x / 0` → `+inf`),墙钟回拨会得到负值——
        // 两种情况下 `UInt64(Double)` 都**直接 trap**(实测在测试宿主里稳定复现:
        // `_assertionFailure` @ TopNetworkProcess.swift:129)。
        let now = Date()
        let dt = previousTime.map { now.timeIntervalSince($0) } ?? 0
        var perProcessRate: [pid_t: (download: UInt64, upload: UInt64)] = [:]

        if dt > 0 {
            for (pid, current) in currentList {
                // 首次采样没有基线,跳过
                guard let prev = previousSnapshot[pid] else { continue }
                let downloadDelta = current.download >= prev.download ? current.download - prev.download : 0
                let uploadDelta = current.upload >= prev.upload ? current.upload - prev.upload : 0
                guard downloadDelta > 0 || uploadDelta > 0 else { continue }
                perProcessRate[pid] = (rate(downloadDelta, over: dt), rate(uploadDelta, over: dt))
            }
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

        previousSnapshot = currentList
        previousTime = now

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

    /// 字节增量 → 速率(字节/秒),与 Stats 等行业惯例对齐。
    ///
    /// 极小的 dt 也会让商超过 UInt64 上限,这里统一夹住——不给 `UInt64(_:)` 留 trap 的机会,
    /// 返回 0 表示这一项本轮不计入(调用方随后还有 `downloadDelta > 0` 的门)。
    private func rate(_ delta: UInt64, over dt: TimeInterval) -> UInt64 {
        let value = Double(delta) / dt
        guard value.isFinite, value > 0 else { return 0 }
        return value < Double(UInt64.max) ? UInt64(value) : UInt64.max
    }
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
