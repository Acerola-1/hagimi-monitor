import Darwin
import Foundation
import IOKit
import IOKit.ps

@_silgen_name("memorystatus_get_level")
private func memorystatus_get_level(_ level: UInt64) -> Int32

struct SystemMonitorSnapshot {
    var modules: [MonitorModule]
}

final class SystemMonitorSampler {
    private var previousCPUInfo: host_cpu_load_info?
    private var previousNetworkBytes: (input: UInt64, output: UInt64, timestamp: Date)?

    func sample(previousModules: [MonitorModule]) -> SystemMonitorSnapshot {
        let modules = MonitorKind.allCases.map { kind in
            let module = makeModule(for: kind)
            if let previous = previousModules.first(where: { $0.kind == kind }) {
                var updated = module
                updated.samples = Array((previous.samples + [module.value]).suffix(28))
                return updated
            }
            return module
        }
        return SystemMonitorSnapshot(modules: modules)
    }

    private func makeModule(for kind: MonitorKind) -> MonitorModule {
        switch kind {
        case .cpu:
            return cpuModule()
        case .gpu:
            return gpuModule()
        case .memory:
            return memoryModule()
        case .storage:
            return storageModule()
        case .network:
            return networkModule()
        case .battery:
            return batteryModule()
        }
    }

