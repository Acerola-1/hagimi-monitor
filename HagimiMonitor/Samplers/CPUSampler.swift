import Darwin
import Foundation
import OSLog
import IOKit

/// 采样器由 SystemMonitorSampler 持有并在串行采样循环中调用，内部状态单线程顺序更新。
nonisolated final class CPUSampler: MonitorSampler, @unchecked Sendable {
    var kind: MonitorKind { .cpu }

    // mach_host_self() 每次调用都会给当前 task 增加一个对 host port 的 send right，
    // 且从不释放。若在采样循环里反复调用会持续泄漏，累积到阈值被 jetsam 静默 SIGKILL。
    // 缓存为 stored property，进程生命周期内只获取一次。
    private let host = mach_host_self()
    private var previousCPUInfo: host_cpu_load_info?
    /// 逐核 tick 历史,用于计算 P/E 核分组占用(与整机占用同口径的差值法)。
    private var previousPerCoreTicks: [host_cpu_load_info]?
    /// 按核心类别划分的逻辑 CPU 编号集合。来自 IODeviceTree 的 cpu 节点
    /// (每节点带 cluster-type 与 cpu-id),启动时读一次即可:核心拓扑运行期不变。
    /// 不能按 hw.perflevelN.physicalcpu 切片——Apple Silicon 上各核类别的
    /// 逻辑编号顺序并非恒为高性能核在前(实测 M4: cpu0-5=E、cpu6-9=P)。
    /// 读不到(Intel 同构/沙盒受限)时 super/performance 均为空集合,
    /// 此时与旧契约一致:不产出 core-split 指标。
    private let coreClusters: CPUCoreClusters = readCoreClusters()
    /// 性能及更强的逻辑 CPU 编号集合(S+P 或仅 P):core-split 指标的
    /// 高占用组判定与逐核类别着色共用。
    private var performanceCoreIndices: Set<Int> {
        coreClusters.superCore.union(coreClusters.performance)
    }
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
        var metrics: [MonitorMetric]
        let total: Double
        var cpuCoreDetail: CPUCoreDetail?

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
                MonitorMetric(name: "system", value: percent(system), numericValue: system, unit: "%"),
                MonitorMetric(name: "user", value: percent(user), numericValue: user, unit: "%"),
                MonitorMetric(name: "idle", value: percent(idle), numericValue: idle, unit: "%"),
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

        // 进程计数无差分依赖,首帧即可出数;读不到时不出该指标。
        if let count = processCount() {
            metrics.append(MonitorMetric(name: "process-count", value: String(count), numericValue: Double(count)))
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
                // S/P/E 三组同帧聚合:超核组仅在拓扑真实标出独立簇时出现,
                // 双类芯片(M1–M4 及仅两组的 M5/M6)维持 P/E 两组不变。
                let pIndices = coreClusters.performance.filter { $0 < perCore.count }
                let sIndices = coreClusters.superCore.filter { $0 < perCore.count }
                let highIndices = pIndices.union(sIndices)
                if !highIndices.isEmpty,
                   let perfUsage = groupUsage(highIndices, current: perCore, previous: previous) {
                    let eIndices = Set(0..<perCore.count).subtracting(highIndices)
                    let eUsage = eIndices.isEmpty
                        ? nil
                        : groupUsage(eIndices, current: perCore, previous: previous)
                    let superUsage = sIndices.isEmpty
                        ? nil
                        : groupUsage(sIndices, current: perCore, previous: previous)
                    // core-split 值保持「高占用组在前,能效组在后」;三组并存时
                    // 超核并入前段文本,逐核环形图与分组占用行再细看 S/P 差异。
                    let highText = superUsage.map { "\(percent($0)) / \(percent(perfUsage))" } ?? percent(perfUsage)
                    let value = eUsage.map { "\(highText) / \(percent($0))" } ?? highText
                    resultMetrics.append(MonitorMetric(name: "core-split", value: value, numericValue: perfUsage))
                    // 逐核负载与分组占用同帧产出:环形图与分组数值同源,
                    // 保证两行展示的口径一致。
                    let cores = perCore.indices.map { index in
                        CPUCoreLoad(
                            index: index,
                            usage: coreUsage(at: index, current: perCore, previous: previous),
                            kind: cpuCoreKind(at: index, clusters: coreClusters)
                        )
                    }
                    cpuCoreDetail = CPUCoreDetail(
                        cores: cores,
                        performanceUsage: perfUsage,
                        efficiencyUsage: eUsage,
                        superUsage: superUsage
                    )
                }
            }
            previousPerCoreTicks = perCore
        }

        #if DISPLAY_CONTROL
        let cpuTemp = smcReader?.cpuTemperature()
        let temperatureValue = cpuTemp.map { "\(String(format: "%.0f", $0))°C" } ?? "--"
        resultMetrics.append(MonitorMetric(name: "temperature", value: temperatureValue, numericValue: cpuTemp, unit: "°C"))
        #endif

        return MonitorModule(
            kind: .cpu,
            value: total,
            summary: percent(total),
            metrics: resultMetrics,
            samples: seedSamples(total),
            cpuCoreDetail: cpuCoreDetail
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

    /// 指定单核的占用(%):tick 差值法,与整机占用同口径。
    /// 无增量(如休眠刚醒)返 0,环形图表现为空环。
    private func coreUsage(at index: Int, current: [host_cpu_load_info], previous: [host_cpu_load_info]) -> Double {
        guard index < current.count, index < previous.count else { return 0 }
        let currentTicks = current[index].cpu_ticks
        let previousTicks = previous[index].cpu_ticks
        let user = Double(currentTicks.0 &- previousTicks.0)
        let system = Double(currentTicks.1 &- previousTicks.1)
        let idle = Double(currentTicks.2 &- previousTicks.2)
        let nice = Double(currentTicks.3 &- previousTicks.3)
        let all = user + system + idle + nice
        guard all > 0 else { return 0 }
        return min(100, max(0, (user + system + nice) / all * 100))
    }

    /// 系统进程总数:sysctl(KERN_PROC_ALL) 枚举计数,沙盒内放行
    /// (proc_listallpids 依赖的 process-info 操作在沙盒下被策略拒绝)。
    /// 首查拿所需缓冲区大小,两次调用间进程数可能波动,以实际填入的
    /// size 为准;pid ≤ 0 的空槽不计入。
    private func processCount() -> Int? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return nil }

        let slots = size / MemoryLayout<kinfo_proc>.stride
        var count = 0
        buffer.withUnsafeBytes { raw in
            let procs = raw.bindMemory(to: kinfo_proc.self)
            for i in 0..<slots where procs[i].kp_proc.p_pid > 0 {
                count += 1
            }
        }
        return count
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

