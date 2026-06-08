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
                    MonitorMetric(name: "IP 地址", value: networkAddressSummary(bytes.addresses)),
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
                MonitorMetric(name: "IP 地址", value: networkAddressSummary(bytes.addresses)),
                MonitorMetric(name: "上传", value: bytesPerSecond(upload)),
                MonitorMetric(name: "下载", value: bytesPerSecond(download))
            ],
            samples: seedSamples(value)
        )
    }

    private func networkBytes() -> NetworkInterfaceSnapshot {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        var totalsByInterface: [String: (input: UInt64, output: UInt64)] = [:]
        var addressesByInterface: [String: [String]] = [:]

        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            AppLogger.sampler.error("getifaddrs failed, errno: \(errno)")
            return NetworkInterfaceSnapshot(input: 0, output: 0, interface: "网络", addresses: [])
        }
        defer { freeifaddrs(addressList) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard !shouldIgnoreInterface(name) else {
                continue
            }

            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else {
                    continue
                }

                var current = totalsByInterface[name] ?? (0, 0)
                current.input += UInt64(data.ifi_ibytes)
                current.output += UInt64(data.ifi_obytes)
                totalsByInterface[name] = current

            case AF_INET, AF_INET6:
                guard let addressText = ipAddress(from: address) else {
                    continue
                }

                var addresses = addressesByInterface[name] ?? []
                if !addresses.contains(addressText) {
                    addresses.append(addressText)
                    addressesByInterface[name] = addresses
                }

            default:
                continue
            }
        }

        let active = totalsByInterface.max {
            ($0.value.input + $0.value.output) < ($1.value.input + $1.value.output)
        }
        let total = totalsByInterface.values.reduce((input: UInt64(0), output: UInt64(0))) { partial, next in
            (partial.input + next.input, partial.output + next.output)
        }

        AppLogger.sampler.info("Network interfaces detected: \(totalsByInterface.keys.joined(separator: ", "), privacy: .public), active: \(active?.key ?? "none", privacy: .public)")

        AppLogger.sampler.info("Network active interface: \(active?.key ?? "none", privacy: .public)")

        return NetworkInterfaceSnapshot(
            input: total.input,
            output: total.output,
            interface: networkInterfaceTitle(active?.key),
            addresses: active.flatMap { addressesByInterface[$0.key] } ?? []
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

    private func shouldIgnoreInterface(_ name: String) -> Bool {
        name == "lo0" || name.hasPrefix("utun") || name.hasPrefix("awdl")
    }

    private func ipAddress(from socketAddress: UnsafePointer<sockaddr>) -> String? {
        let family = Int32(socketAddress.pointee.sa_family)
        let maxLength = Int(NI_MAXHOST)
        var host = [CChar](repeating: 0, count: maxLength)
        let length: socklen_t

        switch family {
        case AF_INET:
            length = socklen_t(MemoryLayout<sockaddr_in>.size)
        case AF_INET6:
            length = socklen_t(MemoryLayout<sockaddr_in6>.size)
        default:
            return nil
        }

        let result = getnameinfo(
            socketAddress,
            length,
            &host,
            socklen_t(maxLength),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard result == 0 else {
            return nil
        }

        let address = String(cString: host)
        guard !address.isEmpty, !address.hasPrefix("fe80:") else {
            return nil
        }
        return address
    }
}

struct NetworkInterfaceSnapshot {
    let input: UInt64
    let output: UInt64
    let interface: String
    let addresses: [String]
}

func networkAddressSummary(_ addresses: [String]) -> String {
    guard !addresses.isEmpty else {
        return "--"
    }

    return addresses.joined(separator: ", ")
}
