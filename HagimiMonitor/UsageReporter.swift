import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 匿名使用心跳上报：每天最多一次，失败会做少量重试，绝不阻塞或影响主流程。
/// 直接上报到 PostHog，只携带匿名安装 UUID、App 版本、系统版本、芯片型号、语言、分发渠道，不采集任何可识别个人身份的信息。
///
/// 触发方式：
/// - App 启动时立即检查一次（`.launch`）。
/// - 启动后台周期计时器，每隔 `checkInterval` 检查一次（`.periodic`），覆盖长期常驻后台、
///   不重启也不打开设置窗口的场景；同一个计时器也承担了失败重试的职责——只有成功发送后
///   才会把"今天已上报"落盘，失败的话下一次 tick 会自然重新尝试，不需要额外的重试队列。
final class UsageReporter: @unchecked Sendable {
    static let shared = UsageReporter()

    enum Trigger: String {
        case launch
        case periodic
    }

    private static let apiKey = "phc_o8tBafcRN23obG9XtNurWPhPdpBXZ8yH4D7hMeK2xGYH"
    /// 周期检查间隔：不是发送间隔——多数 tick 会因为"今天已上报"而直接跳过，不产生网络请求。
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    private static let maxAttempts = 3
    private static let retryDelay: TimeInterval = 5

    private let endpoint: URL?
    private let defaults: UserDefaults
    private let session: URLSession
    private let installID: String

    /// 串行队列：既是周期计时器的执行队列，也用来保护 `isSending`，避免启动触发和
    /// 计时器 tick 撞在一起时并发发出两次请求。
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.usage-report", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isSending = false

    private init(
        endpoint: URL? = URL(string: "https://us.i.posthog.com/capture/"),
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.defaults = defaults
        self.session = session
        self.installID = UsageReporter.loadOrCreateInstallID(defaults: defaults)
    }

    /// 启动后台周期检查计时器，应用生命周期内只需调用一次。
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.checkInterval, repeating: Self.checkInterval)
        timer.setEventHandler { [weak self] in self?.reportIfNeeded(trigger: .periodic) }
        timer.resume()
        self.timer = timer
    }

    /// 若今天还没成功上报过，异步发送一次心跳；失败时会重试几次，仍失败则放弃，
    /// 等下一次触发（周期 tick 或下次启动）再试。
    func reportIfNeeded(trigger: Trigger) {
        guard let endpoint else { return }
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isSending else { return }
            let today = UsageReporter.dateString(Date())
            guard self.defaults.string(forKey: Keys.lastReportedDate) != today else { return }
            self.isSending = true

            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                let body = self.payload(trigger: trigger)
                let succeeded = await self.send(body: body, to: endpoint)
                self.queue.async {
                    self.isSending = false
                    if succeeded {
                        self.defaults.set(today, forKey: Keys.lastReportedDate)
                    }
                }
            }
        }
    }

    /// 最多重试 `maxAttempts` 次，仅在收到 2xx 响应时视为成功。
    private func send(body: [String: Any], to endpoint: URL) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        for attempt in 1...Self.maxAttempts {
            if let (_, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                return true
            }
            if attempt < Self.maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(Self.retryDelay * 1_000_000_000))
            }
        }
        return false
    }

    private func payload(trigger: Trigger) -> [String: Any] {
        var properties: [String: String] = [
            "trigger": trigger.rawValue,
            "os_version": UsageReporter.osVersionString(),
            "chip": UsageReporter.chipName(),
            "locale": Locale.current.identifier,
        ]

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            properties["app_version"] = appVersion
        }

        #if DIRECT_DISTRIBUTION
        properties["distribution"] = "direct"
        #else
        properties["distribution"] = "appstore"
        #endif

        return [
            "api_key": UsageReporter.apiKey,
            "event": "app_ping",
            "distinct_id": installID,
            "properties": properties,
        ]
    }

    private static func loadOrCreateInstallID(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: Keys.installID) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Keys.installID)
        return generated
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dateString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    private static func chipName() -> String {
        if let brand = sysctlString(name: "machdep.cpu.brand_string") {
            return brand
        }
        return sysctlString(name: "hw.model") ?? "unknown"
    }

    private static func sysctlString(name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

private enum Keys {
    static let installID = "telemetry.installID"
    static let lastReportedDate = "telemetry.lastReportedDate"
}
