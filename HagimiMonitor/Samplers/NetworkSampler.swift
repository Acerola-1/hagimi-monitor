import Darwin
import Foundation
import OSLog
import SystemConfiguration

final class NetworkSampler: MonitorSampler {
    var kind: MonitorKind { .network }

    private var previousNetworkBytes: (input: UInt64, output: UInt64, timestamp: Date)?
    private var publicIPCache: (ip: String, timestamp: Date)?
    private let publicIPRefreshInterval: TimeInterval = 30
    private let publicIPLock = NSLock()
    private var isRefreshingPublicIP = false
    private var interfaceTypeCache: [String: CFString] = [:]

    func sample(previous: MonitorModule?) -> MonitorModule {
        let now = Date()
        let bytes = networkBytes()
        let previousBytes = previousNetworkBytes
        previousNetworkBytes = (bytes.input, bytes.output, now)

        let publicIP = cachedPublicIP()

        guard let previousBytes else {
            return MonitorModule(
                kind: .network,
                value: 0,
                summary: bytes.interface,
                metrics: [
                    MonitorMetric(name: "ip-address", value: networkAddressSummary(bytes.addresses)),
                    MonitorMetric(name: "public-ip", value: publicIP),
                    MonitorMetric(name: "upload", value: "--"),
                    MonitorMetric(name: "download", value: "--"),
                    MonitorMetric(name: "cumulativeBytesIn", value: "\(bytes.input)"),
                    MonitorMetric(name: "cumulativeBytesOut", value: "\(bytes.output)")
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
                MonitorMetric(name: "ip-address", value: networkAddressSummary(bytes.addresses)),
                MonitorMetric(name: "public-ip", value: publicIP),
                MonitorMetric(name: "upload", value: bytesPerSecond(upload)),
                MonitorMetric(name: "download", value: bytesPerSecond(download)),
                MonitorMetric(name: "cumulativeBytesIn", value: "\(bytes.input)"),
                MonitorMetric(name: "cumulativeBytesOut", value: "\(bytes.output)")
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
            return NetworkInterfaceSnapshot(input: 0, output: 0, interface: "disconnected", addresses: [])
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

        let primaryName = primaryInterfaceName()
        let activeKey = primaryName.flatMap { totalsByInterface[$0] != nil ? $0 : nil }

        let total = totalsByInterface.values.reduce((input: UInt64(0), output: UInt64(0))) { partial, next in
            (partial.input + next.input, partial.output + next.output)
        }

        AppLogger.sampler.info("Network interfaces detected: \(totalsByInterface.keys.joined(separator: ", "), privacy: .public), primary: \(primaryName ?? "none", privacy: .public), active: \(activeKey ?? "none", privacy: .public)")

        return NetworkInterfaceSnapshot(
            input: total.input,
            output: total.output,
            interface: networkInterfaceTitle(activeKey),
            addresses: activeKey.flatMap { addressesByInterface[$0] } ?? []
        )
    }

    private func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "HagimiMonitor.NetworkSampler" as CFString, nil, nil) else {
            return nil
        }
        guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = global["PrimaryInterface"] as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func cachedPublicIP() -> String {
        let now = Date()

        publicIPLock.lock()
        if let cache = publicIPCache, now.timeIntervalSince(cache.timestamp) < publicIPRefreshInterval {
            publicIPLock.unlock()
            return cache.ip
        }

        let cachedValue = publicIPCache?.ip ?? "--"
        let shouldRefresh = !isRefreshingPublicIP
        if shouldRefresh {
            isRefreshingPublicIP = true
        }
        publicIPLock.unlock()

        if shouldRefresh {
            refreshPublicIP(startedAt: now)
        }

        return cachedValue
    }

    private func refreshPublicIP(startedAt: Date) {
        let url = URL(string: "https://api.ipify.org")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            let ip = data
                .flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let error {
                AppLogger.sampler.error("Public IP refresh failed: \(error.localizedDescription, privacy: .public)")
            }

            publicIPLock.lock()
            if let ip, !ip.isEmpty {
                publicIPCache = (ip, Date())
            } else {
                publicIPCache = (publicIPCache?.ip ?? "--", startedAt)
            }
            isRefreshingPublicIP = false
            publicIPLock.unlock()
        }
        task.resume()
    }

    private func networkInterfaceTitle(_ name: String?) -> String {
        guard let name else {
            return "disconnected"
        }

        if let type = interfaceType(for: name) {
            switch type {
            case kSCNetworkInterfaceTypeIEEE80211:
                return "Wi-Fi"
            case kSCNetworkInterfaceTypeEthernet:
                return "ethernet"
            case kSCNetworkInterfaceTypeWWAN:
                return "cellular"
            case kSCNetworkInterfaceTypeBond:
                return "bond"
            case kSCNetworkInterfaceTypeFireWire:
                return "FireWire"
            default:
                break
            }
        }

        if name.hasPrefix("bridge") {
            return "bridge"
        }
        if name.hasPrefix("pdp_ip") {
            return "cellular"
        }
        return name
    }

    private func interfaceType(for bsdName: String) -> CFString? {
        if let cached = interfaceTypeCache[bsdName] {
            return cached
        }
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return nil
        }
        for interface in interfaces {
            if let name = SCNetworkInterfaceGetBSDName(interface) as String?,
               let type = SCNetworkInterfaceGetInterfaceType(interface) {
                interfaceTypeCache[name] = type
            }
        }
        return interfaceTypeCache[bsdName]
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
