import AppKit
import Combine
import Foundation

/// 一个被扫描发现的游戏候选。
/// `bundleID` 是去重与匹配的主键;`source` 只决定设置页的来源标签。
nonisolated struct GameHUDDiscoveredGame: Identifiable, Equatable, Sendable {
    let bundleID: String
    let name: String
    /// 可执行文件路径(受控启动用);Spotlight 来源可能拿不到,为 nil。
    let executableURL: URL?
    /// Steam AppID(Steam 来源才有;steam_appid.txt 自动预备用)。
    let steamAppID: String?
    let source: Source

    nonisolated enum Source: String, Sendable {
        case steam
        case epic
        case spotlight

        var titleKey: String.LocalizationValue {
            switch self {
            case .steam: "gamehud.scanner.source.steam"
            case .epic: "gamehud.scanner.source.epic"
            case .spotlight: "gamehud.scanner.source.spotlight"
            }
        }
    }

    var id: String { bundleID }
}

/// 游戏自动扫描器:聚合 Steam / Epic / 系统类别三个来源,按 bundle ID 去重。
///
/// 来源与数据契约(2026-09-26 实机调研):
/// - **Steam**:`~/Library/Application Support/Steam/steamapps/libraryfolders.vdf`
///   列出全部库分区;每区 `appmanifest_*.acf` 提供游戏名与 installdir,
///   `steamapps/common/<installdir>/*.app` 即游戏本体,读 Info.plist 得 bundle ID。
/// - **Epic**:`~/Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests/*.item`
///   (JSON:DisplayName/InstallLocation/LaunchExecutable)。用户机未装 Epic 时目录
///   不存在,扫出空集。
/// - **系统类别**:Spotlight 查询 `kMDItemAppStoreCategory == "Games"` 的 .app。
///   Apple Games.app 的游戏库由私有守护进程 gamed 维护,无公开 API;但其识别
///   结果与「Info.plist 声明 Games 类别」高度重合,走公开 Spotlight 索引可覆盖
///   /Applications 与 App Store 游戏,不依赖私有框架。
///
/// 去重:同一游戏可能同时被 Steam 清单和 Spotlight 命中(同一个 .app 文件),
/// 以 bundle ID 为唯一键,先到来源优先(Steam/Epic 带完整安装信息,优先于 Spotlight)。
/// 受总开关门控，由目录变更、有效游戏激活与 5 分钟缓存控制驱动。
///
/// 启动器排除:Steam.app、Games.app、Epic Launcher 等平台本体的 Info.plist
/// 也声明 `public.app-category.games`(实测),Spotlight 会把它们当游戏扫进来。
/// 静态排除名单只用于剔除「明显是启动器/商店」的条目,不用于判定「是游戏」——
/// 后者仍由用户勾选确认(保守原则)。
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
/// 监听节奏(设计定案 2026-09-26):
/// - **目录监听**:DispatchSource 盯 Steam steamapps 与 Epic Manifests 目录。
///   装新 Steam/Epic 游戏必然在这两处落新 manifest 文件,事件驱动零轮询。
/// - **前台激活探测**:App Store/独立安装游戏没有清单目录可听,但用户装完
///   一般立刻打开——监听 NSWorkspace 激活通知,前台 bundle ID 不在已知名单
///   且不在本次扫描缓存里时补扫一次(Spotlight 扫描本身有 3s 上限,频率极低)。
/// - 两种信号都只触发「重扫 + 更新发布」,名单变更是否采纳仍由用户决定
///   (发现列表只增不自动加,保守原则)。
@MainActor
final class GameHUDGameScanner: ObservableObject {

    static let shared = GameHUDGameScanner()

    /// 缓存有效期:设置页停留期间反复刷新不重扫。
    private static let cacheInterval: TimeInterval = 300
    /// 激活探测的最小重扫间隔:同一场游戏连续切窗口不重复扫。
    private static let rescanDebounce: TimeInterval = 30

