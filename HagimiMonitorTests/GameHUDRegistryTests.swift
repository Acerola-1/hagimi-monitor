import AppKit
import Foundation
import Testing
@testable import HagimiMonitorDirect

@Suite("Game HUD 统一登记与黑名单")
struct GameHUDRegistryTests {

    // MARK: - 资格与合并

    @Test func autoRecognitionGrantsEligibilityWithoutConfirmation() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(
                bundleID: "com.acerola.fixture.auto",
                name: "Auto Game",
                applicationPath: "/Applications/Auto Game.app",
                source: .steamManifest
            ),
        ])
        #expect(registry.isEligible("com.acerola.fixture.auto"))
        #expect(registry.records["com.acerola.fixture.auto"]?.badge == .automatic)
        #expect(registry.records["com.acerola.fixture.auto"]?.primarySource == .steamManifest)
    }

    @Test func blacklistOverridesEverySourceAndManualIntent() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.mixed", name: "Mixed", applicationPath: nil, source: .steamManifest),
            GameHUDScannedApp(bundleID: "com.acerola.fixture.mixed", name: "Mixed", applicationPath: nil, source: .applicationCategory),
        ])
        registry.addManually(bundleID: "com.acerola.fixture.mixed", name: "Mixed", applicationPath: nil)
        registry.exclude(bundleID: "com.acerola.fixture.mixed", name: "Mixed", applicationPath: nil)

        #expect(!registry.isEligible("com.acerola.fixture.mixed"))
        #expect(registry.records["com.acerola.fixture.mixed"]?.sources.count == 2)
        #expect(registry.records["com.acerola.fixture.mixed"]?.manualOrigin == .userAdded)
        #expect(registry.excludedApps.count == 1)
        #expect(registry.enabledApps.isEmpty)
    }

    @Test func lateScanCannotReviveExcludedApp() {
        var registry = GameHUDAppRegistry()
        let scan = GameHUDScannedApp(
            bundleID: "com.acerola.fixture.late",
            name: "Late",
            applicationPath: "/Applications/Late.app",
            source: .steamManifest
        )
        registry.merge(scannedApps: [scan])
        registry.exclude(bundleID: scan.bundleID, name: scan.name, applicationPath: scan.applicationPath)
        registry.merge(scannedApps: [scan])
        #expect(!registry.isEligible(scan.bundleID))
        #expect(registry.records[scan.bundleID]?.isExcluded == true)
    }

    @Test func scanMissKeepsRecordAndEligibility() {
        var registry = GameHUDAppRegistry()
        let existing = GameHUDScannedApp(
            bundleID: "com.acerola.fixture.kept",
            name: "Kept",
            applicationPath: "/Applications/Kept.app",
            source: .epicManifest
        )
        registry.merge(scannedApps: [existing])
        registry.merge(scannedApps: [])
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.other", name: "Other", applicationPath: nil, source: .applicationCategory),
        ])
        #expect(registry.isEligible(existing.bundleID))
        #expect(registry.records[existing.bundleID]?.sources == [.epicManifest])
    }

    @Test func mergeDeduplicatesByBundleIDAndUnionsSources() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.same", name: "Old Name", applicationPath: "/Applications/Same.app", source: .applicationCategory),
            GameHUDScannedApp(bundleID: "com.acerola.fixture.same", name: "New Name", applicationPath: "/Applications/Same.app", source: .steamManifest),
        ])
        #expect(registry.records.count == 1)
        #expect(registry.records["com.acerola.fixture.same"]?.sources == [.steamManifest, .applicationCategory])
        #expect(registry.records["com.acerola.fixture.same"]?.primarySource == .steamManifest)
    }

    // MARK: - 手动添加与排除

    @Test func manualAddOfUnscannedAppIsEligible() {
        var registry = GameHUDAppRegistry()
        let change = registry.addManually(
            bundleID: "com.acerola.fixture.manual",
            name: "Manual App",
            applicationPath: "/Applications/Manual.app"
        )
        #expect(change.createdRecord)
        #expect(change.isEnabled)
        #expect(registry.isEligible("com.acerola.fixture.manual"))
        #expect(registry.records["com.acerola.fixture.manual"]?.badge == .manual)
    }

    @Test func manualAddClearsExclusionAndKeepsSingleRecord() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.re", name: "Re", applicationPath: nil, source: .steamManifest),
        ])
        registry.exclude(bundleID: "com.acerola.fixture.re", name: "Re", applicationPath: nil)
        let change = registry.addManually(bundleID: "com.acerola.fixture.re", name: "Re", applicationPath: nil)
        #expect(change.wasExcluded)
        #expect(change.isEnabled)
        #expect(registry.records.count == 1)
        #expect(registry.records["com.acerola.fixture.re"]?.isExcluded == false)
        #expect(registry.records["com.acerola.fixture.re"]?.sources == [.steamManifest])
    }

    @Test func removeExclusionRestoresAutoSource() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.restore", name: "Restore", applicationPath: nil, source: .applicationCategory),
        ])
        registry.exclude(bundleID: "com.acerola.fixture.restore", name: "Restore", applicationPath: nil)
        let change = registry.removeExclusion(bundleID: "com.acerola.fixture.restore")
        #expect(change?.isEnabled == true)
        #expect(registry.isEligible("com.acerola.fixture.restore"))
    }

    @Test func preExcludedUnknownAppHasNoAutomaticBadge() {
        var registry = GameHUDAppRegistry()
        registry.exclude(bundleID: "com.acerola.fixture.pre-badge", name: "Pre Badge", applicationPath: nil)
        let record = registry.records["com.acerola.fixture.pre-badge"]
        #expect(record?.badge == nil)
        #expect(record?.sources.isEmpty == true)
        #expect(record?.manualOrigin == nil)
        #expect(record?.isExcluded == true)
    }

    @Test func packageAvailabilityDoesNotDeleteDecisionWhenBundleMissing() {
        var registry = GameHUDAppRegistry()
        registry.merge(scannedApps: [
            GameHUDScannedApp(
                bundleID: "com.acerola.fixture.missing",
                name: "Missing",
                applicationPath: "/missing/Missing.app",
                source: .steamManifest
            ),
        ])
        let record = registry.records["com.acerola.fixture.missing"]!
        #expect(GameHUDPackageLocator.applicationURL(
            for: record,
            lookup: { _ in nil },
            fileExists: { _ in false }
        ) == nil)
        // 包找不到不影响倾向与资格;行内只显示未找到提示。
        #expect(record.isEnabled)
        #expect(registry.isEligible(record.bundleID))
        #expect(GameHUDPackageLocator.applicationURL(
            for: record,
            lookup: { _ in URL(fileURLWithPath: "/found/Missing.app") },
            fileExists: { $0 == "/found/Missing.app" }
        ) != nil)
    }

    @Test func removeExclusionWithoutSourceDoesNotInventManualIntent() {
        var registry = GameHUDAppRegistry()
        registry.exclude(bundleID: "com.acerola.fixture.pre", name: "Pre Excluded", applicationPath: nil)
        let change = registry.removeExclusion(bundleID: "com.acerola.fixture.pre")
        #expect(change?.isEnabled == false)
        #expect(!registry.isEligible("com.acerola.fixture.pre"))
        #expect(registry.records["com.acerola.fixture.pre"]?.manualOrigin == nil)
        #expect(registry.enabledApps.isEmpty)
        #expect(registry.excludedApps.isEmpty)
    }

    @Test func preExclusionSurvivesFirstRecognition() {
        var registry = GameHUDAppRegistry()
        registry.exclude(bundleID: "com.acerola.fixture.early", name: "Early", applicationPath: nil)
        registry.merge(scannedApps: [
            GameHUDScannedApp(bundleID: "com.acerola.fixture.early", name: "Early", applicationPath: "/Applications/Early.app", source: .steamManifest),
        ])
        #expect(!registry.isEligible("com.acerola.fixture.pre"))
        #expect(!registry.isEligible("com.acerola.fixture.early"))
        #expect(registry.records["com.acerola.fixture.early"]?.isExcluded == true)
    }

    // MARK: - 迁移与持久化

    @Test func legacyMigrationMapsCustomAndExcludedWithExclusionPriority() {
        let suite = "test.hagimi.gamehud.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.acerola.legacy.custom"], forKey: "settings.gameHUD.customGames")
        defaults.set(["com.acerola.legacy.custom", "com.acerola.legacy.blocked"], forKey: "settings.gameHUD.excludedGames")

        let settings = MonitorSettings(defaults: defaults)
        let custom = settings.gameHUDRegistry.records["com.acerola.legacy.custom"]
        #expect(custom?.manualOrigin == .previouslyAdded)
        #expect(custom?.badge == .manual)
        #expect(custom?.isExcluded == true)
        #expect(settings.gameHUDRegistry.records["com.acerola.legacy.blocked"]?.isExcluded == true)
        #expect(!settings.gameHUDRegistry.isEligible("com.acerola.legacy.custom"))
        #expect(settings.gameHUDRegistry.enabledApps.isEmpty)
        #expect(settings.gameHUDRegistry.excludedApps.map(\.bundleID) == [
            "com.acerola.legacy.blocked", "com.acerola.legacy.custom",
        ])
    }

    @Test func registryMigrationIsIdempotentAcrossRestarts() {
        let suite = "test.hagimi.gamehud.idempotent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.acerola.legacy.custom"], forKey: "settings.gameHUD.customGames")
        defaults.set(["com.acerola.legacy.custom"], forKey: "settings.gameHUD.excludedGames")

        let first = MonitorSettings(defaults: defaults)
        first.removeGameHUDExcludedGame("com.acerola.legacy.custom")
        #expect(first.gameHUDRegistry.isEligible("com.acerola.legacy.custom"))

        let second = MonitorSettings(defaults: defaults)
        #expect(second.gameHUDRegistry.isEligible("com.acerola.legacy.custom"))
        #expect(second.gameHUDRegistry.records["com.acerola.legacy.custom"]?.isExcluded == false)
    }

    @Test func corruptRegistryDataKeepsLegacyRecordsAndBackup() {
        let suite = "test.hagimi.gamehud.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "settings.gameHUD.registry")
        defaults.set(["com.acerola.legacy.custom"], forKey: "settings.gameHUD.customGames")
        defaults.set(["com.acerola.legacy.blocked"], forKey: "settings.gameHUD.excludedGames")

        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.gameHUDRegistry.records["com.acerola.legacy.custom"]?.manualOrigin == .previouslyAdded)
        #expect(settings.gameHUDRegistry.records["com.acerola.legacy.blocked"]?.isExcluded == true)
        let backupKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("settings.gameHUD.registry.corruptBackup.") }
        #expect(backupKeys.count == 1)
    }

    @Test func addExcludeRemoveThroughSettingsUsesSingleRegistry() {
        let suite = "test.hagimi.gamehud.actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)

        let added = settings.addGameHUDManualApp(
            bundleID: "com.acerola.fixture.actions",
            name: "Actions",
            applicationPath: "/Applications/Actions.app"
        )
        #expect(added.createdRecord)
        #expect(settings.gameHUDRegistry.isEligible("com.acerola.fixture.actions"))

        let excluded = settings.excludeGameHUDGame(
            bundleID: "com.acerola.fixture.actions",
            name: "Actions",
            applicationPath: "/Applications/Actions.app"
        )
        #expect(!excluded.wasExcluded)
        #expect(!settings.gameHUDRegistry.isEligible("com.acerola.fixture.actions"))
        #expect(settings.gameHUDRegistry.records["com.acerola.fixture.actions"]?.manualOrigin == .userAdded)

        let restored = settings.removeGameHUDExcludedGame("com.acerola.fixture.actions")
        #expect(restored?.isEnabled == true)
        #expect(settings.gameHUDRegistry.isEligible("com.acerola.fixture.actions"))
        #expect(settings.gameHUDRegistry.records.count == 1)
    }

    // MARK: - 总开关兼容

    @Test func freshInstallDefaultsMasterOff() {
        let suite = "test.hagimi.gamehud.fresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.gameHUDMasterEnabled == false)
        #expect(defaults.object(forKey: "settings.gameHUD.masterEnabled") as? Bool == false)
    }

    @Test func secondLaunchOfFreshProfileStaysOff() {
        let suite = "test.hagimi.gamehud.fresh2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = MonitorSettings(defaults: defaults)
        let second = MonitorSettings(defaults: defaults)
        #expect(second.gameHUDMasterEnabled == false)
    }

    @Test func explicitLegacyMasterPreferenceIsPreserved() {
        let suiteFalse = "test.hagimi.gamehud.explicitfalse.\(UUID().uuidString)"
        let defaultsFalse = UserDefaults(suiteName: suiteFalse)!
        defer { defaultsFalse.removePersistentDomain(forName: suiteFalse) }
        defaultsFalse.set("dark", forKey: "settings.themePreference")
        defaultsFalse.set(false, forKey: "settings.gameHUD.masterEnabled")
        #expect(MonitorSettings(defaults: defaultsFalse).gameHUDMasterEnabled == false)

        let suiteTrue = "test.hagimi.gamehud.explicittrue.\(UUID().uuidString)"
        let defaultsTrue = UserDefaults(suiteName: suiteTrue)!
        defer { defaultsTrue.removePersistentDomain(forName: suiteTrue) }
        defaultsTrue.set("dark", forKey: "settings.themePreference")
        defaultsTrue.set(true, forKey: "settings.gameHUD.masterEnabled")
        #expect(MonitorSettings(defaults: defaultsTrue).gameHUDMasterEnabled == true)
    }

    @Test func legacyProfileWithoutExplicitMasterKeepsOldDefaultOn() {
        let suite = "test.hagimi.gamehud.legacydefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "settings.themePreference")
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.gameHUDMasterEnabled == true)
    }

    // MARK: - 背景透明度

    @Test func transparencyDefaultsMatchExistingBackgrounds() {
        let card = GameHUDBackgroundAppearance.defaultTransparency(for: .card)
        let strip = GameHUDBackgroundAppearance.defaultTransparency(for: .topStrip)
        #expect(abs(card - 0.32) < 0.000001)
        #expect(abs(strip - 0.28) < 0.000001)
        #expect(abs(GameHUDBackgroundAppearance.backgroundAlpha(for: .card, transparency: card) - 0.68) < 0.000001)
        #expect(abs(GameHUDBackgroundAppearance.backgroundAlpha(for: .topStrip, transparency: strip) - 0.72) < 0.000001)
        #expect(GameHUDBackgroundAppearance.backgroundAlpha(for: .card, transparency: 0) == 1)
        #expect(GameHUDBackgroundAppearance.backgroundAlpha(for: .card, transparency: 1) == 0)
    }

    @Test func transparencyNormalizesInvalidValues() {
        #expect(GameHUDBackgroundAppearance.normalized(2, for: .card) == 1)
        #expect(GameHUDBackgroundAppearance.normalized(-1, for: .card) == 0)
        #expect(abs(GameHUDBackgroundAppearance.normalized(.nan, for: .card) - 0.32) < 0.000001)
        #expect(abs(GameHUDBackgroundAppearance.normalized(.infinity, for: .topStrip) - 0.28) < 0.000001)
    }

    @Test func transparencyPersistsPerStyleAndResetsOnlyCurrentStyle() {
        let suite = "test.hagimi.gamehud.transparency.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings(defaults: defaults)
        settings.setGameHUDBackgroundTransparency(0.5, for: .card)
        settings.setGameHUDBackgroundTransparency(0.25, for: .topStrip)

        let restored = MonitorSettings(defaults: defaults)
        #expect(abs(restored.gameHUDBackgroundTransparency(for: .card) - 0.5) < 0.000001)
        #expect(abs(restored.gameHUDBackgroundTransparency(for: .topStrip) - 0.25) < 0.000001)

        restored.resetGameHUDBackgroundTransparency(for: .card)
        #expect(abs(restored.gameHUDBackgroundTransparency(for: .card) - 0.32) < 0.000001)
        #expect(abs(restored.gameHUDBackgroundTransparency(for: .topStrip) - 0.25) < 0.000001)
    }

    @Test func invalidStoredTransparencyFallsBackSafely() {
        let suite = "test.hagimi.gamehud.transparency.invalid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(3.0, forKey: "settings.gameHUD.backgroundTransparency.card")
        defaults.set("oops", forKey: "settings.gameHUD.backgroundTransparency.topStrip")
        let settings = MonitorSettings(defaults: defaults)
        #expect(settings.gameHUDBackgroundTransparency(for: .card) == 1)
        #expect(abs(settings.gameHUDBackgroundTransparency(for: .topStrip) - 0.28) < 0.000001)
    }

    // MARK: - 预览隔离

    @Test func previewUsesFixedReadableSampleAndHeightCap() {
        #expect(GameHUDPreviewSample.enabledIDs == Set([GameHUDMetricID.fps, .cpuUsage]))
        #expect(GameHUDPreviewSample.snapshot.readings.count == 1)
        #expect(GameHUDPreviewContract.containerHeight(for: .card) <= GameHUDPreviewContract.maxHeight)
        #expect(GameHUDPreviewContract.containerHeight(for: .topStrip) <= GameHUDPreviewContract.maxHeight)
        #expect(GameHUDPreviewContract.containerHeight(for: .card) < GameHUDPreviewContract.maxHeight + 1)
    }
}

