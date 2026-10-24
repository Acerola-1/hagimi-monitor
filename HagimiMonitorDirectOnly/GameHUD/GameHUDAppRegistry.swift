import AppKit
import Foundation


/// Game HUD 偏好键的唯一登记。共享的 MonitorSettings 只引用这些常量,
/// 登记存储与迁移逻辑不重复拼字符串。
nonisolated enum GameHUDPreferenceKeys {
    static let masterEnabled = "settings.gameHUD.masterEnabled"
    static let masterEnabledResolved = "settings.gameHUD.masterEnabledResolved"
    static let masterEnabledDefaultOnMigrated = "settings.gameHUD.masterEnabledDefaultOnMigrated"
    static let enabledMetrics = "settings.gameHUD.enabledMetrics"
    static let registryData = "settings.gameHUD.registry"
    static let registryCorruptBackupPrefix = "settings.gameHUD.registry.corruptBackup."
    static let customGames = "settings.gameHUD.customGames"
    static let excludedGames = "settings.gameHUD.excludedGames"
    static let side = "settings.gameHUD.side"
    static let presentationStyle = "settings.gameHUD.presentationStyle"
    static let backgroundTransparencyCard = "settings.gameHUD.backgroundTransparency.card"
    static let backgroundTransparencyTopStrip = "settings.gameHUD.backgroundTransparency.topStrip"
    static let fpsMigrated = "settings.gameHUD.fpsMigrated"
    static let newMetricsV2Migrated = "settings.gameHUD.newMetricsV2Migrated"
    static let memoryPressureMigrated = "settings.gameHUD.memoryPressureMigrated"
}

/// 自动识别来源:用户能核对的“为什么它被当成游戏”。
///
/// 来源与获取渠道分开:扫描或前台激活只是发现方式,不能把“系统扫描”写成来源;
/// Steam/Epic 安装清单与应用包声明的游戏类别才是可解释依据。
/// 仅使用 Metal/OpenGL 或路径字符串相似不构成来源(见 game-hud spec)。
nonisolated enum GameHUDRecognitionSource: String, Codable, Sendable {
    case steamManifest
    case epicManifest
    case applicationCategory

    /// 多个来源并存时只展示一条更具体的来源;安装清单优先于类别推断。
    var displayPriority: Int {
        switch self {
        case .steamManifest: 0
        case .epicManifest: 1
        case .applicationCategory: 2
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .steamManifest: "gamehud.source.steam"
        case .epicManifest: "gamehud.source.epic"
        case .applicationCategory: "gamehud.source.category"
        }
    }
}

/// 用户手动添加的来源标记。
///
/// `previouslyAdded` 只用于从旧版 custom 名单迁移的记录:旧数据没有来源字段。
/// 内部保留迁移来源用于兼容与诊断,界面统一按“手动添加”呈现。
nonisolated enum GameHUDManualOrigin: String, Codable, Sendable {
    case userAdded
    case previouslyAdded
}

/// 名单行上紧邻名称的标记。颜色只作补充,文字本身表达状态。
nonisolated enum GameHUDListBadge: String, Equatable, Sendable {
    case automatic
    case manual

    var titleKey: String.LocalizationValue {
        switch self {
        case .automatic: "gamehud.games.badge.auto"
        case .manual: "gamehud.games.badge.manual"
        }
    }
}

