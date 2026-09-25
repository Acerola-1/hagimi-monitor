import Darwin
import Foundation
import IOKit
import IOKit.ps
import Metal

@MainActor
public struct ProbeMetrics {
    public var cpuPercent: Double?
    public var gpuPercent: Double?
    public var memoryUsedBytes: Double?
    public var memoryTotalBytes: Double
    public var compressedBytes: Double?
    public var swapUsedBytes: Double?
    public var gpuMemoryUsedBytes: Double?
    public var gpuMemoryAllocatedBytes: Double?
    public var systemPowerWatts: Double?
    public var batteryPercent: Double?
    public var thermalState: String
    public var diagnostics: [String: String]
}

@MainActor
public final class ProbeSampler {
    public let cpuName: String
    public let gpuName: String
    public let logicalCPUCount: Int

    private let host: mach_port_t
    private let totalMemory: Double
    private let pageSize: Double
    private let accelerator: io_service_t
    private let battery: io_service_t
    private let otherTelemetry: io_service_t
    private let staticDiagnostics: [String: String]
    private var previousTicks: [UInt32]?

    public init() {
        var diagnostics: [String: String] = [:]
        cpuName = Self.readCPUName() ?? "Unknown CPU"
        let device = MTLCreateSystemDefaultDevice()
        gpuName = device?.name ?? "Unavailable GPU"
        logicalCPUCount = ProcessInfo.processInfo.processorCount
        totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        pageSize = Double(getpagesize())
        host = mach_host_self()
        accelerator = Self.findAccelerator(registryID: device?.registryID, diagnostics: &diagnostics)
        battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        otherTelemetry = Self.dictionary(battery, "PowerTelemetryData") == nil
            ? Self.findTelemetry(diagnostics: &diagnostics) : IO_OBJECT_NULL
        diagnostics["AppleSmartBattery"] = battery == IO_OBJECT_NULL ? "service unavailable" : "service found"
        diagnostics["AppleSMC"] = Self.checkSMCConnection()
        diagnostics["gpuMemoryScope"] = "IOAccelerator driver aggregate bytes; not game/process memory or dedicated VRAM"
        staticDiagnostics = diagnostics
    }

    deinit {
        mach_port_deallocate(mach_task_self_, host)
        for service in [accelerator, battery, otherTelemetry] where service != IO_OBJECT_NULL {
            IOObjectRelease(service)
        }
    }

    public func sample() -> ProbeMetrics {
        var diagnostics = staticDiagnostics
        let cpu = cpuUsage(diagnostics: &diagnostics)
        let memory = memoryUsage(diagnostics: &diagnostics)
        let swap = swapUsage(diagnostics: &diagnostics)
        let gpu = Self.dictionary(accelerator, "PerformanceStatistics")
        let utilizationKey = ["Device Utilization %", "GPU Activity(%)"].first {
            Self.percentage(gpu?[$0]) != nil
        }
        let gpuPercent = utilizationKey.flatMap { Self.percentage(gpu?[$0]) }
        let gpuUsed = Self.nonnegative(gpu?["In use system memory"])
        let gpuAllocated = Self.nonnegative(gpu?["Alloc system memory"])
        diagnostics["gpuPercent"] = utilizationKey ?? "field missing, invalid, or inaccessible"
        diagnostics["gpuMemoryUsedBytes"] = gpuUsed == nil ? "field missing, invalid, or inaccessible" : "In use system memory (bytes)"
        diagnostics["gpuMemoryAllocatedBytes"] = gpuAllocated == nil ? "field missing, invalid, or inaccessible" : "Alloc system memory (bytes)"

        let state = Self.powerSourceState()
        let batteryProperties = Self.properties(battery, diagnostics: &diagnostics)
        let registryPercent: Double? = {
            guard batteryProperties?["BatteryInstalled"] as? Bool != false,
                  let current = Self.nonnegative(batteryProperties?["CurrentCapacity"]),
                  let maximum = Self.nonnegative(batteryProperties?["MaxCapacity"]),
                  maximum > 0, current <= maximum else { return nil }
            return current / maximum * 100
        }()
        let batteryPercent = registryPercent ?? state.percent
        diagnostics["batteryPercent"] = registryPercent != nil ? "AppleSmartBattery CurrentCapacity / MaxCapacity"
            : (state.percent != nil ? "IOPS internal battery capacity" : "internal battery capacity unavailable")
        let telemetry = batteryProperties?["PowerTelemetryData"] as? [String: Any]
            ?? Self.dictionary(otherTelemetry, "PowerTelemetryData")
        let power = Self.systemPower(telemetry, external: state.external, charging: state.charging, diagnostics: &diagnostics)

        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return ProbeMetrics(
            cpuPercent: cpu, gpuPercent: gpuPercent,
            memoryUsedBytes: memory.used, memoryTotalBytes: totalMemory,
            compressedBytes: memory.compressed, swapUsedBytes: swap,
            gpuMemoryUsedBytes: gpuUsed, gpuMemoryAllocatedBytes: gpuAllocated,
            systemPowerWatts: power, batteryPercent: batteryPercent,
            thermalState: thermal, diagnostics: diagnostics
        )
    }

