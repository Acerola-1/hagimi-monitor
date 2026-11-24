import AppKit
import Combine
import Foundation

/// 一个被扫描发现的游戏候选。
/// `bundleID` 是去重与匹配的主键;`source` 只决定设置页的来源标签。
nonisolated struct GameHUDDiscoveredGame: Identifiable, Equatable, Sendable {
    let bundleID: String
    let name: String
    /// 应用包路径;Steam/Epic 清单关联失败时不产出该条目。
    let applicationURL: URL?
    let source: Source

    nonisolated enum Source: String, Sendable {
        case steam
        case epic
        /// 应用包自身声明了游戏类别(英文 canonical 或本地化类别名)。
        case applicationCategory

        var recognitionSource: GameHUDRecognitionSource {
            switch self {
            case .steam: .steamManifest
            case .epic: .epicManifest
            case .applicationCategory: .applicationCategory
            }
        }
    }

    var id: String { bundleID }
}

/// 一次扫描的结果。`failed` 只表示索引扫描本身不可用(命令无法执行/异常退出),
/// 某个来源目录不存在只是“这里没有游戏”,不是失败。
nonisolated struct GameHUDScanOutcome: Sendable {
    let games: [GameHUDDiscoveredGame]
    let failed: Bool
}

/// 启动器排除:Steam.app、Games.app、Epic Launcher 等平台本体的 Info.plist
/// 也声明 `public.app-category.games`(实测),类别扫描会命中它们。
/// 该名单只剔除“明显是启动器/商店”的条目,不参与“是不是游戏”的判定。
nonisolated enum GameHUDLauncherExclusions {
    /// bundle ID 精确匹配(小写)。
    static let bundleIDs: Set<String> = [
        "com.valvesoftware.steam",
        "com.valvesoftware.steamlink",
        "com.apple.games",
        "com.epicgames.epicgameslauncher",
        "com.heroicgameslauncher.hgl",
        "com.playcover.playcover",
        "com.codeweavers.crossover",
        "com.whisky.app",
        "net.lutris.lutris",
        "net.battlenet.app",
        "com.riotgames.client",
        "net.itch.itch",
        "com.gog.galaxy",
    ]

    /// 名称包含匹配(小写,处理改名/变体)。
    static let nameSubstrings: [String] = [
        "steam link", "steam app", "epic games launcher", "battle.net", "gog galaxy",
    ]
}

/// 游戏自动扫描器:聚合 Steam / Epic / 系统应用类别三个可解释来源,
/// 按 bundle ID 去重。扫描结果只是登记输入,由设置统一合并并自动采纳。
///
/// 来源与获取渠道:
/// - **Steam**:`libraryfolders.vdf` + `appmanifest_*.acf`,并按游戏名关联真实 `.app`;
/// - **Epic**:Manifests JSON 的 LaunchExecutable/InstallLocation,关联失败则跳过;
/// - **系统类别**:Spotlight 枚举应用包,读取 Info.plist 的
///   `LSApplicationCategoryType`。英文 canonical 与本地化类别名都能识别,
///   不依赖索引语言;索引缺失时由前台激活/手动添加兜底。
///
/// 去重顺序即优先级:Steam/Epic 带安装信息,优先于类别扫描。
/// 受总开关门控;设置页主动刷新允许一次独立扫描,不会打开总开关。
@MainActor
final class GameHUDGameScanner: ObservableObject {

    static let shared = GameHUDGameScanner()

    /// 缓存有效期:设置页停留期间反复刷新不重扫。
    static let cacheInterval: TimeInterval = 300
    /// 激活探测的最小重扫间隔:同一场游戏连续切窗口不重复扫。
    private static let rescanDebounce: TimeInterval = 30

    /// 扫描结果发布(AppDelegate 合并进统一登记、设置页显示状态)。
    @Published private(set) var discoveredGames: [GameHUDDiscoveredGame] = []
    /// 正在扫描指示(设置页刷新按钮转圈用)。
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanCompletedAt: Date?
    @Published private(set) var lastScanCount = 0
    @Published private(set) var lastScanFailed = false

    private var cachedGames: [GameHUDDiscoveredGame]?
    private var lastScanDate: Date?
    private var lastRescanDate: Date = .distantPast
    /// 目录监听源(Steam steamapps / Epic Manifests)。
    private var dirSources: [DispatchSourceFileSystemObject] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var periodicTimer: AnyCancellable?
    private var started = false

    private init() {}