/// 一条统一应用登记。自动来源、手动添加与黑名单都落在这条记录上,
/// 避免视图临时拼接多个集合,防止“能显示却无法管理”。
nonisolated struct GameHUDRegisteredApp: Codable, Equatable, Sendable, Identifiable {
    let bundleID: String
    var name: String
    var applicationPath: String?
    var sources: Set<GameHUDRecognitionSource>
    var manualOrigin: GameHUDManualOrigin?
    /// 黑名单具有最高优先级;为 true 时来源与手动意图都原样保留,供移出排除后恢复。
    var isExcluded: Bool

    var id: String { bundleID }

    var hasRecognitionSource: Bool { !sources.isEmpty }

    /// 是否具备启用意图。黑名单不修改这个值,只压过最终的显示资格。
    var hasEnablementIntent: Bool { hasRecognitionSource || manualOrigin != nil }

    /// 显示资格:有自动来源或手动添加意图,且不在黑名单。
    var isEnabled: Bool { hasEnablementIntent && !isExcluded }

    /// 行内展示的主来源:最具体的一条;没有自动来源时由手动来源文案兜底。
    var primarySource: GameHUDRecognitionSource? {
        sources.min { lhs, rhs in
            if lhs.displayPriority == rhs.displayPriority {
                return lhs.rawValue < rhs.rawValue
            }
            return lhs.displayPriority < rhs.displayPriority
        }
    }

    /// 行内标记。提前排除、尚未被识别且无手动意图的记录没有可声明的来源,
    /// 返回 nil,不能伪标成自动识别。
    var badge: GameHUDListBadge? {
        // 旧数据的手动添加来源在界面上一律呈现「手动添加」;内部保留迁移来源,
        // 只用于兼容与诊断,界面不再暴露第二套标记。
        if manualOrigin != nil {
            return .manual
        }
        return sources.isEmpty ? nil : .automatic
    }

    init(
        bundleID: String,
        name: String,
        applicationPath: String? = nil,
        sources: Set<GameHUDRecognitionSource> = [],
        manualOrigin: GameHUDManualOrigin? = nil,
        isExcluded: Bool = false
    ) {
        self.bundleID = bundleID
        self.name = name
        self.applicationPath = applicationPath
        self.sources = sources
        self.manualOrigin = manualOrigin
        self.isExcluded = isExcluded
    }
}

/// 扫描输入:只携带可核对的来源与应用包路径,不直接写设置。
nonisolated struct GameHUDScannedApp: Equatable, Sendable {
    let bundleID: String
    let name: String
    let applicationPath: String?
    let source: GameHUDRecognitionSource

    init(bundleID: String, name: String, applicationPath: String?, source: GameHUDRecognitionSource) {
        self.bundleID = bundleID
        self.name = name
        self.applicationPath = applicationPath
        self.source = source
    }
}

/// 一次登记修改的结果,供设置页给出对象明确的反馈。
nonisolated struct GameHUDRegistryChange: Equatable, Sendable {
    let createdRecord: Bool
    /// 修改前已在黑名单。
    let wasExcluded: Bool
    /// 修改后的显示资格。
    let isEnabled: Bool
}