    private func cpuModule() -> MonitorModule {
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
                MonitorMetric(name: "系统", value: percent(system)),
                MonitorMetric(name: "用户", value: percent(user)),
                MonitorMetric(name: "闲置", value: percent(idle))
            ]
        } else {
            total = 0
            metrics = [
                MonitorMetric(name: "系统", value: "--"),
                MonitorMetric(name: "用户", value: "--"),
                MonitorMetric(name: "闲置", value: "--")
            ]
        }

        if let info {
            previousCPUInfo = info
        }

        return MonitorModule(
            kind: .cpu,
            value: total,
            summary: percent(total),
            metrics: metrics,
            samples: seedSamples(total)
        )
    }

    private func memoryModule() -> MonitorModule {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return placeholderModule(.memory, summary: "无法读取")
        }

        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let used = max(0, active + inactive + wired + compressed - purgeable - external)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let percentage = total > 0 ? (used / total) * 100 : 0
        let swap = swapUsage()
        let pressure = kernelMemoryPressure()
            ?? memorystatusPressure()
            ?? memoryPressureScore(
            wired: wired,
            compressed: compressed,
            swapUsed: swap?.used ?? 0,
            total: total
        )

        return MonitorModule(
            kind: .memory,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "压力", value: percent(pressure)),
                MonitorMetric(name: "交换已用", value: swap.map { bytes($0.used) } ?? "--")
            ],
            samples: seedSamples(percentage)
        )
    }

    private func gpuModule() -> MonitorModule {
        guard let reading = gpuReading() else {
            return placeholderModule(.gpu, summary: "无法读取")
        }

        let utilization = min(100, max(0, reading.utilization))
        let usedMemory = reading.usedMemory.map(bytes) ?? "--"

        return MonitorModule(
            kind: .gpu,
            value: utilization,
            summary: percent(utilization),
            metrics: [
                MonitorMetric(name: "GPU内存", value: usedMemory)
            ],
            samples: seedSamples(utilization)
        )
    }

    private func storageModule() -> MonitorModule {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = (attributes[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let used = max(0, total - free)
            let percentage = total > 0 ? (used / total) * 100 : 0

            return MonitorModule(
                kind: .storage,
                value: percentage,
                summary: percent(percentage),
                metrics: [
                    MonitorMetric(name: "已用", value: bytes(used)),
                    MonitorMetric(name: "可用", value: bytes(free)),
                    MonitorMetric(name: "总量", value: bytes(total))
                ],
                samples: seedSamples(percentage)
            )
        } catch {
            return placeholderModule(.storage, summary: "无法读取")
        }
    }

    private func networkModule() -> MonitorModule {
        let now = Date()
        let bytes = networkBytes()
        let previous = previousNetworkBytes
        previousNetworkBytes = (bytes.input, bytes.output, now)

        guard let previous else {
            return MonitorModule(
                kind: .network,
                value: 0,
                summary: bytes.interface,
                metrics: [
                    MonitorMetric(name: "上传", value: "--"),
                    MonitorMetric(name: "下载", value: "--")
                ],
                samples: seedSamples(0)
            )
        }

        let delta = max(0.1, now.timeIntervalSince(previous.timestamp))
        let upload = Double(bytes.output &- previous.output) / delta
        let download = Double(bytes.input &- previous.input) / delta
        let value = min(100, log10(max(1, upload + download)) * 14)

        return MonitorModule(
            kind: .network,
            value: value,
            summary: bytes.interface,
            metrics: [
                MonitorMetric(name: "上传", value: bytesPerSecond(upload)),
                MonitorMetric(name: "下载", value: bytesPerSecond(download))
            ],
            samples: seedSamples(value)
        )
    }

    private func batteryModule() -> MonitorModule {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return placeholderModule(.battery, summary: "无法读取")
        }

        let current = doubleValue(description[kIOPSCurrentCapacityKey]) ?? 0
        let maxCapacity = doubleValue(description[kIOPSMaxCapacityKey]) ?? 100
        let percentage = maxCapacity > 0 ? min(100, max(0, current / maxCapacity * 100)) : 0
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let connected = sourceState == kIOPSACPowerValue

        let smart = smartBatteryInfo()
        let power = smart.systemPowerWatts.map { "\(String(format: "%.1f", $0)) W" }
            ?? smart.batteryPowerWatts.map { "\(String(format: "%.1f", $0)) W" }
            ?? "--"
        let adapterPower = smart.adapterWatts.map { "\(Int($0.rounded())) W" } ?? "--"

        return MonitorModule(
            kind: .battery,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "状态", value: isCharging ? "充电中" : (connected ? "外接电源" : "电池供电")),
                MonitorMetric(name: "适配器", value: adapterPower),
                MonitorMetric(name: "功耗", value: power)
            ],
            samples: seedSamples(percentage)
        )
    }


    private func hostCPULoadInfo() -> host_cpu_load_info? {
        let count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var size = count
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func networkBytes() -> (input: UInt64, output: UInt64, interface: String) {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        var totalsByInterface: [String: (input: UInt64, output: UInt64)] = [:]

        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            return (0, 0, "网络")
        }
        defer { freeifaddrs(addressList) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            if name == "lo0" || name.hasPrefix("utun") || name.hasPrefix("awdl") {
                continue
            }

            var current = totalsByInterface[name] ?? (0, 0)
            current.input += UInt64(data.ifi_ibytes)
            current.output += UInt64(data.ifi_obytes)
            totalsByInterface[name] = current
        }

        let active = totalsByInterface.max {
            ($0.value.input + $0.value.output) < ($1.value.input + $1.value.output)
        }
        let total = totalsByInterface.values.reduce((input: UInt64(0), output: UInt64(0))) { partial, next in
            (partial.input + next.input, partial.output + next.output)
        }

        return (total.input, total.output, networkInterfaceTitle(active?.key))
    }

    private func gpuReading() -> GPUReading? {
        let accelerators = registryEntries(forClass: "IOAccelerator")
        guard !accelerators.isEmpty else {
            return nil
        }

        var best: GPUReading?
        for accelerator in accelerators {
            guard let stats = accelerator["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            let utilization = doubleValue(stats["Device Utilization %"])
                ?? doubleValue(stats["GPU Activity(%)"])
                ?? 0
            let render = doubleValue(stats["Renderer Utilization %"])
            let tiler = doubleValue(stats["Tiler Utilization %"])
            let temperature = doubleValue(stats["Temperature(C)"])
            let usedMemory = doubleValue(stats["In use system memory"])
            let allocatedMemory = doubleValue(stats["Alloc system memory"])
            let model = accelerator["model"] as? String ?? accelerator["IOClass"] as? String ?? "GPU"

            let reading = GPUReading(
                model: model,
                utilization: utilization,
                renderUtilization: render,
                tilerUtilization: tiler,
                temperature: temperature,
                usedMemory: usedMemory,
                allocatedMemory: allocatedMemory
            )

            if best == nil || reading.utilization > (best?.utilization ?? 0) {
                best = reading
            }
        }

        return best
    }

    private func smartBatteryInfo() -> SmartBatteryInfo {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            return SmartBatteryInfo()
        }
        defer { IOObjectRelease(service) }

        let cycleCount = intRegistryValue(service, "CycleCount")
        let designCapacity = doubleRegistryValue(service, "DesignCapacity")
        let maxCapacity = doubleRegistryValue(service, "AppleRawMaxCapacity")
            ?? doubleRegistryValue(service, "MaxCapacity")
        let voltage = doubleRegistryValue(service, "Voltage")
        let amperage = doubleRegistryValue(service, "Amperage")
        let adapterWatts = adapterWatts(service)
        let systemPowerWatts = systemPowerWatts(service)
        let health = if let maxCapacity, let designCapacity, designCapacity > 0 {
            min(100, max(0, maxCapacity / designCapacity * 100))
        } else {
            nil as Double?
        }
        let batteryWatts = if let voltage, let amperage {
            abs(voltage * amperage / 1_000_000)
        } else {
            nil as Double?
        }

        return SmartBatteryInfo(
            cycleCount: cycleCount,
            healthPercent: health,
            batteryPowerWatts: batteryWatts,
            adapterWatts: adapterWatts,
            systemPowerWatts: systemPowerWatts
        )
    }

    private func adapterWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return doubleValue(value["Watts"])
    }

    private func systemPowerWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }

        if let adapterMilliwatts = doubleValue(value["SystemPowerIn"]), adapterMilliwatts > 0 {
            return adapterMilliwatts / 1_000
        }

        if let batteryMilliwatts = signedDoubleValue(value["BatteryPower"]), batteryMilliwatts != 0 {
            return abs(batteryMilliwatts) / 1_000
        }

        if let loadMilliwatts = doubleValue(value["SystemLoad"]), loadMilliwatts > 0 {
            return loadMilliwatts / 1_000
        }

        return nil
    }

    private func registryEntries(forClass className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var entries: [[String: Any]] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL {
                break
            }
            defer { IOObjectRelease(service) }

            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] {
                entries.append(dictionary)
            }
        }

        return entries
    }

    private func intRegistryValue(_ service: io_service_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return intValue(value)
    }

    private func doubleRegistryValue(_ service: io_service_t, _ key: String) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return doubleValue(value)
    }

    private func kernelMemoryPressure() -> Double? {
        var size = 0
        guard sysctlbyname("vm.memory_pressure", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { pointer in
            sysctlbyname("vm.memory_pressure", pointer.baseAddress, &size, nil, 0)
        }
        guard result == 0, size >= MemoryLayout<Int32>.size else {
            return nil
        }

        let raw = buffer.withUnsafeBytes { pointer in
            pointer.loadUnaligned(as: Int32.self)
        }
        return min(100, max(0, Double(raw)))
    }

    private func memorystatusPressure() -> Double? {
        var freePercent = UInt32(0)
        let result = withUnsafeMutablePointer(to: &freePercent) { pointer in
            memorystatus_get_level(UInt64(UInt(bitPattern: pointer)))
        }
        guard result == 0 else {
            return nil
        }

        return min(100, max(0, 100 - Double(freePercent)))
    }

    private func memoryPressureScore(wired: Double, compressed: Double, swapUsed: Double, total: Double) -> Double {
        guard total > 0 else {
            return 0
        }

        // Activity Monitor does not expose its exact pressure formula. This score follows the same signal mix:
        // wired memory, compressed memory, and swap pressure rather than simple used / total memory.
        let wiredRatio = wired / total
        let compressedRatio = compressed / total
        let swapRatio = swapUsed / total
        let score = wiredRatio * 42 + compressedRatio * 48 + swapRatio * 65
        return min(100, max(0, score))
    }

    private func swapUsage() -> SwapUsage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else {
            return nil
        }
        return SwapUsage(
            used: Double(usage.xsu_used),
            total: Double(usage.xsu_total),
            available: Double(usage.xsu_avail)
        )
    }

    private func networkInterfaceTitle(_ name: String?) -> String {
        guard let name else {
            return "网络"
        }

        if name == "en0" {
            return "Wi-Fi"
        }
        if name.hasPrefix("en") {
            return "以太网"
        }
        if name.hasPrefix("bridge") {
            return "桥接"
        }
        if name.hasPrefix("pdp_ip") {
            return "蜂窝"
        }
        return name
    }

    private func placeholderModule(_ kind: MonitorKind, summary: String) -> MonitorModule {
        MonitorModule(
            kind: kind,
            value: 0,
            summary: summary,
            metrics: [
                MonitorMetric(name: "状态", value: "未知"),
                MonitorMetric(name: "数据", value: "--"),
                MonitorMetric(name: "更新", value: "--")
            ],
            samples: seedSamples(0)
        )
    }

    private func seedSamples(_ value: Double) -> [Double] {
        Array(repeating: min(100, max(0, value)), count: 28)
    }
}

