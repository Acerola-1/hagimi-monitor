import Darwin
import Foundation
import OSLog

final class CPUSampler: MonitorSampler {
    var kind: MonitorKind { .cpu }

    private var previousCPUInfo: host_cpu_load_info?
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
            self.previousCPUInfo = info
        }

        return MonitorModule(
            kind: .cpu,
            value: total,
            summary: percent(total),
            metrics: metrics,
            samples: seedSamples(total)
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
        guard result == KERN_SUCCESS else {
            AppLogger.sampler.error("host_statistics failed with result: \(result)")
            return nil
        }
        return info
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
