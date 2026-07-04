import Foundation

@MainActor
@Observable
final class UpdateChecker {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    /// 供设置面板打开等入口触发自动检查、供 `AboutSettingsView` 观察同一份状态。
    static let shared = UpdateChecker()

    private(set) var state: UpdateCheckState = .idle
    private var lastCheckedAt: Date?

    private let latestReleaseURL: URL
    private let currentVersionProvider: () -> String
    private let dataLoader: DataLoader

    init(
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/Acerola-1/hagimi-monitor/releases/latest")!,
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        },
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.latestReleaseURL = latestReleaseURL
        self.currentVersionProvider = currentVersionProvider
        self.dataLoader = dataLoader
    }

    var currentVersion: String {
        currentVersionProvider()
    }

    /// 供设置窗口打开等自动触发场景使用：距上次检查未超过 `minInterval` 时直接跳过，避免每次开窗都打一次 GitHub API 并打断已展示的更新提示。
    func checkForUpdatesIfStale(minInterval: TimeInterval = 30 * 60) async {
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < minInterval {
            return
        }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !state.isChecking else { return }
        lastCheckedAt = Date()
        state = .checking

        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HagimiMonitor", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await dataLoader(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                state = .failed(failureMessage(for: response, data: data))
                return
            }

            let release: GitHubRelease
            do {
                release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            } catch {
                state = .failed(String(localized: "update.parse-failed"))
                return
            }
            let latestVersion = VersionParser.normalize(release.tagName)

            guard !latestVersion.isEmpty else {
                state = .failed(String(localized: "update.version-parse-failed"))
                return
            }

            if VersionParser.isNewer(latestVersion, than: currentVersion) {
                let downloadURL = Self.resolveDownloadURL(from: release)
                state = .updateAvailable(
                    latestVersion: latestVersion,
                    publishedAt: release.publishedAt,
                    downloadURL: downloadURL,
                    releaseNotes: release.body
                )
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(String(localized: "update.network-error"))
        }
    }

    func reset() {
        state = .idle
    }

    static func resolveDownloadURL(from release: GitHubRelease) -> URL {
        if let assets = release.assets {
            for asset in assets {
                let name = asset.name.lowercased()
                if name.hasSuffix(".dmg") || name.hasSuffix(".zip") {
                    return asset.browserDownloadURL
                }
            }
        }
        return release.htmlURL
    }

    private func failureMessage(for response: URLResponse, data: Data) -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            return String(localized: "update.temp-unavailable")
        }

        switch httpResponse.statusCode {
        case 403, 429:
            return String(localized: "update.rate-limited")
        case 404:
            return String(localized: "update.no-release")
        case 500...599:
            return String(localized: "update.github-unavailable")
        default:
            if let githubError = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data),
               let message = githubError.message,
               !message.isEmpty {
                return String(localized: "update.check-failed") + "\(message)"
            }
            return String(localized: "update.temp-unavailable")
        }
    }
}

enum VersionParser {
    static func normalize(_ tag: String) -> String {
        var result = tag.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("v") || result.hasPrefix("V") {
            result.removeFirst()
        }
        return result
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let lhsParts = parse(lhs)
        let rhsParts = parse(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l > r { return true }
            if l < r { return false }
        }
        return false
    }

    private static func parse(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}
