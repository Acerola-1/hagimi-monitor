import Darwin
import Foundation
import OSLog
import SystemConfiguration

/// 公网 IP 查询的启用与在飞状态。每次关闭令旧请求失效:旧回调携带的
/// generation 不再相等,不会清除新一轮的在飞标记,也不会继续尝试备用源。
nonisolated struct PublicIPQueryState {
    private(set) var isEnabled = true
    private(set) var isRefreshing = false
    private(set) var generation: UInt64 = 0

    /// 返回本次应启动的新请求代次;关闭或重复设置返回 nil。
    mutating func setEnabled(_ enabled: Bool) -> UInt64? {
        guard isEnabled != enabled else { return nil }
        isEnabled = enabled
        guard enabled else {
            generation &+= 1
            isRefreshing = false
            return nil
        }
        return beginRefresh()
    }

    /// 仅当前启用代次且没有在飞请求时开始;重复采样不会叠加请求。
    mutating func beginRefresh() -> UInt64? {
        guard isEnabled, !isRefreshing else { return nil }
        isRefreshing = true
        return generation
    }

    func isCurrent(_ requestGeneration: UInt64) -> Bool {
        isEnabled && requestGeneration == generation
    }

    /// 仅当前代次可结束并清在飞标记;旧回调不影响新一轮状态。
    @discardableResult
    mutating func finish(_ requestGeneration: UInt64) -> Bool {
        guard requestGeneration == generation else { return false }
        isRefreshing = false
        return true
    }
}

