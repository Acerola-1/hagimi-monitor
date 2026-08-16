import Darwin
import Foundation
import OSLog
import IOKit

final class CPUSampler: MonitorSampler {
    var kind: MonitorKind { .cpu }

    // mach_host_self() 每次调用都会给当前 task 增加一个对 host port 的 send right，
    // 且从不释放。若在采样循环里反复调用会持续泄漏，累积到阈值被 jetsam 静默 SIGKILL。
    // 缓存为 stored property，进程生命周期内只获取一次。
    private let host = mach_host_self()
    private var previousCPUInfo: host_cpu_load_info?
    /// 逐核 tick 历史,用于计算 P/E 核分组占用(与整机占用同口径的差值法)。
    private var previousPerCoreTicks: [host_cpu_load_info]?
    /// 性能核的逻辑 CPU 编号集合。来自 IODeviceTree 的 cpu 节点(每节点带
    /// cluster-type 与 cpu-id),启动时读一次即可:核心拓扑运行期不变。
    /// 不能按 hw.perflevelN.physicalcpu 切片——Apple Silicon 上 P/E 核的
    /// 逻辑编号顺序并非恒为 P 在前(实测 M4: cpu0-5=E、cpu6-9=P)。
    /// 读不到(Intel 同构/沙盒受限)时为空集合,此时不产出 core-split 指标。
    private let performanceCoreIndices: Set<Int> = readPerformanceCoreIndices()
    #if DISPLAY_CONTROL
    private let smcReader: SMCReader? = SMCReader()
    #endif
    private let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter
    }()

    func sample(previous: MonitorModule?) -> MonitorModule {
        let info = hostCPULoadInfo()
        let metrics: [MonitorMetric]
        let total: Double

        if let info, let previousCPUInfo {
            let userDiff = Double(info.cpu_ticks.0 &- previousCPUInfo.cpu_ticks.0)
            let systemDiff = Double(info.cpu_ticks.1 &- previousCPUInfo.cpu_ticks.1)
            let idleDiff = Double(info.cpu_ticks.2 &- previousCPUInfo.cpu_ticks.2)
            let niceDiff = Double(info.cpu_ticks.3 &- previousCPUInfo.cpu_ticks.3)
            let all = userDiff + systemDiff + idleDiff + niceDiff

            let system = all > 0 ? (systemDiff / all) * 100 : 0
            let user = all > 0 ? ((userDiff + niceDiff) / all) * 100 : 0
            let idle = all > 0 ? (idleDiff / all) * 100 : 100
            total = min(100, max(0, system + user))
            metrics = [
                MonitorMetric(name: "system", value: percent(system), numericValue: system),
                MonitorMetric(name: "user", value: percent(user), numericValue: user),
                MonitorMetric(name: "idle", value: percent(idle), numericValue: idle),
                MonitorMetric(name: "uptime", value: systemUptime())
            ]
        } else {
            total = 0
            metrics = [
                MonitorMetric(name: "system", value: "--"),
                MonitorMetric(name: "user", value: "--"),
                MonitorMetric(name: "idle", value: "--"),
                MonitorMetric(name: "uptime", value: systemUptime())
            ]
        }

        if let info {
            self.previousCPUInfo = info
        }

        var resultMetrics = metrics

        // 热压力(ProcessInfo.thermalState 四档):公开 API,双渠道可用。
        // value 存档位 id(normal/fair/serious/critical),视图层本地化并按 severity 着色;
        // numericValue 存原始 rawValue 供着色判定。
        let thermalState = ProcessInfo.processInfo.thermalState
        let thermalId: String
        switch thermalState {
        case .nominal: thermalId = "normal"
        case .fair: thermalId = "fair"
        case .serious: thermalId = "serious"
        case .critical: thermalId = "critical"
        @unknown default: thermalId = "normal"
        }
        resultMetrics.append(MonitorMetric(name: "thermal-pressure", value: thermalId, numericValue: Double(thermalState.rawValue)))

        // P/E 核分组占用 → 单一指标「P/E 核」:逐核 tick 差值按核心拓扑分组聚合,
        // 展示为「82% / 35%」(P 在前 E 在后);无 E 核的同构拓扑只显 P。
        // 首帧无历史不出指标。
        if let perCore = perCoreLoadInfo() {
            if let previous = previousPerCoreTicks, previous.count == perCore.count {
                let pIndices = performanceCoreIndices.filter { $0 < perCore.count }
                if !pIndices.isEmpty,
                   let perfUsage = groupUsage(pIndices, current: perCore, previous: previous) {
                    let eIndices = Set(0..<perCore.count).subtracting(performanceCoreIndices)
                    let eUsage = eIndices.isEmpty
                        ? nil
                        : groupUsage(eIndices, current: perCore, previous: previous)
                    let value = eUsage.map { "\(percent(perfUsage)) / \(percent($0))" } ?? percent(perfUsage)
                    resultMetrics.append(MonitorMetric(name: "core-split", value: value, numericValue: perfUsage))
                }
            }
            previousPerCoreTicks = perCore
        }

        #if DISPLAY_CONTROL
        let cpuTemp = smcReader?.cpuTemperature()
        let temperatureValue = cpuTemp.map { "\(String(format: "%.0f", $0))°C" } ?? "--"
        resultMetrics.append(MonitorMetric(name: "temperature", value: temperatureValue, numericValue: cpuTemp))
        #endif

        return MonitorModule(
            kind: .cpu,
            value: total,
            summary: percent(total),
            metrics: resultMetrics,
            samples: seedSamples(total)
        )
    }

    private func hostCPULoadInfo() -> host_cpu_load_info? {
        let count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var size = count
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            AppLogger.sampler.error("host_statistics failed with result: \(result)")
            return nil
        }
        return info
    }

    /// 逐核 CPU tick 快照。返回的数组由 vm 分配,读完立即释放,不留悬挂指针。
    private func perCoreLoadInfo() -> [host_cpu_load_info]? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS, let infoArray else {
            return nil
        }
        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(infoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }
        // 每个处理器占 CPU_STATE_MAX 个 integer_t(host_cpu_load_info 恰好四个字段)。
        let entryStride = Int(CPU_STATE_MAX) * MemoryLayout<integer_t>.stride
        var infos: [host_cpu_load_info] = []
        infos.reserveCapacity(Int(cpuCount))
        let base = UnsafeRawPointer(infoArray)
        for index in 0..<Int(cpuCount) {
            infos.append(base.advanced(by: index * entryStride).loadUnaligned(as: host_cpu_load_info.self))
        }
        return infos
    }

    /// 指定核心下标范围的分组占用(%):tick 差值法,与整机占用同口径。
    /// 全部核心无增量(如休眠刚醒)时返 nil 而非 0,避免瞬时假读数。
    private func groupUsage(_ indices: Set<Int>, current: [host_cpu_load_info], previous: [host_cpu_load_info]) -> Double? {
        var totalTicks = 0.0
        var activeTicks = 0.0
        for index in indices where index < current.count && index < previous.count {
            let currentTicks = current[index].cpu_ticks
            let previousTicks = previous[index].cpu_ticks
            let user = Double(currentTicks.0 &- previousTicks.0)
            let system = Double(currentTicks.1 &- previousTicks.1)
            let idle = Double(currentTicks.2 &- previousTicks.2)
            let nice = Double(currentTicks.3 &- previousTicks.3)
            let all = user + system + idle + nice
            guard all > 0 else { continue }
            totalTicks += all
            activeTicks += user + system + nice
        }
        guard totalTicks > 0 else { return nil }
        return min(100, max(0, activeTicks / totalTicks * 100))
    }

    private func systemUptime() -> String {
        guard let bootDate = bootDate() else {
            return "--"
        }

        return uptimeFormatter.string(from: bootDate, to: Date()) ?? "--"
    }

    private func bootDate() -> Date? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        let result = sysctl(&mib, UInt32(mib.count), &bootTime, &size, nil, 0)
        guard result == 0, bootTime.tv_sec > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000)
    }
}

