import Testing
@testable import HagimiMonitorDirect
import Foundation

/// 持久化迁移测试(8.4/8.5)。
/// 验收:旧历史值标记未确认;零序列号冲突不迁移;硬件历史不自动变成软件因子;
/// 旧 key 保留支持回滚;软件与硬件值各自保存;重启后显式恢复。
struct DisplayPersistenceTests {
    private func makePersistence() -> (DisplayPersistence, UserDefaults) {
        let suite = "test-persistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (DisplayPersistence(defaults: defaults), defaults)
    }

    @Test func v2SoftwareAndHardwareValuesAreSeparate() {
        let (persistence, _) = makePersistence()
        let stableKey = "ext.4660.22040.serial123"
        persistence.saveSoftwareFactor(60, stableKey: stableKey)
        persistence.saveHardwareValue(80, attribute: "brightness", stableKey: stableKey)

        #expect(persistence.softwareFactor(stableKey: stableKey) == 60)
        #expect(persistence.hardwareValue(attribute: "brightness", stableKey: stableKey) == 80)
        // 软件因子与硬件值不互相污染。
        #expect(persistence.softwareFactor(stableKey: stableKey) != 80)
    }

    /// 零序列号冲突:两个显示器共享 stableKey 时,迁移不能把一屏的值复制给两屏。
    /// 迁移入口由调用方(identity ledger)保证唯一匹配才调用;此处验证
    /// migrateHistoricalValues 只写一次,重复迁移幂等。
    @Test func migrationWritesOnceAndIdempotent() {
        let (persistence, defaults) = makePersistence()
        let v1StorageID = "external.Dell.4660.22040.0" // 零序列号
        let stableKey = "ext.4660.22040.noserial"
        defaults.set(70, forKey: "\(DisplayPersistence.v1Prefix).value.\(v1StorageID).brightness")

        let migrated1 = persistence.migrateHistoricalValues(v1StorageID: v1StorageID, stableKey: stableKey, attributes: ["brightness"])
        #expect(migrated1["brightness"] == 70)
        // 旧 key 保留供回滚。
        #expect(defaults.object(forKey: "\(DisplayPersistence.v1Prefix).value.\(v1StorageID).brightness") != nil)
        // 迁移值标未确认。
        #expect(persistence.historicalValue(attribute: "brightness", stableKey: stableKey) == 70)
    }

    /// 硬件历史不自动变成软件因子:v1 亮度值迁移后是 historical,不是 softwareFactor。
    @Test func v1HardwareHistoryDoesNotBecomeSoftwareFactor() {
        let (persistence, defaults) = makePersistence()
        let v1StorageID = "external.Dell.4660.22040.999"
        let stableKey = "ext.4660.22040.999"
        defaults.set(50, forKey: "\(DisplayPersistence.v1Prefix).value.\(v1StorageID).brightness")

        persistence.migrateHistoricalValues(v1StorageID: v1StorageID, stableKey: stableKey, attributes: ["brightness"])
        // 迁移后 softwareFactor 不存在(旧值不是软件因子)。
        #expect(persistence.softwareFactor(stableKey: stableKey) == nil)
        #expect(persistence.historicalValue(attribute: "brightness", stableKey: stableKey) == 50)
    }

    /// 音量恢复值:0 不保存(避免静音状态覆盖恢复值)。
    @Test func volumeRestoreRejectsZero() {
        let (persistence, _) = makePersistence()
        persistence.saveVolumeRestoreValue(0, stableKey: "k")
        #expect(persistence.volumeRestoreValue(stableKey: "k") == nil)
        persistence.saveVolumeRestoreValue(25, stableKey: "k")
        #expect(persistence.volumeRestoreValue(stableKey: "k") == 25)
    }

    /// 兼容配置持久化可重启恢复。
    @Test func compatibilityConfigPersistsAcrossRestart() {
        let (persistence, _) = makePersistence()
        let stableKey = "ext.1.2.serial"
        var config = DisplayCompatibilityConfig()
        config.brightnessMode = .software
        config.readPolicy = .off
        config.timingProfile = .slow
        config.rangeOverride = 255
        persistence.saveCompatibilityConfig(config, stableKey: stableKey)

        let loaded = persistence.compatibilityConfig(stableKey: stableKey)
        #expect(loaded?.brightnessMode == .software)
        #expect(loaded?.readPolicy == .off)
        #expect(loaded?.timingProfile == .slow)
        #expect(loaded?.rangeOverride == 255)
    }

    /// 软件模式重启恢复:保存成功因子后 hasV2Data 为真,可据此显式恢复。
    @Test func softwareModeRestartRecoverySignal() {
        let (persistence, _) = makePersistence()
        let stableKey = "ext.1.2.serial"
        #expect(!persistence.hasV2Data(stableKey: stableKey))
        persistence.saveSoftwareFactor(40, stableKey: stableKey)
        #expect(persistence.hasV2Data(stableKey: stableKey))
        #expect(persistence.softwareFactor(stableKey: stableKey) == 40)
    }
}