    /// 扫描结果发布(设置页「自动发现」列表消费)。
    @Published private(set) var discoveredGames: [GameHUDDiscoveredGame] = []
    /// 最近一次扫描结果的 bundle ID 快照(供名单匹配;扫描未完成前为空)。
    private(set) var knownGameBundleIDs: Set<String> = []
    /// 正在扫描指示(设置页刷新按钮转圈用)。
    @Published private(set) var isScanning = false

    private var cachedGames: [GameHUDDiscoveredGame]?
    private var lastScanDate: Date?
    private var lastRescanDate: Date = .distantPast
    /// 目录监听源(Steam steamapps / Epic Manifests)。
    private var dirSources: [DispatchSourceFileSystemObject] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var periodicTimer: AnyCancellable?
    private var started = false

    private init() {}

    /// 常驻监听启动:目录监听 + 应用生命周期通知 + 自动定时扫描 (每 10 分钟) + 启动即后台初扫。
    func startMonitoring() {
        guard !started else { return }
        started = true
        // 启动即在后台执行一次扫描,保证 knownGameBundleIDs 与发现列表及早落定
        rescanNow(force: true)
        watchDirectory(FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps"))
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

        // 自动定时扫描:每 10 分钟在后台轮询一次游戏目录与 Spotlight,自动发现新装游戏
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

    nonisolated private static func watchPathCandidates() -> [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Steam/steamapps"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests"),
        ]
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

    /// 前台应用激活:目标是名单/缓存外的新 bundle(装完新游戏就立刻打开的场景)。
    private func handleActivation(bundleID: String, name: String, appURL: URL?) {
        guard !bundleID.isEmpty else { return }
        // 系统应用跳过，避免 Finder/Safari/Xcode 等日常切换触发重扫
        if bundleID.hasPrefix("com.apple.") { return }
        // 已在缓存或名单关注范围内:不扫。
        if cachedGames?.contains(where: { $0.bundleID == bundleID }) == true { return }
        // 明显是启动器/系统应用:不扫。
        if GameHUDGameScanner.isLauncher(bundleID: bundleID, name: name) { return }
        // 过滤非游戏普通应用: 仅当位于游戏目录或包信息声明为游戏时才调度重扫
        guard GameHUDGameScanner.isLikelyGame(appURL: appURL, bundleID: bundleID) else { return }

        // 快速登记当前已激活的新游戏，避免 5 分钟 cacheInterval 导致刚安装并运行的游戏无法被即时识别
        if let url = appURL, !knownGameBundleIDs.contains(bundleID) {
            knownGameBundleIDs.insert(bundleID)
            let newGame = GameHUDDiscoveredGame(
                bundleID: bundleID,
                name: name.isEmpty ? url.deletingPathExtension().lastPathComponent : name,
                executableURL: url,
                steamAppID: nil,
                source: url.path.contains("steamapps/common") ? .steam : (url.path.contains("Epic Games") ? .epic : .spotlight)
            )
            if !discoveredGames.contains(where: { $0.bundleID == bundleID }) {
                discoveredGames.append(newGame)
                discoveredGames.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        scheduleRescan()
    }

    nonisolated static func isLikelyGame(appURL: URL?, bundleID: String) -> Bool {
        guard let url = appURL else { return false }
        let path = url.path
        if path.contains("steamapps/common") || path.contains("Epic Games") {
            return true
        }
        if let bundle = Bundle(url: url) {
            if let category = bundle.infoDictionary?["LSApplicationCategoryType"] as? String,
               category.localizedCaseInsensitiveContains("games") {
                return true
            }
        }
        return false
    }

    /// 去抖:30 秒内多次信号只扫一次。
    private func scheduleRescan() {
        guard Date().timeIntervalSince(lastRescanDate) >= Self.rescanDebounce else { return }
        lastRescanDate = Date()
        rescanNow()
    }

    /// 为名单游戏清理 per-app `MetalForceHudEnabled`,
    /// 避免 Apple 官方 HUD 出现干扰 Hagimi 自研 HUD。
    /// 沙盒游戏(App Store)的容器偏好由 cfprefsd 保护,先按容器目录存在性
    /// 跳过——stat 元数据读取不触发「App 管理」授权,零弹窗。写失败静默。
    /// 移入后台 utility 队列执行外部进程，避免阻塞主线程。
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

    /// 丢弃缓存强制重扫(刷新按钮用)。
    func invalidate() {
        cachedGames = nil
        lastScanDate = nil
    }

    /// 立即重扫并发布(刷新按钮与监听信号共用)。
    func rescanNow(force: Bool = false) {
        guard started || force else { return }
        guard !isScanning else { return }
        if !force, let last = lastScanDate, Date().timeIntervalSince(last) < Self.cacheInterval, cachedGames != nil {
            return
        }
        isScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let games = GameHUDGameScanner.scan()
            let bundleIDs = Set(games.map(\.bundleID))
            DispatchQueue.main.async {
                self?.knownGameBundleIDs = bundleIDs
                self?.cachedGames = games
                self?.lastScanDate = Date()
                self?.discoveredGames = games
                self?.isScanning = false
            }
        }
    }

    nonisolated static func scan() -> [GameHUDDiscoveredGame] {
        var byBundleID: [String: GameHUDDiscoveredGame] = [:]
        // 顺序即优先级:Steam/Epic 带安装信息,后扫的 Spotlight 不覆盖已存在的。
        for game in scanSteam() + scanEpic() + scanSpotlight() {
            if byBundleID[game.bundleID] == nil {
                byBundleID[game.bundleID] = game
            }
        }
        return byBundleID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                guard let fields = acfFields(at: manifest, keys: ["appid", "name", "installdir"]),
                      let installdir = fields["installdir"] else {
                    continue
                }
                // StateFlags == 4 表示 Fully Installed;损坏/更新中清单跳过。
                if let flags = acfFields(at: manifest, keys: ["StateFlags"])?["StateFlags"], flags != "4" {
                    continue
                }
                let commonDir = library.appendingPathComponent("common").appendingPathComponent(installdir)
                guard let bundleID = firstGameBundleID(in: commonDir) else { continue }
                games.append(GameHUDDiscoveredGame(
                    bundleID: bundleID,
                    name: fields["name"] ?? installdir,
                    executableURL: firstExecutable(in: commonDir),
                    steamAppID: fields["appid"],
                    source: .steam
                ))
            }
        }
        return games
    }