@Suite("Game HUD 类别与安装清单关联")
struct GameHUDAutoDetectionTests {

    @Test func gameCategoryRecognizesEnglishChineseAndJapanese() {
        #expect(GameHUDAutoDetection.isGameCategory("public.app-category.games"))
        #expect(GameHUDAutoDetection.isGameCategory("public.app-category.action-games"))
        #expect(GameHUDAutoDetection.isGameCategory("Games"))
        #expect(GameHUDAutoDetection.isGameCategory("Action Games"))
        #expect(GameHUDAutoDetection.isGameCategory("游戏"))
        #expect(GameHUDAutoDetection.isGameCategory("动作游戏"))
        #expect(GameHUDAutoDetection.isGameCategory("遊戲"))
        #expect(GameHUDAutoDetection.isGameCategory("ゲーム"))
        #expect(GameHUDAutoDetection.isGameCategory("アクションゲーム"))
        #expect(GameHUDAutoDetection.isGameCategory("게임"))
        #expect(!GameHUDAutoDetection.isGameCategory("public.app-category.productivity"))
        #expect(!GameHUDAutoDetection.isGameCategory("Productivity"))
        #expect(!GameHUDAutoDetection.isGameCategory(nil))
        #expect(!GameHUDAutoDetection.isGameCategory(""))
    }