private struct GPUReading {
    let model: String
    let utilization: Double
    let renderUtilization: Double?
    let tilerUtilization: Double?
    let temperature: Double?
    let usedMemory: Double?
    let allocatedMemory: Double?
}

private struct SmartBatteryInfo {
    var cycleCount: Int?
    var healthPercent: Double?
    var batteryPowerWatts: Double?
    var adapterWatts: Double?
    var systemPowerWatts: Double?
}

private struct SwapUsage {
    let used: Double
    let total: Double
    let available: Double
}

private func percent(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

private func bytes(_ value: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(max(0, value)))
}

private func bytesPerSecond(_ value: Double) -> String {
    let safeValue = max(0, value)
    let units = ["B/s", "KB/s", "MB/s", "GB/s"]
    var scaled = safeValue
    var unitIndex = 0

    while scaled >= 1024, unitIndex < units.count - 1 {
        scaled /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(Int(scaled.rounded())) \(units[unitIndex])"
    }
    return "\(String(format: scaled >= 10 ? "%.0f" : "%.1f", scaled)) \(units[unitIndex])"
}

private func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
        value
    case let value as Float:
        Double(value)
    case let value as Int:
        Double(value)
    case let value as Int64:
        Double(value)
    case let value as UInt64:
        Double(value)
    case let value as NSNumber:
        value.doubleValue
    default:
        nil
    }
}

private func signedDoubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Int:
        return Double(value)
    case let value as Int64:
        return Double(value)
    case let value as UInt64:
        if value > UInt64(Int64.max) {
            return Double(Int64(bitPattern: value))
        }
        return Double(value)
    case let value as NSNumber:
        let unsigned = value.uint64Value
        if unsigned > UInt64(Int64.max) {
            return Double(Int64(bitPattern: unsigned))
        }
        return value.doubleValue
    default:
        return doubleValue(value)
    }
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
        value
    case let value as Int64:
        Int(value)
    case let value as UInt64:
        Int(value)
    case let value as NSNumber:
        value.intValue
    default:
        nil
    }
}
