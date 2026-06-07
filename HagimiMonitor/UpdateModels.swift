import Foundation

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(latestVersion: String, publishedAt: String?, downloadURL: URL, releaseNotes: String?)
    case failed(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let publishedAt: String?
    let name: String?
    let body: String?
    let assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case name, body, assets
    }
}

struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubErrorResponse: Decodable {
    let message: String?
}