    /// 常驻监听启动:目录监听 + 应用生命周期通知 + 自动定时扫描 + 启动即后台初扫。
    /// 由总开关门控,关闭时停止这里的一切轮询。
    func startMonitoring() {
        guard !started else { return }
        started = true
        performRescan(force: true)
        let steamApps = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps")
        var watchedPaths: Set<String> = []
        for library in Self.steamLibraryPaths(
            vdfURL: steamApps.appendingPathComponent("libraryfolders.vdf"),
            fallback: steamApps
        ) where watchedPaths.insert(library.path).inserted {
            watchDirectory(library)
        }
        watchDirectory(FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests"))
        let center = NSWorkspace.shared.notificationCenter
        let activated = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            let url = app.bundleURL
            Task { @MainActor in
                self?.handleActivation(bundleID: bundleID, name: name, appURL: url)
            }
        }
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            let url = app.bundleURL
            Task { @MainActor in
                self?.handleActivation(bundleID: bundleID, name: name, appURL: url)
            }
        }
        workspaceObservers = [activated, launched]

        periodicTimer = Timer.publish(every: 600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.rescanNow()
            }
    }

    /// 停止常驻监听，释放文件描述符、定时器与通知观察者。
    func stopMonitoring() {
        guard started else { return }
        started = false
        for source in dirSources {
            source.cancel()
        }
        dirSources.removeAll()
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()
        periodicTimer?.cancel()
        periodicTimer = nil
    }

    /// 丢弃缓存强制重扫(手动刷新按钮用)。
    func invalidate() {
        cachedGames = nil
        lastScanDate = nil
    }

    /// 常驻监听路径的扫描入口。
    func rescanNow(force: Bool = false) {
        guard started || force else { return }
        performRescan(force: force)
    }

    /// 设置页路径:即使总开关关闭也允许单次扫描,但不启动常驻监听。
    /// `force == false` 时仍遵守缓存,避免每次切回页面都重扫。
    func rescanFromSettings(force: Bool) {
        performRescan(force: force || !started)
    }

    /// 前台激活发现新候选时安排一次去抖重扫(商店清单证据靠这次扫描补全)。
    func requestRescanForActivatedGame() {
        scheduleRescan()
    }

    private func performRescan(force: Bool) {
        guard !isScanning else { return }
        if !force, let last = lastScanDate, Date().timeIntervalSince(last) < Self.cacheInterval, cachedGames != nil {
            return
        }
        isScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let outcome = GameHUDGameScanner.scanWithOutcome()
            DispatchQueue.main.async {
                guard let self else { return }
                self.cachedGames = outcome.games
                self.lastScanDate = Date()
                self.discoveredGames = outcome.games
                self.lastScanCount = outcome.games.count
                self.lastScanFailed = outcome.failed
                self.lastScanCompletedAt = Date()
                self.isScanning = false
            }
        }
    }

    /// 前台应用激活:不在缓存且存在类别或商店路径线索时补扫一次。
    /// 这里只决定“值不值得扫”,不把路径/Metal 当作识别证据,也不直接登记。
    private func handleActivation(bundleID: String, name: String, appURL: URL?) {
        guard !bundleID.isEmpty else { return }
        if bundleID.hasPrefix("com.apple.") { return }
        if cachedGames?.contains(where: { $0.bundleID == bundleID }) == true { return }
        if Self.isLauncher(bundleID: bundleID, name: name) { return }
        guard Self.isLikelyGame(appURL: appURL, bundleID: bundleID) else { return }
        scheduleRescan()
    }

    /// 去抖:30 秒内多次信号只扫一次。
    private func scheduleRescan() {
        guard Date().timeIntervalSince(lastRescanDate) >= Self.rescanDebounce else { return }
        lastRescanDate = Date()
        performRescan(force: false)
    }

    /// 仅用于触发重扫的线索:类别证据或商店安装目录。
    static func isLikelyGame(appURL: URL?, bundleID: String) -> Bool {
        guard let url = appURL else { return false }
        if GameHUDAutoDetection.isGameApplication(at: url) {
            return true
        }
        return GameHUDAutoDetection.storePathSource(for: url) != nil
    }

    /// 为名单游戏清理 per-app `MetalForceHudEnabled`,
    /// 避免 Apple 官方 HUD 出现干扰 Hagimi 自研 HUD。
    ///
    /// 只在“总开关开启且目标真正允许显示”的运行时路径调用(见 coordinator),
    /// 扫描结果、设置预览和黑名单操作都不会触发它。沙盒游戏(App Store)的容器偏好由 cfprefsd
    /// 保护,先按容器目录存在性跳过——stat 元数据读取不触发授权,零弹窗。
    nonisolated static func cleanupPerAppHUD(bundleID: String) {
        DispatchQueue.global(qos: .utility).async {
            let containerDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(bundleID)")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: containerDir.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return
            }
            let defaults = Process()
            defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            defaults.arguments = ["delete", bundleID, "MetalForceHudEnabled"]
            defaults.standardOutput = FileHandle.nullDevice
            defaults.standardError = FileHandle.nullDevice
            try? defaults.run()
            defaults.waitUntilExit()
        }
    }

    private func watchDirectory(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRescan()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dirSources.append(source)
    }

    // MARK: - 扫描聚合

    nonisolated static func scanWithOutcome() -> GameHUDScanOutcome {
        let categories = scanApplicationCategories()
        var byBundleID: [String: GameHUDDiscoveredGame] = [:]
        // 顺序即优先级:Steam/Epic 带安装信息,后扫的类别结果不覆盖已存在条目。
        for game in scanSteam() + scanEpic() + categories.games {
            if byBundleID[game.bundleID] == nil {
                byBundleID[game.bundleID] = game
            }
        }
        let sorted = byBundleID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return GameHUDScanOutcome(games: sorted, failed: categories.failed)
    }

    // MARK: - Steam

    /// 解析 libraryfolders.vdf + appmanifest_*.acf。
    /// VDF/ACF 都是「"key" "value" / { }」的 Valve 自有格式;只按行级结构
    /// 抽需要的字段(path / appid / name / installdir),不实现完整解析器。
    nonisolated static func scanSteam() -> [GameHUDDiscoveredGame] {
        let steamApps = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps")
        let libraryPaths = steamLibraryPaths(vdfURL: steamApps.appendingPathComponent("libraryfolders.vdf"), fallback: steamApps)
        var games: [GameHUDDiscoveredGame] = []
        for library in libraryPaths {
            let files = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
            for manifest in files where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard let fields = acfFields(at: manifest, keys: ["appid", "name", "installdir", "StateFlags"]),
                      let installdir = fields["installdir"],
                      steamManifestIsInstalled(stateFlags: fields["StateFlags"]) else {
                    continue
                }
                let commonDir = library.appendingPathComponent("common").appendingPathComponent(installdir)
                let gameName = fields["name"] ?? installdir
                // 不在多应用包目录里随便取第一个 .app:唯一候选或名称唯一匹配才采用。
                let candidates = GameHUDAppAssociation.candidates(inDirectory: commonDir, maxDepth: 2)
                guard let app = GameHUDAppAssociation.select(gameName: gameName, candidates: candidates) else {
                    continue
                }
                games.append(GameHUDDiscoveredGame(
                    bundleID: app.bundleID,
                    name: gameName,
                    applicationURL: app.url,
                    source: .steam
                ))
            }
        }
        return games
    }

    /// ACF `StateFlags` 是位掩码,`FullyInstalled`(4) 可与更新暂停(512)、
    /// 运行中等其他状态并存;只要求已完整安装,不要求数值恰好等于 4。
    /// 缺省字段按旧清单兼容为已安装,无法解析的值按未安装处理。
    nonisolated static func steamManifestIsInstalled(stateFlags: String?) -> Bool {
        guard let stateFlags else { return true }
        guard let flags = Int(stateFlags) else { return false }
        return flags & 4 != 0
    }

    /// 从单行 VDF/ACF 文本提取 `"key" "value"` 引号对，不依赖制表符分隔，并还原简单转义。
    nonisolated static func parseQuotedKeyValue(_ line: Substring) -> (key: String, value: String)? {
        var tokens: [String] = []
        var index = line.startIndex
        while index < line.endIndex, tokens.count < 2 {
            let ch = line[index]
            if ch == "\"" {
                index = line.index(after: index)
                var value = ""
                var escaped = false
                var closed = false
                while index < line.endIndex {
                    let current = line[index]
                    if escaped {
                        value.append(current)
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == "\"" {
                        closed = true
                        index = line.index(after: index)
                        break
                    } else {
                        value.append(current)
                    }
                    index = line.index(after: index)
                }
                guard closed else { return nil }
                tokens.append(value)
                continue
            }
            if ch == "/" {
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == "/" {
                    break
                }
            }
            index = line.index(after: index)
        }
        guard tokens.count == 2 else { return nil }
        return (tokens[0], tokens[1])
    }

    /// libraryfolders.vdf 里的 "path" 字段列表;解析失败回退默认库。
    nonisolated static func steamLibraryPaths(vdfURL: URL, fallback: URL) -> [URL] {
        guard let text = try? String(contentsOf: vdfURL, encoding: .utf8) else {
            return [fallback]
        }
        var paths: [URL] = []
        var seen: Set<String> = []
        for line in text.split(separator: "\n") {
            guard let pair = parseQuotedKeyValue(line),
                  pair.key == "path", !pair.value.isEmpty else { continue }
            let steamApps = URL(fileURLWithPath: pair.value).appendingPathComponent("steamapps")
            if seen.insert(steamApps.path).inserted {
                paths.append(steamApps)
            }
        }
        return paths.isEmpty ? [fallback] : paths
    }

    /// 抓 ACF 顶层字段(进 "AppState" depth == 1 即取, 跳过更深层嵌套节)。
    nonisolated static func acfFields(at url: URL, keys: [String]) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let keySet = Set(keys)
        var result: [String: String] = [:]
        var depth = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "{" {
                depth += 1
                continue
            }
            if trimmed == "}" {
                depth = max(0, depth - 1)
                continue
            }
            guard depth <= 1, let pair = parseQuotedKeyValue(line), keySet.contains(pair.key) else {
                continue
            }
            if result[pair.key] == nil {
                result[pair.key] = pair.value
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Epic

    nonisolated static func scanEpic() -> [GameHUDDiscoveredGame] {
        let manifests = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests")
        let files = (try? FileManager.default.contentsOfDirectory(at: manifests, includingPropertiesForKeys: nil)) ?? []
        var games: [GameHUDDiscoveredGame] = []
        for item in files where item.pathExtension == "item" {
            guard let data = try? Data(contentsOf: item),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = json["DisplayName"] as? String else {
                continue
            }
            let installLocation = json["InstallLocation"] as? String ?? ""
            let launchExecutable = json["LaunchExecutable"] as? String ?? ""
            guard !installLocation.isEmpty, !launchExecutable.isEmpty else { continue }
            guard let app = GameHUDAppAssociation.epicApplicationCandidate(
                launchExecutable: launchExecutable,
                installLocation: installLocation,
                gameName: name
            ) else {
                continue
            }
            games.append(GameHUDDiscoveredGame(
                bundleID: app.bundleID,
                name: name,
                applicationURL: app.url,
                source: .epic
            ))
        }
        return games
    }

    // MARK: - 系统应用类别

    /// 枚举应用包并读取包内类别。Spotlight 只作为可缺失的索引:
    /// 命令不可用时返回 failed,由激活/手动添加兜底,不影响已有登记。
    nonisolated static func scanApplicationCategories() -> (games: [GameHUDDiscoveredGame], failed: Bool) {
        let enumeration = applicationBundlePaths()
        var byBundleID: [String: GameHUDDiscoveredGame] = [:]
        for path in enumeration.paths {
            autoreleasepool {
                guard let game = categoryGame(at: URL(fileURLWithPath: path)),
                      byBundleID[game.bundleID] == nil else {
                    return
                }
                byBundleID[game.bundleID] = game
            }
        }
        return (Array(byBundleID.values), enumeration.failed)
    }

    /// 单个应用包的类别识别。拆出纯入口供夹具直接验证中英日类别与子类别,
    /// 不依赖 Spotlight 索引语言或测试机安装位置。
    nonisolated static func categoryGame(at url: URL) -> GameHUDDiscoveredGame? {
        guard let info = GameHUDAutoDetection.infoDictionary(at: url),
              let bundleID = info["CFBundleIdentifier"] as? String,
              !bundleID.isEmpty,
              let category = info["LSApplicationCategoryType"] as? String,
              GameHUDAutoDetection.isGameCategory(category) else {
            return nil
        }
        let name = GameHUDAutoDetection.applicationName(at: url, info: info)
        if isLauncher(bundleID: bundleID, name: name) {
            return nil
        }
        return GameHUDDiscoveredGame(
            bundleID: bundleID,
            name: name,
            applicationURL: url,
            source: .applicationCategory
        )
    }

    nonisolated private static let ignoredBundlePathComponents: [String] = [
        "/.Trash/",
        "/DerivedData/",
        "/Backups.backupdb/",
        "/CoreSimulator/",
        "/node_modules/",
        "/.build/",
    ]

    nonisolated private static func applicationBundlePaths() -> (paths: [String], failed: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == \"com.apple.application-bundle\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ([], true)
        }
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWorkItem.cancel()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return ([], true)
        }
        var seen: Set<String> = []
        var paths: [String] = []
        for line in text.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            guard path.hasSuffix(".app"), !path.hasPrefix("/System/") else { continue }
            guard !ignoredBundlePathComponents.contains(where: { path.contains($0) }) else { continue }
            // 只接受最外层应用包,跳过 .app 内部嵌套的 helper/插件。
            guard path.components(separatedBy: ".app").count <= 2 else { continue }
            guard seen.insert(path).inserted else { continue }
            paths.append(path)
        }
        return (paths, false)
    }

    // MARK: - 工具

    /// 已知启动器/商店平台本体(见 GameHUDLauncherExclusions 文档)。
    nonisolated static func isLauncher(bundleID: String, name: String) -> Bool {
        if GameHUDLauncherExclusions.bundleIDs.contains(bundleID.lowercased()) {
            return true
        }
        let lowered = name.lowercased()
        return GameHUDLauncherExclusions.nameSubstrings.contains { lowered.contains($0) }
    }
}