    private func cpuUsage(diagnostics: inout [String: String]) -> Double? {
        var info = host_cpu_load_info()
        let expected = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var count = expected
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(expected)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count >= expected else {
            previousTicks = nil
            diagnostics["cpuPercent"] = "host_statistics: \(result), count: \(count)"
            return nil
        }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        let previous = previousTicks
        previousTicks = ticks
        guard let previous else {
            diagnostics["cpuPercent"] = "warming up; needs two successful samples"
            return nil
        }
        // Mach tick 为 UInt32 累计计数，回绕差分后按整机总 tick 归一到 0–100%。
        let delta = zip(ticks, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else {
            diagnostics["cpuPercent"] = "no elapsed CPU ticks"
            return nil
        }
        diagnostics["cpuPercent"] = "Mach aggregate tick delta (0–100%)"
        return (total - delta[Int(CPU_STATE_IDLE)]) / total * 100
    }

    private func memoryUsage(diagnostics: inout [String: String]) -> (used: Double?, compressed: Double?) {
        var info = vm_statistics64()
        let expected = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var count = expected
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(expected)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        diagnostics["memory"] = "host_statistics64: \(result), count: \(count)"
        guard result == KERN_SUCCESS, count >= expected else { return (nil, nil) }
        let compressed = Double(info.compressor_page_count) * pageSize
        // 与项目 MemorySampler 同口径：活跃 + 非活跃 + 推测 + wired + 压缩 − 可清除 − 文件映射。
        let used = (Double(info.active_count) + Double(info.inactive_count) + Double(info.speculative_count)
            + Double(info.wire_count) + Double(info.compressor_page_count)
            - Double(info.purgeable_count) - Double(info.external_page_count)) * pageSize
        return (max(0, used), compressed)
    }

    private func swapUsage(diagnostics: inout [String: String]) -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        let error = result == 0 ? 0 : errno
        diagnostics["swapUsedBytes"] = "vm.swapusage: \(result), errno: \(error)"
        guard result == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return Double(usage.xsu_used)
    }