    /// libraryfolders.vdf 里的 "path" 字段列表;解析失败回退默认库。
    nonisolated private static func steamLibraryPaths(vdfURL: URL, fallback: URL) -> [URL] {
        guard let text = try? String(contentsOf: vdfURL, encoding: .utf8) else {
            return [fallback]
        }
        var paths: [URL] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 形如 "path" "/Users/xxx/Library/Application Support/Steam"
            guard trimmed.hasPrefix("\"path\"") else { continue }
            let parts = trimmed.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            let value = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t")) ?? ""
            guard !value.isEmpty else { continue }
            paths.append(URL(fileURLWithPath: value).appendingPathComponent("steamapps"))
        }
        return paths.isEmpty ? [fallback] : paths
    }

    /// 抓 ACF 顶层字段(进 "AppState" 一层即取,不递归嵌套节)。
    nonisolated private static func acfFields(at url: URL, keys: [String]) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for key in keys {
                if result[key] == nil, trimmed.hasPrefix("\"\(key)\"") {
                    // "key"  "value"
                    let segments = trimmed.split(separator: "\t").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t")) }
                    if segments.count >= 2 {
                        result[key] = segments[1]
                    }
                }
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
            // 只收原生 Mac 安装: 检查 InstallLocation 与 LaunchExecutable 并定位可执行文件。
            let installLocation = json["InstallLocation"] as? String ?? ""
            let launchExecutable = json["LaunchExecutable"] as? String ?? ""
            guard !installLocation.isEmpty, !launchExecutable.isEmpty else { continue }
            let executable = URL(fileURLWithPath: installLocation).appendingPathComponent(launchExecutable)
            // Epic 的 LaunchExecutable 形如 "Game/Binaries/Mac/Game.app" 或 ".../Mac/Game"。
            let appURL = executable.path.contains(".app")
                ? URL(fileURLWithPath: executable.path)
                : URL(fileURLWithPath: installLocation)
            guard let bundleID = bundleID(ofAppAt: appURL) else { continue }
            games.append(GameHUDDiscoveredGame(
                bundleID: bundleID,
                name: name,
                executableURL: appURL,
                steamAppID: nil,
                source: .epic
            ))
        }
        return games
    }

    // MARK: - 系统类别(Spotlight)

    /// 扫描声明为 Games 类别的 .app(App Store 类别全集,含子类)。
    nonisolated static func scanSpotlight() -> [GameHUDDiscoveredGame] {
        var byBundle: [String: GameHUDDiscoveredGame] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: gameCategories.count) { index in
            for game in categoryGames(category: gameCategories[index]) {
                lock.lock()
                if byBundle[game.bundleID] == nil {
                    byBundle[game.bundleID] = game
                }
                lock.unlock()
            }
        }
        return Array(byBundle.values)
    }

    /// App Store 游戏类别全集(公开枚举):父类 + 各子类。
    /// 实测:鸣潮等 App Store 游戏声明的是子类别("Action Games"),只查
    /// "Games" 会漏,故枚举全部类别。
    nonisolated static let gameCategories: [String] = [
        "Games",
        "Action Games",
        "Adventure Games",
        "Role Playing Games",
        "Board Games",
        "Card Games",
        "Casino Games",
        "Dice Games",
        "Educational Games",
        "Family Games",
        "Kids Games",
        "Music Games",
        "Puzzle Games",
        "Racing Games",
        "Simulation Games",
        "Sports Games",
        "Strategy Games",
        "Trivia Games",
        "Word Games",
    ]

    /// 单类别扫描:调用 `mdfind`(Spotlight 的官方命令行接口)。
    ///
    /// 注:NSMetadataQuery(API 版)实测在本 app 内对 kMDItemAppStoreCategory
    /// 查询返回 0 条,而 mdfind 命令行同一查询稳定命中——故走进程调用,
    /// 输出即路径列表,行为可预期(沙盒版无此问题:未启用扫描)。
    nonisolated private static func categoryGames(category: String) -> [GameHUDDiscoveredGame] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemAppStoreCategory == \"\(category)\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var games: [GameHUDDiscoveredGame] = []
        for line in text.split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            // 系统应用本体(Games.app 等)不进候选。
            guard path.hasSuffix(".app"), !path.hasPrefix("/System/") else { continue }
            let appURL = URL(fileURLWithPath: path)
            guard let bundleID = bundleID(ofAppAt: appURL) else { continue }
            let name = appURL.deletingPathExtension().lastPathComponent
            if isLauncher(bundleID: bundleID, name: name) { continue }
            games.append(GameHUDDiscoveredGame(
                bundleID: bundleID,
                name: name,
                executableURL: appURL,
                steamAppID: nil,
                source: .spotlight
            ))
        }
        return games
    }

    // MARK: - 工具

    /// 目录下第一个 .app 的 bundle ID(Steam 游戏目录通常恰有一个 .app)。
    nonisolated private static func firstGameBundleID(in directory: URL) -> String? {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in contents where item.pathExtension == "app" {
            if let id = bundleID(ofAppAt: item) {
                return id
            }
        }
        return nil
    }

    nonisolated private static func firstExecutable(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    nonisolated private static func bundleID(ofAppAt url: URL) -> String? {
        guard let bundle = Bundle(url: url) else { return nil }
        return bundle.bundleIdentifier
    }

    /// 已知启动器/商店平台本体(见 GameHUDLauncherExclusions 文档)。
    nonisolated private static func isLauncher(bundleID: String, name: String) -> Bool {
        if GameHUDLauncherExclusions.bundleIDs.contains(bundleID.lowercased()) {
            return true
        }
        let lowered = name.lowercased()
        return GameHUDLauncherExclusions.nameSubstrings.contains { lowered.contains($0) }
    }
}
