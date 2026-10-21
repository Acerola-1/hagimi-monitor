import AppKit
import Foundation

/// 应用包身份读取。添加/排除只需要 bundle ID、名称与包路径,
/// 不要求用户输入或查询内部标识。
nonisolated struct GameHUDApplicationIdentity: Equatable, Sendable {
    let bundleID: String
    let name: String
    let applicationURL: URL

    init?(applicationURL: URL) {
        guard applicationURL.pathExtension.lowercased() == "app" else { return nil }
        let info = GameHUDAutoDetection.infoDictionary(at: applicationURL)
        guard let bundleID = info?["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            return nil
        }
        self.bundleID = bundleID
        self.name = GameHUDAutoDetection.applicationName(at: applicationURL, info: info)
        self.applicationURL = applicationURL
    }

    var applicationPath: String { applicationURL.path }
}

/// 自动识别证据与 Steam/Epic 目标包关联。
///
/// 识别只看可解释证据:
/// - 应用包 Info.plist 的游戏类别(英文 canonical ID 与本地化类别名都接受);
/// - Steam/Epic 安装清单,并尽量关联清单对应的真实 .app。
/// 路径相似或使用 Metal/OpenGL 本身只用于触发一次重扫,不构成识别依据。
nonisolated enum GameHUDAutoDetection {
    /// 类别值包含以下任一标记即视为游戏类别。
    /// 英文 canonical ID(public.app-category.*-games)、本地化父/子类别都能命中,
    /// 因此不依赖系统语言或 Spotlight 索引语言。
    static let gameCategoryTokens: [String] = [
        "games", "游戏", "遊戲", "ゲーム", "게임",
    ]

    static func isGameCategory(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if normalized.contains("public.app-category") {
            return normalized.contains("game")
        }
        return gameCategoryTokens.contains { normalized.contains($0) }
    }

    /// 读取应用包 Info.plist;失败或不是应用包返回 nil。
    static func infoDictionary(at applicationURL: URL) -> [String: Any]? {
        let infoURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    static func applicationName(at applicationURL: URL, info: [String: Any]? = nil) -> String {
        let info = info ?? infoDictionary(at: applicationURL)
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = info?[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return applicationURL.deletingPathExtension().lastPathComponent
    }

    /// 应用包是否以稳定类别证据声明为游戏。
    static func isGameApplication(at applicationURL: URL) -> Bool {
        let category = infoDictionary(at: applicationURL)?["LSApplicationCategoryType"] as? String
        return isGameCategory(category)
    }

    /// 前台激活兜底:类别证据可即时登记;商店安装路径只用于安排一次重扫。
    static func storePathSource(for applicationURL: URL?) -> GameHUDRecognitionSource? {
        guard let path = applicationURL?.path else { return nil }
        if path.contains("/Steam/steamapps/common/") {
            return .steamManifest
        }
        if path.contains("/Epic Games/") {
            return .epicManifest
        }
        return nil
    }
}

/// 一个已被安装清单定位到的 .app 候选。
nonisolated struct GameHUDAppCandidate: Equatable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
}

/// 安装清单到真实应用包的关联。
///
/// 安装目录可能包含工具、启动器和多个应用包;这里只在“唯一候选”或
/// “名称唯一匹配”时采用,歧义时跳过该清单,宁可少一条自动识别,
/// 也不编造 bundle ID。
nonisolated enum GameHUDAppAssociation {
    static func candidates(inDirectory directory: URL, maxDepth: Int = 1) -> [GameHUDAppCandidate] {
        let urls = applicationBundleURLs(inDirectory: directory, maxDepth: maxDepth)
        var seen: Set<String> = []
        var result: [GameHUDAppCandidate] = []
        for url in urls {
            guard let identity = GameHUDApplicationIdentity(applicationURL: url),
                  !seen.contains(identity.bundleID) else { continue }
            seen.insert(identity.bundleID)
            result.append(GameHUDAppCandidate(url: url, name: identity.name, bundleID: identity.bundleID))
        }
        return result
    }

    static func select(gameName: String, candidates: [GameHUDAppCandidate]) -> GameHUDAppCandidate? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return candidates[0]
        }
        let normalizedGame = normalize(gameName)
        guard !normalizedGame.isEmpty else { return nil }
        let scored = candidates.map { candidate -> (candidate: GameHUDAppCandidate, score: Int) in
            let normalizedCandidate = normalize(candidate.name)
            let score: Int
            if normalizedCandidate == normalizedGame {
                score = 3
            } else if normalizedCandidate.contains(normalizedGame) || normalizedGame.contains(normalizedCandidate) {
                score = 2
            } else {
                score = 0
            }
            return (candidate, score)
        }
        guard let best = scored.map(\.score).max(), best >= 2 else { return nil }
        let winners = scored.filter { $0.score == best }
        guard winners.count == 1 else { return nil }
        return winners[0].candidate
    }

    /// Epic 清单的 `LaunchExecutable` 可能指向 `.app` 内部可执行文件,
    /// 也可能是安装目录内的相对路径。能从路径里确定 `.app` 时直接用,
    /// 否则退回按游戏名在安装目录内关联。
    static func epicApplicationCandidate(
        launchExecutable: String,
        installLocation: String,
        gameName: String
    ) -> GameHUDAppCandidate? {
        if let appURL = applicationBundleURL(inPath: launchExecutable),
           let identity = GameHUDApplicationIdentity(applicationURL: appURL) {
            return GameHUDAppCandidate(url: appURL, name: identity.name, bundleID: identity.bundleID)
        }
        let installURL = URL(fileURLWithPath: installLocation)
        return select(
            gameName: gameName,
            candidates: candidates(inDirectory: installURL, maxDepth: 2)
        )
    }

    static func applicationBundleURL(inPath path: String) -> URL? {
        guard let range = path.range(of: ".app", options: [.caseInsensitive]) else { return nil }
        let appPath = String(path[..<range.upperBound])
        return appPath.isEmpty ? nil : URL(fileURLWithPath: appPath)
    }

    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }

    private static func applicationBundleURLs(inDirectory directory: URL, maxDepth: Int) -> [URL] {
        guard maxDepth >= 0 else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var result: [URL] = []
        var subdirectories: [URL] = []
        for item in contents {
            if item.pathExtension.lowercased() == "app" {
                result.append(item)
                continue
            }
            guard maxDepth > 0,
                  (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            subdirectories.append(item)
        }
        for subdirectory in subdirectories {
            result.append(contentsOf: applicationBundleURLs(
                inDirectory: subdirectory,
                maxDepth: maxDepth - 1
            ))
        }
        return result
    }
}