    private static func powerSourceState() -> (percent: Double?, external: Bool?, charging: Bool?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, nil, nil)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }
            var percent: Double?
            if let current = nonnegative(description[kIOPSCurrentCapacityKey]),
               let maximum = nonnegative(description[kIOPSMaxCapacityKey]), maximum > 0, current <= maximum {
                percent = current / maximum * 100
            }
            let sourceState = description[kIOPSPowerSourceStateKey] as? String
            let external: Bool? = sourceState == kIOPSACPowerValue ? true
                : (sourceState == kIOPSBatteryPowerValue ? false : nil)
            return (percent, external, description[kIOPSIsChargingKey] as? Bool)
        }
        return (nil, nil, nil)
    }

    private static func systemPower(
        _ telemetry: [String: Any]?, external: Bool?, charging: Bool?, diagnostics: inout [String: String]
    ) -> Double? {
        diagnostics["systemPowerWatts"] = "PowerTelemetryData unavailable or insufficient valid fields/state"
        guard let telemetry else { return nil }
        // 遥测功率单位为 mW；SystemLoad 是整机负载，SystemPowerIn 是适配器输入，不能直接等同。
        if let load = nonnegative(telemetry["SystemLoad"]), load > 0 {
            diagnostics["systemPowerWatts"] = "PowerTelemetryData.SystemLoad / 1000"
            return load / 1_000
        }
        guard let batteryPower = signedNumber(telemetry["BatteryPower"]) else { return nil }
        let magnitude = abs(batteryPower)
        if external == false, charging == false, magnitude > 0 {
            diagnostics["systemPowerWatts"] = "abs(BatteryPower) / 1000; IOPS on-battery estimate"
            return magnitude / 1_000
        }
        guard external == true, let charging,
              let input = nonnegative(telemetry["SystemPowerIn"]), input > 0 else { return nil }
        // 电池功率符号随机型变化，流向只取 IOPS 状态；缺失字段不当作零。
        let load = charging ? input - magnitude : input + magnitude
        guard load > 0, load.isFinite else { return nil }
        diagnostics["systemPowerWatts"] = charging
            ? "(SystemPowerIn - abs(BatteryPower)) / 1000; IOPS charging estimate"
            : "(SystemPowerIn + abs(BatteryPower)) / 1000; IOPS not-charging estimate"
        return load / 1_000
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number
    }

    private static func nonnegative(_ value: Any?) -> Double? {
        guard let value = number(value)?.doubleValue, value >= 0 else { return nil }
        return value
    }

    private static func percentage(_ value: Any?) -> Double? {
        guard let value = nonnegative(value), value <= 100 else { return nil }
        return value
    }

    private static func signedNumber(_ value: Any?) -> Double? {
        guard let number = number(value) else { return nil }
        // 固件可能把负的 BatteryPower 编成无符号 64 位二补码。
        return String(cString: number.objCType) == "Q"
            ? Double(Int64(bitPattern: number.uint64Value)) : number.doubleValue
    }

    private static func dictionary(_ service: io_service_t, _ key: String) -> [String: Any]? {
        guard service != IO_OBJECT_NULL else { return nil }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    private static func properties(_ service: io_service_t, diagnostics: inout [String: String]) -> [String: Any]? {
        guard service != IO_OBJECT_NULL else { return nil }
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        let value = properties?.takeRetainedValue()
        diagnostics["AppleSmartBattery.read"] = "IORegistryEntryCreateCFProperties: \(result)"
        guard result == KERN_SUCCESS else { return nil }
        return value as? [String: Any]
    }

    private static func services(_ name: String, diagnostics: inout [String: String]) -> [io_service_t] {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator)
        defer { if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) } }
        diagnostics["\(name).matching"] = "IOServiceGetMatchingServices: \(result)"
        guard result == KERN_SUCCESS else { return [] }
        var services: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            services.append(service)
        }
        return services
    }

    private static func findAccelerator(registryID: UInt64?, diagnostics: inout [String: String]) -> io_service_t {
        let candidates = services("IOAccelerator", diagnostics: &diagnostics)
        let matched = candidates.first { service in
            var identifier: UInt64 = 0
            return IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS && identifier == registryID
        }
        // 多 GPU 时不把另一驱动的统计冠以默认 Metal 设备名称。
        let selected = matched ?? (candidates.count == 1 ? candidates.first : nil)
        for service in candidates where service != selected { IOObjectRelease(service) }
        diagnostics["gpuSource"] = matched != nil ? "default Metal device IOAccelerator"
            : (selected != nil ? "sole IOAccelerator" : "IOAccelerator unavailable or multiple devices cannot be matched")
        return selected ?? IO_OBJECT_NULL
    }

    private static func findTelemetry(diagnostics: inout [String: String]) -> io_service_t {
        let candidates = services("IOService", diagnostics: &diagnostics)
        let selected = candidates.first { dictionary($0, "PowerTelemetryData") != nil }
        for service in candidates where service != selected { IOObjectRelease(service) }
        diagnostics["powerTelemetrySource"] = selected == nil ? "no readable PowerTelemetryData service" : "cached PowerTelemetryData service"
        return selected ?? IO_OBJECT_NULL
    }

    private static func checkSMCConnection() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return "service unavailable; open not attempted" }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = IO_OBJECT_NULL
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        var status = "IOServiceOpen: \(result) (\(String(format: "0x%08x", UInt32(bitPattern: result))))"
        // 仅探测连接可达性并立即关闭，不调用任何 SMC 请求或写操作。
        if connection != IO_OBJECT_NULL {
            status += "; IOServiceClose: \(IOServiceClose(connection))"
        }
        return status
    }

    private static func readCPUName() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("machdep.cpu.brand_string", $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        let name = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
