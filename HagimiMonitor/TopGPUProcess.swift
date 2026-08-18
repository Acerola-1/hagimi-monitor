import AppKit
import Darwin
import Foundation
import IOKit

struct TopGPUProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    /// 采样窗口内的 GPU 占用百分比(累计 GPU 时间增量 / 窗口时长)。
    let gpuUsage: Double
    /// 该进程提交 GPU 工作所用的图形 API(如 Metal)。
    let api: String
    let icon: NSImage?

    var id: pid_t { pid }

    static func == (lhs: TopGPUProcess, rhs: TopGPUProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.gpuUsage == rhs.gpuUsage && lhs.api == rhs.api
    }
}

struct RawGPUProcess {
    let pid: pid_t
    let path: String
    let fallbackName: String
    let gpuUsage: Double
    let api: String
}

/// 每进程累计 GPU 时间(纳秒)快照,用于计算窗口增量。
/// 与 previousDiskSnapshot 同为文件级全局,线程安全依赖 procSampleQueue 的串行性。
private var previousGPUSnapshot: (perPid: [pid_t: UInt64], timestamp: TimeInterval)?

/// AGX 驱动的每进程累计 GPU 时间:IOAccelerator 服务的 user client 子节点
/// (AGXDeviceUserClient)在 AppUsage 属性里按图形 API 记录 accumulatedGPUTime。
/// user client 不在 service plane,IOServiceMatching 匹配不到,须从 IOAccelerator
/// 遍历子节点。纯 IORegistry 属性读取,无 user client open,沙盒下同样可用。
private func gpuTimePerClientPid() -> [pid_t: (gpuTime: UInt64, api: String)] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
        return [:]
    }
    defer { IOObjectRelease(iterator) }

    var result: [pid_t: (gpuTime: UInt64, api: String)] = [:]
    while true {
        let accelerator = IOIteratorNext(iterator)
        guard accelerator != IO_OBJECT_NULL else { break }
        defer { IOObjectRelease(accelerator) }

        var childIterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &childIterator) == KERN_SUCCESS else { continue }
        defer { IOObjectRelease(childIterator) }

        while true {
            let client = IOIteratorNext(childIterator)
            guard client != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(client) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(client, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            guard let creator = dict["IOUserClientCreator"] as? String,
                  creator.hasPrefix("pid "),
                  let pid = pid_t(creator.dropFirst(4).prefix(while: { $0.isNumber })) else { continue }

            var gpuTime: UInt64 = 0
            var api = ""
            if let usage = dict["AppUsage"] as? [[String: Any]] {
                for entry in usage {
                    if let time = (entry["accumulatedGPUTime"] as? NSNumber)?.uint64Value {
                        gpuTime += time
                    }
                    if let name = entry["API"] as? String {
                        api = name
                    }
                }
            }

            // 同一 pid 可持有多个 client,累加合并。
            if let existing = result[pid] {
                result[pid] = (existing.gpuTime + gpuTime, existing.api.isEmpty ? api : existing.api)
            } else {
                result[pid] = (gpuTime, api)
            }
        }
    }
    return result
}

/// 后台采样 GPU 占用最高的 N 个进程。
/// 数据源是 AGX user client 的 accumulatedGPUTime(纳秒累计值),两次采样差分
/// 除以窗口时长即占用率;首次调用只建立基线返回空。按宿主 App 合并子进程。
func sampleTopGPUProcesses(limit: Int = 5, includeSystemProcesses: Bool = false) -> [RawGPUProcess] {
    let current = gpuTimePerClientPid()
    let now = ProcessInfo.processInfo.systemUptime
    defer { previousGPUSnapshot = (current.mapValues { $0.gpuTime }, now) }

    guard let previous = previousGPUSnapshot else { return [] }
    let elapsed = now - previous.timestamp
    guard elapsed > 0.5 else { return [] }

    // responsiblePid -> (path, usageDelta, api)
    var groups: [pid_t: (path: String, gpuTime: UInt64, api: String)] = [:]

    for (pid, entry) in current {
        guard let before = previous.perPid[pid], entry.gpuTime >= before else { continue }
        let delta = entry.gpuTime - before
        guard delta > 0 else { continue }

        let responsiblePid = responsiblePidResolver(pid)
        let groupKey: pid_t = responsiblePid > 0 ? responsiblePid : pid

        if groups[groupKey] == nil {
            groups[groupKey] = (path: executablePath(for: groupKey), gpuTime: 0, api: entry.api)
        }
        groups[groupKey]?.gpuTime += delta
        if groups[groupKey]?.api.isEmpty == true {
            groups[groupKey]?.api = entry.api
        }
    }

    var result: [RawGPUProcess] = []
    result.reserveCapacity(groups.count)

    for (groupKey, group) in groups {
        let usage = Double(group.gpuTime) / (elapsed * 1_000_000_000) * 100
        guard usage > 0.1 else { continue }

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

        result.append(RawGPUProcess(
            pid: groupKey,
            path: hostPath,
            fallbackName: fallbackName,
            gpuUsage: usage,
            api: group.api
        ))
    }

    return Array(result.sorted { $0.gpuUsage > $1.gpuUsage }.prefix(limit))
}

/// 用 NSRunningApplication(pid:) 为 GPU 采样结果补齐本地化名与 App 图标。
/// 与 enrichCPU 同构,可在任意线程调用。
func enrichGPU(_ rawProcesses: [RawGPUProcess]) -> [TopGPUProcess] {
    return rawProcesses.map { raw in
        let app = NSRunningApplication(processIdentifier: pid_t(raw.pid))

        let name: String
        if let localized = app?.localizedName, !localized.isEmpty {
            name = localized
        } else {
            name = raw.fallbackName
        }

        return TopGPUProcess(
            pid: raw.pid,
            name: name,
            gpuUsage: raw.gpuUsage,
            api: raw.api,
            icon: ProcessIconCache.icon(forPID: pid_t(raw.pid), path: raw.path)
        )
    }
}