/// 唯一的应用登记所有者。
///
/// 合并规则:
/// - 按 bundle ID 去重,来源取并集,扫描元数据合并;
/// - 扫描缺席不删除记录(扫描漏项不等于卸载);
/// - 合并从不修改黑名单,晚到扫描不能复活被排除应用;
/// - 用户决定(手动添加/黑名单)与自动来源各自保存,不互相覆盖。
nonisolated struct GameHUDAppRegistry: Codable, Equatable, Sendable {
    static let currentSchema = 1

    var schema: Int
    var records: [String: GameHUDRegisteredApp]

    init(schema: Int = GameHUDAppRegistry.currentSchema, records: [String: GameHUDRegisteredApp] = [:]) {
        self.schema = schema
        self.records = records
    }

    /// 启用名单:有自动来源或手动添加意图,且不在黑名单。按名称稳定排序。
    var enabledApps: [GameHUDRegisteredApp] {
        records.values
            .filter(\.isEnabled)
            .sorted(by: Self.displayOrder)
    }

    /// 黑名单独立成组;即使从未被扫描发现也保留名称/身份,便于移出排除。
    var excludedApps: [GameHUDRegisteredApp] {
        records.values
            .filter(\.isExcluded)
            .sorted(by: Self.displayOrder)
    }

    func record(for bundleID: String) -> GameHUDRegisteredApp? {
        records[bundleID]
    }

    func isEligible(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        return records[bundleID]?.isEnabled == true
    }

    /// 合并扫描元数据。返回是否有可见变化(黑名单与来源都按并集/保留处理)。
    @discardableResult
    mutating func merge(scannedApps: [GameHUDScannedApp]) -> Bool {
        var changed = false
        for app in scannedApps {
            guard !app.bundleID.isEmpty else { continue }
            if var record = records[app.bundleID] {
                if record.sources.insert(app.source).inserted {
                    changed = true
                }
                if !app.name.isEmpty, app.name != record.name {
                    record.name = app.name
                    changed = true
                }
                if let path = app.applicationPath, !path.isEmpty, path != record.applicationPath {
                    record.applicationPath = path
                    changed = true
                }
                if changed {
                    records[app.bundleID] = record
                }
            } else {
                records[app.bundleID] = GameHUDRegisteredApp(
                    bundleID: app.bundleID,
                    name: app.name.isEmpty ? app.bundleID : app.name,
                    applicationPath: app.applicationPath,
                    sources: [app.source]
                )
                changed = true
            }
        }
        return changed
    }

    /// 手动添加(或对已排除应用明确添加)。重复添加更新同一条记录。
    ///
    /// - `.userAdded`:用户本次明确选择的应用;
    /// - `.previouslyAdded`:只用于旧版 custom 名单迁移。
    @discardableResult
    mutating func addManually(
        bundleID: String,
        name: String,
        applicationPath: String?,
        origin: GameHUDManualOrigin = .userAdded
    ) -> GameHUDRegistryChange {
        let existing = records[bundleID]
        var record = existing ?? GameHUDRegisteredApp(bundleID: bundleID, name: name)
        let wasExcluded = existing?.isExcluded ?? false
        record.isExcluded = false
        record.manualOrigin = origin
        if !name.isEmpty {
            record.name = name
        }
        if let applicationPath, !applicationPath.isEmpty {
            record.applicationPath = applicationPath
        }
        records[bundleID] = record
        return GameHUDRegistryChange(
            createdRecord: existing == nil,
            wasExcluded: wasExcluded,
            isEnabled: record.isEnabled
        )
    }

    /// 写入黑名单。保留来源与手动意图;从未见过的应用也能提前排除。
    @discardableResult
    mutating func exclude(bundleID: String, name: String, applicationPath: String?) -> GameHUDRegistryChange {
        let existing = records[bundleID]
        var record = existing ?? GameHUDRegisteredApp(bundleID: bundleID, name: name)
        let wasExcluded = existing?.isExcluded ?? false
        record.isExcluded = true
        if !name.isEmpty {
            record.name = name
        }
        if let applicationPath, !applicationPath.isEmpty {
            record.applicationPath = applicationPath
        }
        records[bundleID] = record
        return GameHUDRegistryChange(
            createdRecord: existing == nil,
            wasExcluded: wasExcluded,
            isEnabled: record.isEnabled
        )
    }

    /// 移出排除。只解除黑名单,不凭空创建手动添加意图。
    /// 返回 nil 表示没有可解除的排除记录。
    @discardableResult
    mutating func removeExclusion(bundleID: String) -> GameHUDRegistryChange? {
        guard var record = records[bundleID], record.isExcluded else { return nil }
        record.isExcluded = false
        records[bundleID] = record
        return GameHUDRegistryChange(
            createdRecord: false,
            wasExcluded: true,
            isEnabled: record.isEnabled
        )
    }

    private static func displayOrder(_ lhs: GameHUDRegisteredApp, _ rhs: GameHUDRegisteredApp) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder == .orderedSame {
            return lhs.bundleID.localizedStandardCompare(rhs.bundleID) == .orderedAscending
        }
        return nameOrder == .orderedAscending
    }
}