    @Test func packageCategoryIsLanguageIndependent() throws {
        let english = try makeFixtureApp(category: "public.app-category.strategy-games")
        let chinese = try makeFixtureApp(category: "动作游戏")
        let japanese = try makeFixtureApp(category: "アクションゲーム")
        let productivity = try makeFixtureApp(category: "public.app-category.productivity")
        defer {
            for url in [english, chinese, japanese, productivity] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        #expect(GameHUDAutoDetection.isGameApplication(at: english))
        #expect(GameHUDAutoDetection.isGameApplication(at: chinese))
        #expect(GameHUDAutoDetection.isGameApplication(at: japanese))
        #expect(!GameHUDAutoDetection.isGameApplication(at: productivity))
        #expect(GameHUDGameScanner.categoryGame(at: english)?.source == .applicationCategory)
        #expect(GameHUDGameScanner.categoryGame(at: productivity) == nil)
    }

    @Test func pathAndBundleNameAloneAreNotGameEvidence() throws {
        let productivity = try makeFixtureApp(
            category: "public.app-category.productivity",
            bundleID: "com.example.looks-like-steam-game",
            name: "Steam Game Launcher"
        )
        defer { try? FileManager.default.removeItem(at: productivity) }
        // 路径/名称相似或使用图形 API 不能成为自动识别依据:只有包内类别证据才算。
        #expect(!GameHUDAutoDetection.isGameApplication(at: productivity))
        #expect(GameHUDGameScanner.categoryGame(at: productivity) == nil)
        #expect(GameHUDAutoDetection.storePathSource(
            for: URL(fileURLWithPath: "/Applications/Some Game.app")
        ) == nil)
    }

    @Test func launcherCategoriesAreExcludedFromAutomaticAdoption() throws {
        let launcher = try makeFixtureApp(
            category: "public.app-category.games",
            bundleID: "com.valvesoftware.steam",
            name: "Steam"
        )
        defer { try? FileManager.default.removeItem(at: launcher) }
        #expect(GameHUDGameScanner.categoryGame(at: launcher) == nil)
    }

    @Test func associationSelectsOnlyUnambiguousApplication() {
        let hades = GameHUDAppCandidate(
            url: URL(fileURLWithPath: "/tmp/Hades.app"),
            name: "Hades",
            bundleID: "com.supergiantgames.hades"
        )
        let tool = GameHUDAppCandidate(
            url: URL(fileURLWithPath: "/tmp/Tool.app"),
            name: "Crash Reporter",
            bundleID: "com.example.tool"
        )
        #expect(GameHUDAppAssociation.select(gameName: "Hades", candidates: [hades]) == hades)
        #expect(GameHUDAppAssociation.select(gameName: "Hades", candidates: [hades, tool]) == hades)
        #expect(GameHUDAppAssociation.select(gameName: "Unknown", candidates: [hades, tool]) == nil)
        #expect(GameHUDAppAssociation.select(gameName: "", candidates: [hades, tool]) == nil)
        #expect(GameHUDAppAssociation.select(gameName: "Hades", candidates: []) == nil)
        #expect(GameHUDAppAssociation.select(gameName: "Hades", candidates: [hades, hades]) == nil)
    }

    @Test func epicLaunchExecutableResolvesNestedApplicationBundle() {
        let candidate = GameHUDAppAssociation.epicApplicationCandidate(
            launchExecutable: "Celeste.app/Contents/MacOS/Celeste",
            installLocation: "/tmp/Celeste",
            gameName: "Celeste"
        )
        // 不存在的安装目录上没有真实 .app,不能凭空生成 bundle ID。
        #expect(candidate == nil)
        #expect(GameHUDAppAssociation.applicationBundleURL(inPath: "/tmp/Celeste.app/Contents/MacOS/Celeste")?.path == "/tmp/Celeste.app")
    }

    @Test func newGameHUDStringsMatchProjectLanguages() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let xcstringsURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HagimiMonitor/Localizable.xcstrings")
        let data = try Data(contentsOf: xcstringsURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let keys = [
            "gamehud.appearance.title",
            "gamehud.appearance.transparency",
            "gamehud.appearance.transparency.hint",
            "gamehud.appearance.transparency.reset",
            "gamehud.appearance.preview",
            "gamehud.appearance.preview.background %@",
            "gamehud.games.title",
            "gamehud.games.rescan",
            "gamehud.games.add-app",
            "gamehud.games.badge.auto",
            "gamehud.games.badge.manual",
            "gamehud.games.source.manual",
            "gamehud.games.source.unrecognized",
            "gamehud.games.package-missing",
            "gamehud.games.feedback.added %@",
            "gamehud.games.feedback.excluded %@",
            "gamehud.games.feedback.excluded-early %@",
            "gamehud.games.feedback.removed-exclusion %@",
            "gamehud.games.feedback.removed-exclusion-no-source %@",
            "gamehud.games.feedback.scan-finished %lld",
            "gamehud.excluded.title",
            "gamehud.excluded.add",
            "gamehud.excluded.remove",
            "gamehud.excluded.empty",
            "gamehud.source.steam",
            "gamehud.source.epic",
            "gamehud.source.category",
        ]
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "missing key \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "missing localizations \(key)")
            // 项目资源实际只有 zh-Hans/en;不能只给新增文案加半套日文。
            #expect(localizations["ja"] == nil, "unexpected ja for \(key)")
            for language in ["en", "zh-Hans"] {
                let unit = try #require((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "missing \(language) \(key)")
                let value = try #require(unit["value"] as? String, "missing value \(language) \(key)")
                #expect(!value.isEmpty)
            }
        }
    }

    private func makeFixtureApp(
        category: String?,
        bundleID: String = "com.acerola.fixture.\(UUID().uuidString)",
        name: String = "Fixture"
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameHUD-\(UUID().uuidString).app", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": "Fixture",
        ]
        if let category {
            plist["LSApplicationCategoryType"] = category
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }
}
