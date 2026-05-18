import Darwin
import Foundation
import IOKit
import IOKit.ps

struct SystemMonitorSnapshot {
    var modules: [MonitorModule]
}

final class SystemMonitorSampler {
    private var previousCPUInfo: host_cpu_load_info?
    private var previousNetworkBytes: (input: UInt64, output: UInt64, timestamp: Date)?
    private var powerTelemetryService: io_service_t = IO_OBJECT_NULL
    private var didSearchPowerTelemetryService = false
    private let totalMemorySize = SystemMonitorSampler.memoryTotalSize()
    private let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter
    }()

    deinit {
        if powerTelemetryService != IO_OBJECT_NULL {
            IOObjectRelease(powerTelemetryService)
        }
    }

    func sample(previousModules: [MonitorModule]) -> SystemMonitorSnapshot {
        sample(kinds: MonitorKind.allCases, previousModules: previousModules)
    }

    func sample(kinds: some Sequence<MonitorKind>, previousModules: [MonitorModule]) -> SystemMonitorSnapshot {
        autoreleasepool {
            var modulesByKind = Dictionary(uniqueKeysWithValues: previousModules.map { ($0.kind, $0) })

            for kind in kinds {
                let module = makeModule(for: kind)
                if let previous = modulesByKind[kind] {
                    var updated = module
                    updated.samples = Array((previous.samples + [module.value]).suffix(28))
                    modulesByKind[kind] = updated
                } else {
                    modulesByKind[kind] = module
                }
            }

            let modules = MonitorKind.allCases.map { kind in
                modulesByKind[kind] ?? MonitorModule.placeholder(kind: kind)
            }
            return SystemMonitorSnapshot(modules: modules)
        }
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
                MonitorMetric(name: "闲置", value: percent(idle)),
                MonitorMetric(name: "启动时间", value: systemUptime())
            ]
        } else {
            total = 0
            metrics = [
                MonitorMetric(name: "系统", value: "--"),
                MonitorMetric(name: "用户", value: "--"),
                MonitorMetric(name: "闲置", value: "--"),
                MonitorMetric(name: "启动时间", value: systemUptime())
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
        let speculative = Double(stats.speculative_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize
        let used = max(0, active + inactive + speculative + wired + compressed - purgeable - external)
        let total = totalMemorySize
        let percentage = total > 0 ? (used / total) * 100 : 0
        let swap = swapUsage()
        let pressure = memoryPressure()

        return MonitorModule(
            kind: .memory,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "已用", value: memoryBytes(used)),
                MonitorMetric(name: "压力", value: pressure.title),
                MonitorMetric(name: "交换已用", value: swapUsedText(swap)),
                MonitorMetric(name: "总量", value: memoryBytes(total))
            ],
            samples: seedSamples(percentage)
        )
    }

    private func gpuModule() -> MonitorModule {
        guard let reading = gpuReading() else {
            return placeholderModule(.gpu, summary: "无法读取")
        }

        let utilization = min(100, max(0, reading.utilization))
        var metrics = [
            MonitorMetric(name: "GPU内存", value: reading.usedMemory.map(bytes) ?? "--"),
            MonitorMetric(name: "已分配", value: reading.allocatedMemory.map(bytes) ?? "--")
        ]

        if let renderUtilization = reading.renderUtilization {
            metrics.append(MonitorMetric(name: "渲染", value: percent(renderUtilization)))
        }

        if let tilerUtilization = reading.tilerUtilization {
            metrics.append(MonitorMetric(name: "分块", value: percent(tilerUtilization)))
        }

        return MonitorModule(
            kind: .gpu,
            value: utilization,
            summary: percent(utilization),
            metrics: metrics,
            samples: seedSamples(utilization)
        )
    }

    private func storageModule() -> MonitorModule {
        do {
            let rootURL = URL(fileURLWithPath: "/")
            let values = try rootURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = Double(values.volumeTotalCapacity ?? Int((attributes[.systemSize] as? NSNumber)?.int64Value ?? 0))
            let free = Double(values.volumeAvailableCapacity ?? Int((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0))
            let used = max(0, total - free)
            let percentage = total > 0 ? (used / total) * 100 : 0

            return MonitorModule(
                kind: .storage,
                context: externalVolumesJSON(),
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

    private func externalVolumesJSON() -> String? {
        let volumes = detectExternalVolumes()
        guard !volumes.isEmpty else { return nil }

        let payload = volumes.map { vol in
            let pct = vol.total > 0 ? Int((vol.used / vol.total * 100).rounded()) : 0
            return ExternalVolumePayload(
                name: vol.name,
                used: bytes(vol.used),
                free: bytes(vol.free),
                total: bytes(vol.total),
                percentage: pct
            )
        }

        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private struct ExternalVolume {
        let name: String
        let used: Double
        let free: Double
        let total: Double
    }

    private struct ExternalVolumePayload: Encodable {
        let name: String
        let used: String
        let free: String
        let total: String
        let percentage: Int
    }

    private func detectExternalVolumes() -> [ExternalVolume] {
        guard let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey], options: []) else {
            return []
        }

        var volumes: [ExternalVolume] = []
        for url in volumeURLs {
            guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey]),
                  let totalCapacity = values.volumeTotalCapacity,
                  let availableCapacity = values.volumeAvailableCapacity,
                  let name = values.volumeName,
                  // 用 volumeIsInternalKey == false 检测外置卷，比 removable 更准确
                  values.volumeIsInternal == false else {
                continue
            }

            let total = Double(totalCapacity)
            let free = Double(availableCapacity)
            let used = max(0, total - free)

            guard total > 0 else { continue }

            volumes.append(ExternalVolume(name: name, used: used, free: free, total: total))
        }

        // 最多 3 个，避免撑高面板
        return Array(volumes.prefix(3))
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
            return externalPowerModule()
        }

        let current = doubleValue(description[kIOPSCurrentCapacityKey]) ?? 0
        let maxCapacity = doubleValue(description[kIOPSMaxCapacityKey]) ?? 100
        let percentage = maxCapacity > 0 ? min(100, max(0, current / maxCapacity * 100)) : 0
        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let connected = sourceState == kIOPSACPowerValue

        let smart = smartBatteryInfo()
        let adapterWatts = smart.adapterWatts ?? externalAdapterWatts()
        let chargingPower = connected
            ? (smart.telemetryChargingWatts ?? smart.chargingPowerWatts)
            : nil
        let systemPower = smart.systemPowerWatts ?? powerTelemetryWatts()

        return MonitorModule(
            kind: .battery,
            value: percentage,
            summary: percent(percentage),
            metrics: [
                MonitorMetric(name: "类型", value: "电池"),
                MonitorMetric(name: "状态", value: isCharging ? "充电中" : (connected ? "外接电源" : "电池供电")),
                MonitorMetric(name: "适配器", value: wattString(adapterWatts, rounded: true)),
                MonitorMetric(name: "充电功率", value: connected ? wattStringAllowZero(chargingPower) : "--"),
                MonitorMetric(name: "功耗", value: wattString(systemPower)),
                MonitorMetric(name: "健康度", value: smart.healthPercent.map(percent) ?? "--"),
                MonitorMetric(name: "循环数", value: smart.cycleCount.map { "\($0)" } ?? "--"),
                MonitorMetric(name: "温度", value: smart.temperatureCelsius.map { "\(String(format: "%.0f", $0))°C" } ?? "--")
            ],
            samples: seedSamples(percentage)
        )
    }

    private func externalPowerModule() -> MonitorModule {
        let adapterWatts = externalAdapterWatts()
        let powerWatts = powerTelemetryWatts()
        return MonitorModule(
            kind: .battery,
            value: 100,
            summary: "外接电源",
            metrics: [
                MonitorMetric(name: "类型", value: "外接电源"),
                MonitorMetric(name: "状态", value: "外接电源"),
                MonitorMetric(name: "适配器", value: wattString(adapterWatts, rounded: true)),
                MonitorMetric(name: "功耗", value: wattString(powerWatts))
            ],
            samples: seedSamples(100)
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

    private static func memoryTotalSize() -> Double {
        var info = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return Double(ProcessInfo.processInfo.physicalMemory)
        }
        return Double(info.max_mem)
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
        let accelerators = acceleratorServices()
        guard !accelerators.isEmpty else {
            return nil
        }
        defer {
            accelerators.forEach { IOObjectRelease($0) }
        }

        var best: GPUReading?
        for accelerator in accelerators {
            guard let stats = registryDictionaryValue(accelerator, "PerformanceStatistics") else {
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
            let model = registryStringValue(accelerator, "model")
                ?? registryStringValue(accelerator, "IOClass")
                ?? "GPU"

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

    private func acceleratorServices() -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var services: [io_service_t] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else {
                break
            }
            services.append(service)
        }
        return services
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
        let chargingPowerWatts = chargingPowerWatts(service)
        let telemetryChargingWatts = telemetryChargingWatts(service)
        let temperature = doubleRegistryValue(service, "Temperature").map { $0 / 100 }
        let health = if let maxCapacity, let designCapacity, designCapacity > 0 {
            min(100, max(0, maxCapacity / designCapacity * 100))
        } else {
            nil as Double?
        }
        let batteryWatts = if let voltage, let amperage {
            nonZeroWatts(abs(voltage * amperage / 1_000_000))
        } else {
            nil as Double?
        }

        return SmartBatteryInfo(
            cycleCount: cycleCount,
            healthPercent: health,
            batteryPowerWatts: batteryWatts,
            adapterWatts: adapterWatts,
            systemPowerWatts: systemPowerWatts,
            chargingPowerWatts: chargingPowerWatts,
            temperatureCelsius: temperature,
            telemetryChargingWatts: telemetryChargingWatts
        )
    }

    private func adapterWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return doubleValue(value["Watts"])
    }

    private func externalAdapterWatts() -> Double? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return doubleValue(details[kIOPSPowerAdapterWattsKey])
    }

    private func chargingPowerWatts(_ service: io_service_t) -> Double? {
        // 优先用 PowerTelemetryData.BatteryPower（电池包级别，准确）
        if let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
           let bp = signedDoubleValue(value["BatteryPower"]), bp < 0 {
            return abs(bp) / 1_000
        }
        // Fallback: ChargerData 的 ChargingCurrent * ChargingVoltage
        // 注意 ChargingVoltage 是单节电芯电压，结果会偏低
        guard let value = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let current = doubleValue(value["ChargingCurrent"]),
              let voltage = doubleValue(value["ChargingVoltage"]) else {
            return nil
        }
        return nonZeroWatts(current * voltage / 1_000_000)
    }

    private func telemetryChargingWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
              let bp = signedDoubleValue(value["BatteryPower"]), bp < 0 else {
            return nil
        }
        return abs(bp) / 1_000
    }

    private func powerTelemetryWatts() -> Double? {
        if powerTelemetryService == IO_OBJECT_NULL, !didSearchPowerTelemetryService {
            powerTelemetryService = serviceWithProperty("PowerTelemetryData")
            didSearchPowerTelemetryService = true
        }
        guard powerTelemetryService != IO_OBJECT_NULL else {
            return nil
        }
        return systemPowerWatts(powerTelemetryService)
    }

    private func systemPowerWatts(_ service: io_service_t) -> Double? {
        guard let value = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard let powerIn = doubleValue(value["SystemPowerIn"]), powerIn > 0 else {
            // 电池供电：用 BatteryPower
            if let bp = signedDoubleValue(value["BatteryPower"]), bp != 0 {
                return abs(bp) / 1_000
            }
            return nil
        }

        let batteryPower = signedDoubleValue(value["BatteryPower"]) ?? 0

        if batteryPower == 0 {
            // 未充电：SystemPowerIn 就是系统功耗
            return powerIn / 1_000
        }

        let systemPower = powerIn - abs(batteryPower)
        if systemPower > 0 {
            // 充电时：系统功耗 = 适配器输入 - 充电功率
            return systemPower / 1_000
        }

        // 遥测瞬时不同步导致差值为负，返回 nil 而非跳到完整 powerIn
        return nil
    }

    private func serviceWithProperty(_ key: String) -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOService"), &iterator) == KERN_SUCCESS else {
            return IO_OBJECT_NULL
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else {
                return IO_OBJECT_NULL
            }

            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) {
                value.release()
                return service
            }

            IOObjectRelease(service)
        }
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

    private func registryDictionaryValue(_ service: io_service_t, _ key: String) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    private func registryStringValue(_ service: io_service_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    private func memoryPressure() -> MemoryPressureState {
        let vmPressureWarning: Int32 = 2
        let vmPressureCritical: Int32 = 4
        var pressureLevel = Int32(0)
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0)
        guard result == 0 else {
            return .unknown
        }

        switch pressureLevel {
        case vmPressureWarning:
            return .warning
        case vmPressureCritical:
            return .critical
        default:
            return .normal
        }
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

    private func swapUsedText(_ swap: SwapUsage?) -> String {
        guard let used = swap?.used, used > 0 else {
            return "--"
        }
        return memoryBytes(used)
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
    var chargingPowerWatts: Double?
    var temperatureCelsius: Double?
    var telemetryChargingWatts: Double?
}

private struct SwapUsage {
    let used: Double
    let total: Double
    let available: Double
}

private enum MemoryPressureState {
    case normal
    case warning
    case critical
    case unknown

    var title: String {
        switch self {
        case .normal:
            "正常"
        case .warning:
            "偏高"
        case .critical:
            "严重"
        case .unknown:
            "--"
        }
    }
}

private func percent(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

private func bytes(_ value: Double) -> String {
    byteFormatter.string(fromByteCount: Int64(max(0, value)))
}

private func memoryBytes(_ value: Double) -> String {
    memoryByteFormatter.string(fromByteCount: Int64(max(0, value)))
}

private func wattString(_ value: Double?, rounded: Bool = false) -> String {
    guard let value else {
        return "--"
    }
    if rounded {
        return "\(Int(value.rounded())) W"
    }
    return "\(String(format: "%.1f", value)) W"
}

private func wattStringAllowZero(_ value: Double?) -> String {
    guard let value else {
        return "--"
    }
    return value == 0 ? "0 W" : "\(String(format: "%.1f", value)) W"
}

private func nonZeroWatts(_ value: Double?) -> Double? {
    guard let value, value >= 0.05 else {
        return nil
    }
    return value
}

private let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .file
    return formatter
}()

private let memoryByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB]
    formatter.countStyle = .memory
    return formatter
}()

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
