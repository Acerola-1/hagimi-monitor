import Foundation
import Testing
@testable import HagimiMonitor

struct VersionParserTests {

    @Test func normalizeStripsVPrefix() {
        #expect(VersionParser.normalize("v1.2.3") == "1.2.3")
    }

    @Test func normalizeStripsUpperVPrefix() {
        #expect(VersionParser.normalize("V1.2.3") == "1.2.3")
    }

    @Test func normalizeKeepsPlainVersion() {
        #expect(VersionParser.normalize("1.2.3") == "1.2.3")
    }

    @Test func normalizeTrimsWhitespace() {
        #expect(VersionParser.normalize("  v1.2.3  ") == "1.2.3")
    }

    @Test func newerVersionDetected() {
        #expect(VersionParser.isNewer("1.1.0", than: "1.0.0"))
    }

    @Test func olderVersionNotNewer() {
        #expect(!VersionParser.isNewer("1.0.0", than: "1.1.0"))
    }

    @Test func sameVersionNotNewer() {
        #expect(!VersionParser.isNewer("1.0.0", than: "1.0.0"))
    }

    @Test func multiDigitComponents() {
        #expect(VersionParser.isNewer("1.10.0", than: "1.9.0"))
    }

    @Test func differentMajorVersion() {
        #expect(VersionParser.isNewer("2.0.0", than: "1.9.9"))
    }

    @Test func twoPartVersion() {
        #expect(VersionParser.isNewer("1.2", than: "1.1"))
    }

    @Test func unequalComponentCount() {
        #expect(VersionParser.isNewer("1.2.1", than: "1.2"))
    }
}

struct GitHubReleaseDecodingTests {

    @Test func decodeMinimalRelease() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "html_url": "https://github.com/Acerola-1/hagimi-monitor/releases/tag/v1.0.0",
            "published_at": "2026-06-07T12:00:00Z",
            "name": "v1.0.0",
            "body": "First release",
            "assets": [
                {
                    "name": "HagimiMonitor.dmg",
                    "browser_download_url": "https://github.com/Acerola-1/hagimi-monitor/releases/download/v1.0.0/HagimiMonitor.dmg"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #expect(release.tagName == "v1.0.0")
        #expect(release.htmlURL.absoluteString.contains("v1.0.0"))
        #expect(release.name == "v1.0.0")
        #expect(release.body == "First release")
        #expect(release.assets?.count == 1)
        #expect(release.assets?.first?.name == "HagimiMonitor.dmg")
    }

    @Test func decodeReleaseWithoutOptionalFields() throws {
        let json = """
        {
            "tag_name": "v0.1.0",
            "html_url": "https://github.com/test/test/releases/tag/v0.1.0"
        }
        """
        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #expect(release.tagName == "v0.1.0")
        #expect(release.publishedAt == nil)
        #expect(release.body == nil)
        #expect(release.assets == nil)
    }
}

@MainActor
struct UpdateCheckerTests {

    @Test func checkForUpdatesReportsAvailableRelease() async throws {
        let releaseURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases/tag/v1.1.0")!
        let assetURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases/download/v1.1.0/HagimiMonitor.dmg")!
        let checker = UpdateChecker(
            currentVersionProvider: { "1.0.0" },
            dataLoader: { request in
                #expect(request.value(forHTTPHeaderField: "User-Agent") == "HagimiMonitor")
                let json = """
                {
                    "tag_name": "v1.1.0",
                    "html_url": "\(releaseURL.absoluteString)",
                    "published_at": "2026-06-07T15:38:02Z",
                    "assets": [
                        {
                            "name": "HagimiMonitor.dmg",
                            "browser_download_url": "\(assetURL.absoluteString)"
                        }
                    ]
                }
                """
                return (
                    json.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await checker.checkForUpdates()

        #expect(checker.state == .updateAvailable(
            latestVersion: "1.1.0",
            publishedAt: "2026-06-07T15:38:02Z",
            downloadURL: assetURL,
            releaseNotes: nil
        ))
    }

    @Test func checkForUpdatesReportsUpToDate() async {
        let checker = UpdateChecker(
            currentVersionProvider: { "1.1.0" },
            dataLoader: { request in
                let json = """
                {
                    "tag_name": "v1.1.0",
                    "html_url": "https://github.com/Acerola-1/hagimi-monitor/releases/tag/v1.1.0"
                }
                """
                return (
                    json.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await checker.checkForUpdates()

        #expect(checker.state == .upToDate)
    }

    @Test func checkForUpdatesMapsRateLimitToFriendlyMessage() async {
        let checker = UpdateChecker(
            dataLoader: { request in
                (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 403,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await checker.checkForUpdates()

        #expect(checker.state == .failed("检查更新过于频繁，请稍后再试"))
    }

    @Test func checkForUpdatesMapsMissingReleaseToFriendlyMessage() async {
        let checker = UpdateChecker(
            dataLoader: { request in
                (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await checker.checkForUpdates()

        #expect(checker.state == .failed("暂时没有可用的发布版本"))
    }

    @Test func checkForUpdatesHandlesDecodeFailure() async {
        let checker = UpdateChecker(
            dataLoader: { request in
                (
                    Data("{}".utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        await checker.checkForUpdates()

        #expect(checker.state == .failed("无法解析更新信息"))
    }

    @Test func resolveDownloadURLFallsBackToReleasePage() throws {
        let releaseURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases/tag/v1.0.0")!
        let json = """
        {
            "tag_name": "v1.0.0",
            "html_url": "\(releaseURL.absoluteString)",
            "assets": [
                {
                    "name": "checksums.txt",
                    "browser_download_url": "https://github.com/Acerola-1/hagimi-monitor/releases/download/v1.0.0/checksums.txt"
                }
            ]
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(UpdateChecker.resolveDownloadURL(from: release) == releaseURL)
    }
}