/// 登记持久化与旧版兼容。
///
/// 新格式是唯一权威,旧 `customGames` / `excludedGames` 只在没有新数据时作为
/// 迁移输入,并持续作为旧版回退输出写入;不从旧键反向覆盖新决定。
nonisolated enum GameHUDRegistryStore {
    static func load(defaults: UserDefaults) -> GameHUDAppRegistry {
        if let stored = defaults.object(forKey: GameHUDPreferenceKeys.registryData) {
            let rawData: Data?
            if let data = stored as? Data {
                rawData = data
            } else {
                rawData = String(describing: stored).data(using: .utf8)
            }
            if let rawData,
               let registry = try? JSONDecoder().decode(GameHUDAppRegistry.self, from: rawData),
               registry.schema == GameHUDAppRegistry.currentSchema {
                return registry
            }
            backup(rawData, defaults: defaults)
        }

        let migrated = migrateLegacy(defaults: defaults)
        save(migrated, defaults: defaults)
        return migrated
    }

    static func save(_ registry: GameHUDAppRegistry, defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(registry) {
            defaults.set(data, forKey: GameHUDPreferenceKeys.registryData)
        }
        syncLegacyCompatibility(registry, defaults: defaults)
    }

    /// 迁移旧 `customGames` / `excludedGames`:排除优先,旧添加按手动添加呈现。
    static func migrateLegacy(defaults: UserDefaults) -> GameHUDAppRegistry {
        var registry = GameHUDAppRegistry()
        let custom = defaults.stringArray(forKey: GameHUDPreferenceKeys.customGames) ?? []
        let excluded = Set(defaults.stringArray(forKey: GameHUDPreferenceKeys.excludedGames) ?? [])
        for bundleID in Set(custom) {
            guard !bundleID.isEmpty else { continue }
            registry.records[bundleID] = GameHUDRegisteredApp(
                bundleID: bundleID,
                name: bundleID,
                manualOrigin: .previouslyAdded,
                isExcluded: excluded.contains(bundleID)
            )
        }
        for bundleID in excluded where registry.records[bundleID] == nil {
            guard !bundleID.isEmpty else { continue }
            registry.records[bundleID] = GameHUDRegisteredApp(
                bundleID: bundleID,
                name: bundleID,
                isExcluded: true
            )
        }
        return registry
    }

    /// 旧版回退输出:custom 只写手动意图,excluded 写全部黑名单。
    static func syncLegacyCompatibility(_ registry: GameHUDAppRegistry, defaults: UserDefaults) {
        let manual = registry.records.values
            .filter { $0.manualOrigin != nil }
            .map(\.bundleID)
            .sorted()
        let excluded = registry.records.values
            .filter(\.isExcluded)
            .map(\.bundleID)
            .sorted()
        defaults.set(manual, forKey: GameHUDPreferenceKeys.customGames)
        defaults.set(excluded, forKey: GameHUDPreferenceKeys.excludedGames)
    }

    /// 损坏的新格式不覆盖旧决定:把原始载荷留在独立备份键,再从旧键迁移。
    static func backup(_ data: Data?, defaults: UserDefaults) {
        guard let data else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let key = "\(GameHUDPreferenceKeys.registryCorruptBackupPrefix)\(stamp)"
        defaults.set(data, forKey: key)
    }
}

/// 总开关的兼容解析。
///
/// 新用户默认关闭;旧用户显式值优先;可识别旧档案但没有显式值时沿用旧版
/// 有效默认(开启)。解析只执行一次并把结果写成显式值,避免第二次启动后
/// 把“新用户已写下的设置键”误判为旧档案。
nonisolated enum GameHUDSettingsMigration {
    static func resolveMasterEnabled(
        defaults: UserDefaults,
        existingInstallBeforeMigration: Bool
    ) -> Bool {
        if let explicit = defaults.object(forKey: GameHUDPreferenceKeys.masterEnabled) as? Bool {
            defaults.set(true, forKey: GameHUDPreferenceKeys.masterEnabledResolved)
            return explicit
        }
        if defaults.bool(forKey: GameHUDPreferenceKeys.masterEnabledResolved) {
            // 解析过却读不到显式值(被外部清空):按新用户安全默认关闭。
            return false
        }
        let legacyProfile = existingInstallBeforeMigration
            || defaults.bool(forKey: GameHUDPreferenceKeys.masterEnabledDefaultOnMigrated)
            || defaults.object(forKey: GameHUDPreferenceKeys.enabledMetrics) != nil
            || defaults.object(forKey: GameHUDPreferenceKeys.customGames) != nil
            || defaults.object(forKey: GameHUDPreferenceKeys.excludedGames) != nil
        let enabled = legacyProfile
        defaults.set(enabled, forKey: GameHUDPreferenceKeys.masterEnabled)
        defaults.set(true, forKey: GameHUDPreferenceKeys.masterEnabledResolved)
        return enabled
    }
}

/// 应用包可用性:登记身份与包是否仍可找到分开。
///
/// 找不到只影响行内提示,不删除来源、手动意图或黑名单;扫描漏项同样不判失效。
@MainActor
enum GameHUDPackageLocator {
    static func applicationURL(
        for record: GameHUDRegisteredApp,
        lookup: ((String) -> URL?)? = nil,
        fileExists: ((String) -> Bool)? = nil
    ) -> URL? {
        let exists = fileExists ?? { FileManager.default.fileExists(atPath: $0) }
        if let path = record.applicationPath, exists(path) {
            return URL(fileURLWithPath: path)
        }
        let resolve = lookup ?? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let url = resolve(record.bundleID), exists(url.path) {
            return url
        }
        return nil
    }
}
