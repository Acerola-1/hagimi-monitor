import Foundation

@MainActor
@Observable
final class UpdateChecker {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private(set) var state: UpdateCheckState = .idle

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

    func checkForUpdates() async {
        guard !state.isChecking else { return }
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
                state = .failed("无法解析更新信息")
                return
            }
            let latestVersion = VersionParser.normalize(release.tagName)

            guard !latestVersion.isEmpty else {
                state = .failed("无法解析版本号")
                return
            }

            if VersionParser.isNewer(latestVersion, than: currentVersion) {
                let downloadURL = resolveDownloadURL(from: release)
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
            state = .failed("网络错误")
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

    private func resolveDownloadURL(from release: GitHubRelease) -> URL {
        Self.resolveDownloadURL(from: release)
    }

    private func failureMessage(for response: URLResponse, data: Data) -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            return "暂时无法检查更新"
        }

        switch httpResponse.statusCode {
        case 403, 429:
            return "检查更新过于频繁，请稍后再试"
        case 404:
            return "暂时没有可用的发布版本"
        case 500...599:
            return "GitHub 暂时不可用，请稍后再试"
        default:
            if let githubError = try? JSONDecoder().decode(GitHubErrorResponse.self, from: data),
               let message = githubError.message,
               !message.isEmpty {
                return "无法检查更新：\(message)"
            }
            return "暂时无法检查更新"
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