/// 单个核心的类别判定:按所在簇的字母归类。
nonisolated func cpuCoreKind(at index: Int, clusters: CPUCoreClusters) -> CPUCoreKind {
    if clusters.superCore.contains(index) { return .superCore }
    if clusters.performance.contains(index) { return .performance }
    return .efficiency
}

/// IODeviceTree 簇字母 → 面板核心类别的归类规则。
/// Apple 的 cluster-type 字母与市场名称不同步(实测随代际演变):
/// M1–M4 为 P(性能)/E(能效)两类;M5 起顶级核在 IORegistry 标为
/// 独立簇字母——M5 Pro/Max 实测为 P/M/E 三簇,P 为超核、M 为性能核
/// (hwloc #839,Apple 开发者生态工程团队提交)。因此不能把任一字母
/// 固定映射为"性能核",须按字母强弱序自适应(弱 → 强):
/// E < M < P < S。
/// - E → 能效核
/// - M → 性能核(M5 代际性能簇,仅与 P 并存出现)
/// - P → 无更强字母时为超核,与 S 并存时降为性能核
/// - S → 超核(预留:若后续代际使用独立 S 簇)
/// - 未知字母 → 归入高占用组,避免新字母把核误划进能效组拉低读数
/// 归类仅依赖字母组合,不依赖芯片型号清单,新代际无需改码。
nonisolated struct CPUCoreClusters: Sendable, Equatable {
    var superCore: Set<Int> = []
    var performance: Set<Int> = []
    var efficiency: Set<Int> = []

    /// 从「逻辑编号 → 簇字母」映射构建归类结果。
    init(logicalClusters: [Int: Character]) {
        let letters = Set(logicalClusters.values)
        for (logical, letter) in logicalClusters {
            switch letter {
            case "E":
                efficiency.insert(logical)
            case "M":
                performance.insert(logical)
            case "S":
                superCore.insert(logical)
            case "P":
                // M5 Pro/Max:P 簇与 M 簇并存,P 是超核、M 为性能核
                // (hwloc #839);S 在场时 S 才是顶级,P 降入性能组;
                // M1–M4 及双簇代际:M/S 均缺席,P 就是常规性能核。
                if letters.contains("M") {
                    superCore.insert(logical)
                } else {
                    performance.insert(logical)
                }
            default:
                // 未知字母按 Apple 官方 perflevel 语义处理:非 E 即
                // 归入高占用组,避免新字母把核误划进能效组拉低读数。
                performance.insert(logical)
            }
        }
    }

    init() {}
}

/// 读取 IODeviceTree 全部 CPU 节点的簇归属。每个 cpu 节点带 cluster-type
/// (Data,单字母)与 cpu-id(Data,小端 UInt32 逻辑编号),host_processor_info
/// 数组索引即逻辑编号。失败或 Intel 同构(无簇标注)时返回空归类,
/// 采样侧维持旧契约:不产出 core-split 指标。
nonisolated func readCoreClusters() -> CPUCoreClusters {
    var logicalClusters: [Int: Character] = [:]
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator) == KERN_SUCCESS else {
        return CPUCoreClusters()
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
            let letter = cluster.first.map({ Character(Unicode.Scalar($0)) }),
            cpuID.count >= MemoryLayout<UInt32>.size else {
            continue
        }
        // cpu-id 为小端 UInt32 逻辑编号(实测 cpu0..9 依次 0x00..0x09 小端)。
        let logical = cpuID.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        logicalClusters[Int(logical)] = letter
    }
    return CPUCoreClusters(logicalClusters: logicalClusters)
}