/// 采样器由 SystemMonitorSampler 持有并在串行采样循环中调用，内部状态单线程顺序更新。
nonisolated final class NetworkSampler: MonitorSampler, @unchecked Sendable {
    var kind: MonitorKind { .network }

    private var previousNetworkBytes: (input: UInt64, output: UInt64, timestamp: Date)?
    private var publicIPCache: (ip: String, timestamp: Date)?
    private let publicIPRefreshInterval: TimeInterval = 30
    private let publicIPLock = NSLock()
    /// 默认开启以保持直接调用采样器的原有行为;MonitorStore 在面板隐藏时关闭。
    private var publicIPQueryState = PublicIPQueryState()
    private var interfaceTypeCache: [String: CFString] = [:]
    private var interfaceTypeCacheDate: Date?
    private let interfaceTypeRefreshInterval: TimeInterval = 30

    // SCDynamicStore 会话:每秒重新 SCDynamicStoreCreate 是无谓开销,进程内只建一次。
    private let dynamicStore: SCDynamicStore? =
        SCDynamicStoreCreate(nil, "HagimiMonitor.NetworkSampler" as CFString, nil, nil)

    // Wi-Fi 信号/网关延迟探针:内部带缓存,RSSI 10s、延迟 5s,不随每秒采样无脑触发。
    private let wifiProbe = WiFiProbe()

    func sample(previous: MonitorModule?) -> MonitorModule {
        let now = Date()
        let bytes = networkBytes()
        let previousBytes = previousNetworkBytes
        previousNetworkBytes = (bytes.input, bytes.output, now)

        let publicIP = cachedPublicIP()
        let ipv4 = bytes.ipv4.first ?? "--"
        let ipv6 = bytes.ipv6.first ?? "--"

        // Wi-Fi 信号/SSID/网关延迟(A6):探针失败时全部降级为"--"。
        // 顺序对齐冻结原型网格配对:(信号, 延迟),SSID 长值整行展示。
        // 接口名指标已删:行头 summary 展示的就是接口名,明细再列一遍是冗余。
        let wifi = wifiProbe.snapshot()
        let wifiMetrics = [
            MonitorMetric(name: "wifi-rssi", value: wifi.rssi.map { "\($0) dBm" } ?? "--", numericValue: wifi.rssi.map(Double.init), unit: " dBm"),
            MonitorMetric(name: "gateway-latency", value: wifi.gatewayLatencyMs.map { "\($0) ms" } ?? "--", numericValue: wifi.gatewayLatencyMs.map(Double.init), unit: " ms"),
            MonitorMetric(name: "wifi-ssid", value: wifi.ssid ?? "--")
        ]

        guard let previousBytes else {
            return MonitorModule(
                kind: .network,
                value: 0,
                summary: bytes.interface,
                metrics: [
                    MonitorMetric(name: "ipv4", value: ipv4),
                    MonitorMetric(name: "ipv6", value: ipv6),
                    MonitorMetric(name: "public-ip", value: publicIP),
                    MonitorMetric(name: "upload", value: "--"),
                    MonitorMetric(name: "download", value: "--"),
                    MonitorMetric(name: "cumulativeBytesIn", value: "\(bytes.input)"),
                    MonitorMetric(name: "cumulativeBytesOut", value: "\(bytes.output)")
                ] + wifiMetrics,
                samples: seedSamples(0)
            )
        }

        let delta = max(0.1, now.timeIntervalSince(previousBytes.timestamp))
        // 计数器回绕/主接口切换会使累计字节数下降,此时该方向增量按 0 计,
        // 避免无保护的减法回绕出巨值、瞬时冲到满格(与磁盘采样口径一致)。
        let uploadBytes = bytes.output >= previousBytes.output ? bytes.output - previousBytes.output : 0
        let downloadBytes = bytes.input >= previousBytes.input ? bytes.input - previousBytes.input : 0
        let upload = Double(uploadBytes) / delta
        let download = Double(downloadBytes) / delta
        let value = min(100, log10(max(1, upload + download)) * 14)

        return MonitorModule(
            kind: .network,
            value: value,
            summary: bytes.interface,
            metrics: [
                MonitorMetric(name: "ipv4", value: ipv4),
                MonitorMetric(name: "ipv6", value: ipv6),
                MonitorMetric(name: "public-ip", value: publicIP),
                MonitorMetric(name: "upload", value: bytesPerSecond(upload), numericValue: upload),
                MonitorMetric(name: "download", value: bytesPerSecond(download), numericValue: download),
                MonitorMetric(name: "cumulativeBytesIn", value: "\(bytes.input)"),
                MonitorMetric(name: "cumulativeBytesOut", value: "\(bytes.output)")
            ] + wifiMetrics,
            samples: seedSamples(value)
        )
    }

    private func networkBytes() -> NetworkInterfaceSnapshot {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        var totalsByInterface: [String: (input: UInt64, output: UInt64)] = [:]
        var ipv4ByInterface: [String: [String]] = [:]
        var ipv6ByInterface: [String: [String]] = [:]

        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            AppLogger.sampler.error("getifaddrs failed, errno: \(errno)")
            return NetworkInterfaceSnapshot(input: 0, output: 0, interface: "disconnected", ipv4: [], ipv6: [])
        }
        defer { freeifaddrs(addressList) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else {
                continue
            }

            guard let name = String(validatingCString: interface.ifa_name), !name.isEmpty else {
                continue
            }
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

            case AF_INET:
                guard let addressText = ipAddress(from: address) else {
                    continue
                }

                var addresses = ipv4ByInterface[name] ?? []
                if !addresses.contains(addressText) {
                    addresses.append(addressText)
                    ipv4ByInterface[name] = addresses
                }

            case AF_INET6:
                guard let addressText = ipAddress(from: address) else {
                    continue
                }

                var addresses = ipv6ByInterface[name] ?? []
                if !addresses.contains(addressText) {
                    addresses.append(addressText)
                    ipv6ByInterface[name] = addresses
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

        return NetworkInterfaceSnapshot(
            input: total.input,
            output: total.output,
            interface: networkInterfaceTitle(activeKey),
            ipv4: activeKey.flatMap { ipv4ByInterface[$0] } ?? [],
            ipv6: activeKey.flatMap { ipv6ByInterface[$0] } ?? []
        )
    }

    private func primaryInterfaceName() -> String? {
        guard let store = dynamicStore else {
            return nil
        }
        guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let name = global["PrimaryInterface"] as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    /// 面板可见且公网 IP 指标仍开启时才允许发请求。关掉时保留上次成功值,不再新开连接。
    /// 从关到开时把缓存时间标成过期,让这次切换立刻重查,而不是等满 30 秒。
    func setPublicIPQueriesEnabled(_ enabled: Bool) {
        publicIPLock.lock()
        let wasEnabled = publicIPQueryState.isEnabled
        if enabled && !wasEnabled, let cache = publicIPCache {
            publicIPCache = (cache.ip, .distantPast)
        }
        let requestGeneration = publicIPQueryState.setEnabled(enabled)
        publicIPLock.unlock()
        if let requestGeneration {
            refreshPublicIP(startedAt: Date(), generation: requestGeneration)
        }
    }

    private func cachedPublicIP() -> String {
        let now = Date()

        publicIPLock.lock()
        guard publicIPQueryState.isEnabled else {
            let cachedValue = publicIPCache?.ip ?? "--"
            publicIPLock.unlock()
            return cachedValue
        }
        if let cache = publicIPCache, now.timeIntervalSince(cache.timestamp) < publicIPRefreshInterval {
            publicIPLock.unlock()
            return cache.ip
        }

        let cachedValue = publicIPCache?.ip ?? "--"
        let requestGeneration = publicIPQueryState.beginRefresh()
        publicIPLock.unlock()

        if let requestGeneration {
            refreshPublicIP(startedAt: now, generation: requestGeneration)
        }

        return cachedValue
    }

    /// 公网 IP 查询服务列表，按优先级排列。
    /// ip.3322.net 和 ipinfo.io 在大陆网络下稳定可达；ipify 在部分网络不可达，放最后。
    private static let publicIPProviders: [String] = [
        "https://ip.3322.net",
        "https://ipinfo.io/ip",
        "https://checkip.amazonaws.com",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
        "https://api.ipify.org",
    ]

    /// 使用 inet_pton 严格校验 IPv4/IPv6 字符串，避免把 HTML 错误页(Cloudflare 521 等)误识别为 IP。
    private static func isValidIP(_ s: String) -> Bool {
        return s.withCString { ptr in
            var addr4 = in_addr()
            var addr6 = in6_addr()
            return inet_pton(AF_INET, ptr, &addr4) == 1 ||
                   inet_pton(AF_INET6, ptr, &addr6) == 1
        }
    }

    private func refreshPublicIP(startedAt: Date, generation: UInt64) {
        fetchPublicIPFrom(providers: Self.publicIPProviders, startedAt: startedAt, generation: generation)
    }

    private func fetchPublicIPFrom(providers: [String], startedAt: Date, generation: UInt64) {
        publicIPLock.lock()
        let isCurrent = publicIPQueryState.isCurrent(generation)
        publicIPLock.unlock()
        // 关闭后旧代次不再顺着备用服务开新请求,也不会清除新一轮的启用/在飞状态。
        guard isCurrent else { return }
        guard let provider = providers.first else {
            // 所有源都失败，保留旧缓存
            AppLogger.sampler.error("Public IP refresh failed: all providers exhausted")
            publicIPLock.lock()
            if publicIPQueryState.isCurrent(generation) {
                publicIPCache = (publicIPCache?.ip ?? "--", startedAt)
                publicIPQueryState.finish(generation)
            }
            publicIPLock.unlock()
            return
        }

        let remaining = Array(providers.dropFirst())
        let url = URL(string: provider)!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            let ip = data
                .flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let ip, Self.isValidIP(ip) {
                publicIPLock.lock()
                if publicIPQueryState.isCurrent(generation) {
                    publicIPCache = (ip, Date())
                    publicIPQueryState.finish(generation)
                }
                publicIPLock.unlock()
            } else {
                if let error {
                    AppLogger.sampler.warning("Public IP provider \(provider) failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    AppLogger.sampler.warning("Public IP provider \(provider) returned invalid response")
                }
                // 当前源失败，尝试下一个;旧代次由入口守卫直接丢弃。
                fetchPublicIPFrom(providers: remaining, startedAt: startedAt, generation: generation)
            }
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
        // 缓存未命中:可能是新插入的接口,也可能是 SCNetworkInterfaceCopyAll 里根本不存在的
        // 虚拟/VPN 主接口。后者若每秒都重扫整表,会每秒触发一次昂贵的 SCNetworkInterfaceCopyAll,
        // 故对整表重扫加时间闸门:最多每 interfaceTypeRefreshInterval 秒重扫一次。
        let now = Date()
        if let last = interfaceTypeCacheDate, now.timeIntervalSince(last) < interfaceTypeRefreshInterval {
            return nil
        }
        interfaceTypeCacheDate = now
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

        guard let address = host.withUnsafeBufferPointer({ pointer in
            pointer.baseAddress.flatMap { String(validatingCString: $0) }
        }), !address.isEmpty, !address.hasPrefix("fe80:") else {
            return nil
        }
        return address
    }
}

struct NetworkInterfaceSnapshot {
    let input: UInt64
    let output: UInt64
    let interface: String
    let ipv4: [String]
    let ipv6: [String]
}

func networkAddressSummary(_ addresses: [String]) -> String {
    guard !addresses.isEmpty else {
        return "--"
    }

    return addresses.joined(separator: ", ")
}
