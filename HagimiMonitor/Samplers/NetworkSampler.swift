import Darwin
import Foundation
import OSLog

final class NetworkSampler: MonitorSampler {
    var kind: MonitorKind { .network }

    private var previousNetworkBytes: (input: UInt64, output: UInt64, timestamp: Date)?

    func sample(previous: MonitorModule?) -> MonitorModule {
        let now = Date()
        let bytes = networkBytes()
        let previousBytes = previousNetworkBytes
        previousNetworkBytes = (bytes.input, bytes.output, now)

        guard let previousBytes else {
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

        let delta = max(0.1, now.timeIntervalSince(previousBytes.timestamp))
        let upload = Double(bytes.output &- previousBytes.output) / delta
        let download = Double(bytes.input &- previousBytes.input) / delta
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

    private func networkBytes() -> (input: UInt64, output: UInt64, interface: String) {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        var totalsByInterface: [String: (input: UInt64, output: UInt64)] = [:]

        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            AppLogger.sampler.error("getifaddrs failed, errno: \(errno)")
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

        AppLogger.sampler.info("Network interfaces detected: \(totalsByInterface.keys.joined(separator: ", "), privacy: .public), active: \(active?.key ?? "none", privacy: .public)")

        AppLogger.sampler.info("Network active interface: \(active?.key ?? "none", privacy: .public)")

        return (total.input, total.output, networkInterfaceTitle(active?.key))
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
}
