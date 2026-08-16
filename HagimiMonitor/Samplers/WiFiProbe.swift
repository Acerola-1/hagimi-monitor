import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// Wi-Fi 信号与网关延迟探针(只读、可降级)。
///
/// 数据源:
/// - RSSI / SSID 走 CoreWLAN。沙盒下依赖 airportd XPC,部分环境会失败——
///   失败即返 nil(UI 显"--"),不影响其余网络指标;
/// - 网关地址读 SCDynamicStore `State:/Network/Global/IPv4` 的 Router 字段;
/// - 延迟用 TCP connect 探测网关可达性:连接成功或立即 RST(ECONNREFUSED)
///   都视为可达并计时,超时 300ms 判为不可测。不依赖 ICMP raw socket,
///   沙盒的 network.client entitlement 即可满足。
///
/// 全部结果短窗口缓存:CoreWLAN 调用与 socket 探测都不便宜,
/// 不能随每秒采样无脑触发。
final class WiFiProbe {
    struct Snapshot {
        var ssid: String?
        var rssi: Int?
        var gatewayLatencyMs: Int?
    }

    private let rssiCacheInterval: TimeInterval = 10
    private let latencyCacheInterval: TimeInterval = 5

    private var rssiCache: (ssid: String?, rssi: Int?, timestamp: Date)?
    private var latencyCache: (ms: Int?, timestamp: Date)?

    // SCDynamicStore 会话进程内只建一次(与 NetworkSampler 同理)。
    private lazy var dynamicStore: SCDynamicStore? =
        SCDynamicStoreCreate(nil, "HagimiMonitor.WiFiProbe" as CFString, nil, nil)

    func snapshot() -> Snapshot {
        let now = Date()
        let wifi: (ssid: String?, rssi: Int?)
        if let cache = rssiCache, now.timeIntervalSince(cache.timestamp) < rssiCacheInterval {
            wifi = (cache.ssid, cache.rssi)
        } else {
            wifi = readWiFi()
            rssiCache = (wifi.ssid, wifi.rssi, now)
        }
        return Snapshot(ssid: wifi.ssid, rssi: wifi.rssi, gatewayLatencyMs: cachedLatency(now: now))
    }

    // MARK: RSSI / SSID

    private func readWiFi() -> (ssid: String?, rssi: Int?) {
        // CWWiFiClient 在个别系统状态下抛异常/返回 nil 都按「无 Wi-Fi」降级。
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
            return (nil, nil)
        }
        let ssid = interface.ssid()
        let rssi = interface.rssiValue()
        // 未关联任何网络时 rssiValue 返 0,非有效读数。
        return (ssid, rssi < 0 ? rssi : nil)
    }

    // MARK: 网关延迟

    private func cachedLatency(now: Date) -> Int? {
        if let cache = latencyCache, now.timeIntervalSince(cache.timestamp) < latencyCacheInterval {
            return cache.ms
        }
        let ms: Int?
        if let gateway = defaultGatewayAddress() {
            ms = measureConnectLatency(to: gateway, timeoutMs: 300)
        } else {
            ms = nil
        }
        latencyCache = (ms, now)
        return ms
    }

    /// 当前默认网关(IPv4)。无网络/仅有 IPv6 时返 nil。
    private func defaultGatewayAddress() -> sockaddr_in? {
        guard let store = dynamicStore,
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = value["Router"] as? String else {
            return nil
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, router, &address.sin_addr) == 1 else { return nil }
        return address
    }

    /// TCP connect 计时:非阻塞 connect 后 poll 等可写。
    /// 连接成功(端口开放)与 ECONNREFUSED(立即 RST)都证明网关可达,
    /// 两者耗时即往返延迟;超时/其他错误返 nil。
    private func measureConnectLatency(to gateway: sockaddr_in, timeoutMs: Int) -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // 探测端口选 443:无论开放还是拒绝,回包都快;不选 80 避免个别网关重定向拖慢。
        var target = gateway
        target.sin_port = in_port_t(443).bigEndian

        let start = DispatchTime.now()
        let connectResult = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        func elapsedMs() -> Int {
            let nanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
            return Int(nanos / 1_000_000)
        }

        if connectResult == 0 {
            return max(1, elapsedMs())
        }
        guard errno == EINPROGRESS else { return nil }

        var pollFd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollFd, 1, Int32(timeoutMs)) > 0 else { return nil }

        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
        guard socketError == 0 || socketError == ECONNREFUSED else { return nil }
        return max(1, elapsedMs())
    }
}
