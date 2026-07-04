import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 匿名使用心跳上报：每天最多一次，失败静默忽略，绝不阻塞或影响主流程。
/// 直接上报到 PostHog，只携带匿名安装 UUID、App 版本、系统版本、芯片型号、语言、分发渠道，不采集任何可识别个人身份的信息。
final class UsageReporter: @unchecked Sendable {
    static let shared = UsageReporter()

    enum Trigger: String {
        case launch
        case settings
    }

    private static let apiKey = "phc_o8tBafcRN23obG9XtNurWPhPdpBXZ8yH4D7hMeK2xGYH"

    private let endpoint: URL?
    private let defaults: UserDefaults
    private let session: URLSession
    private let installID: String

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

    /// 若今天还没上报过，异步发送一次心跳；网络失败/超时/不可达时静默放弃，不重试、不影响调用方。
    /// 上报标记在派发后台任务前就同步写入，避免短时间内的两次调用都读到"今天未上报"而重复发送。
    func reportIfNeeded(trigger: Trigger) {
        guard let endpoint else { return }
        let today = UsageReporter.dateString(Date())
        guard defaults.string(forKey: Keys.lastReportedDate) != today else { return }
        defaults.set(today, forKey: Keys.lastReportedDate)

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let body = self.payload(trigger: trigger)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 8
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            _ = try? await self.session.data(for: request)
        }
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
