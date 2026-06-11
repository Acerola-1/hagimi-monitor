import Darwin
import Foundation
import OSLog

final class MemorySampler: MonitorSampler {
    var kind: MonitorKind { .memory }

    private let totalMemorySize = MemorySampler.memoryTotalSize()

    func sample(previous: MonitorModule?) -> MonitorModule {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            AppLogger.sampler.error("host_statistics64 failed with result: \(result)")
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
                MonitorMetric(name: "used", value: memoryBytes(used)),
                MonitorMetric(name: "pressure", value: pressure.title),
                MonitorMetric(name: "swap-used", value: swapUsedText(swap)),
                MonitorMetric(name: "total", value: memoryBytes(total))
            ],
            samples: seedSamples(percentage),
            pressure: pressure.level
        )
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
}

private enum MemoryPressureState {
    case normal
    case warning
    case critical
    case unknown

    var title: String {
        switch self {
        case .normal:
            "normal"
        case .warning:
            "warning"
        case .critical:
            "critical"
        case .unknown:
            "--"
        }
    }

    var level: MemoryPressureLevel {
        switch self {
        case .normal: .normal
        case .warning: .warning
        case .critical: .critical
        case .unknown: .unknown
        }
    }
}

private struct SwapUsage {
    let used: Double
    let total: Double
    let available: Double
}