/// 读取 IODeviceTree 的性能核逻辑 CPU 编号集合。每个 cpu 节点带 cluster-type
/// (Data,首字节 'P'/'E')与 cpu-id(Data,小端 UInt32 逻辑编号)。host_processor_info
/// 数组索引即逻辑编号,但 P/E 核的编号顺序并非恒为 P 在前,故必须按每核
/// cluster-type 归组而非切片。失败或 Intel 同构(无 P 簇)时返回空集合。
private func readPerformanceCoreIndices() -> Set<Int> {
    var indices = Set<Int>()
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator) == KERN_SUCCESS else {
        return indices
    }
    defer { IOObjectRelease(iterator) }
    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { break }
        defer { IOObjectRelease(service) }
        // 仅 CPU 节点带 cluster-type,其余 platform 设备读属性为 nil,快速跳过。
        guard let cluster = IORegistryEntryCreateCFProperty(service, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data,
            let cpuID = IORegistryEntryCreateCFProperty(service, "cpu-id" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data,
            cluster.first == 0x50, // 'P'
            cpuID.count >= MemoryLayout<UInt32>.size else {
            continue
        }
        // cpu-id 为小端 UInt32 逻辑编号(实测 cpu0..9 依次 0x00..0x09 小端)。
        let logical = cpuID.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        indices.insert(Int(logical))
    }
    return indices
}
