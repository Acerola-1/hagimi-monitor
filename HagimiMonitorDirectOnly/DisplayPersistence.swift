import Foundation

/// v2 持久化命名空间与迁移(8.4/8.5)。
///
/// 设计:
/// - 独立 v2 命名空间 `displayControl2.<stableKey>.<field>`,与 v1 key 分开;
/// - 迁移仅在 v1 身份唯一匹配时复制历史值,标为 historical/unverified;零序列号碰撞
///   不复制到两屏;不据 v1 key 推断软件模式;v1 仅迁移读取,不双写;
/// - 保存 backendPreference、readPolicy、timingProfile、rangeOverride、软件成功因子
///   及音量恢复值;请求队列/临时故障/generation 不持久化。
nonisolated final class DisplayPersistence {
    static let shared = DisplayPersistence()
    private let defaults: UserDefaults

    /// v2 命名空间前缀。
    static let v2Prefix = "displayControl2"
    /// v1 前缀(仅迁移读取)。
    static let v1Prefix = "displayControl"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - v2 读写

    private func v2Key(_ stableKey: String, _ field: String) -> String {
        "\(Self.v2Prefix).\(stableKey).\(field)"
    }

    func saveSoftwareFactor(_ factor: Double, stableKey: String) {
        defaults.set(min(100, max(0, factor)), forKey: v2Key(stableKey, "softwareFactor"))
    }

    func softwareFactor(stableKey: String) -> Double? {
        guard defaults.object(forKey: v2Key(stableKey, "softwareFactor")) != nil else { return nil }
        return defaults.double(forKey: v2Key(stableKey, "softwareFactor"))
    }

    func saveHardwareValue(_ value: Double, attribute: String, stableKey: String) {
        defaults.set(min(100, max(0, value)), forKey: v2Key(stableKey, "hardware.\(attribute)"))
    }

    func hardwareValue(attribute: String, stableKey: String) -> Double? {
        guard defaults.object(forKey: v2Key(stableKey, "hardware.\(attribute)")) != nil else { return nil }
        return defaults.double(forKey: v2Key(stableKey, "hardware.\(attribute)"))
    }

    func saveVolumeRestoreValue(_ value: Double, stableKey: String) {
        guard value > 0 else { return }
        defaults.set(min(100, max(0, value)), forKey: v2Key(stableKey, "volumeRestore"))
    }

    func volumeRestoreValue(stableKey: String) -> Double? {
        guard defaults.object(forKey: v2Key(stableKey, "volumeRestore")) != nil else { return nil }
        let value = defaults.double(forKey: v2Key(stableKey, "volumeRestore"))
        return value > 0 ? value : nil
    }

    func saveCompatibilityConfig(_ config: DisplayCompatibilityConfig, stableKey: String) {
        defaults.set(config.brightnessMode.rawValue, forKey: v2Key(stableKey, "brightnessMode"))
        defaults.set(config.readPolicy.rawValue, forKey: v2Key(stableKey, "readPolicy"))
        defaults.set(config.timingProfile.rawValue, forKey: v2Key(stableKey, "timingProfile"))
        if let range = config.rangeOverride {
            defaults.set(range, forKey: v2Key(stableKey, "rangeOverride"))
        } else {
            defaults.removeObject(forKey: v2Key(stableKey, "rangeOverride"))
        }
        if let override = config.vcpOverride {
            defaults.set(override.map(Int.init), forKey: v2Key(stableKey, "vcpOverride"))
        } else {
            defaults.removeObject(forKey: v2Key(stableKey, "vcpOverride"))
        }
    }

    func compatibilityConfig(stableKey: String) -> DisplayCompatibilityConfig? {
        guard defaults.object(forKey: v2Key(stableKey, "brightnessMode")) != nil else { return nil }
        var config = DisplayCompatibilityConfig()
        config.brightnessMode = DisplayCompatibilityConfig.BrightnessMode(
            rawValue: defaults.string(forKey: v2Key(stableKey, "brightnessMode")) ?? ""
        ) ?? .auto
        config.readPolicy = DisplayCompatibilityConfig.ReadPolicy(
            rawValue: defaults.string(forKey: v2Key(stableKey, "readPolicy")) ?? ""
        ) ?? .auto
        config.timingProfile = DisplayCompatibilityConfig.TimingProfile(
            rawValue: defaults.string(forKey: v2Key(stableKey, "timingProfile")) ?? ""
        ) ?? .normal
        if defaults.object(forKey: v2Key(stableKey, "rangeOverride")) != nil {
            let number = defaults.object(forKey: v2Key(stableKey, "rangeOverride")) as? NSNumber
            if let number, number.intValue > 0, number.intValue <= Int(UInt16.max) {
                config.rangeOverride = UInt16(number.intValue)
            }
        }
        if let numbers = defaults.array(forKey: v2Key(stableKey, "vcpOverride")) as? [NSNumber] {
            let values = numbers.map(\.intValue).filter { (1...255).contains($0) }
            config.vcpOverride = values.map(UInt8.init)
        }
        return config
    }

    // MARK: - v1 迁移

    /// v1 key:displayControl.value.<v1StorageID>.<attribute>。
    private func v1Key(_ v1StorageID: String, _ attribute: String) -> String {
        "\(Self.v1Prefix).value.\(v1StorageID).\(attribute)"
    }

    /// 迁移单台显示器的历史值(仅当身份唯一匹配时调用)。
    /// - Returns: 迁移得到的历史值字典(attribute → 值),均标为未确认。
    func migrateHistoricalValues(
        v1StorageID: String,
        stableKey: String,
        attributes: [String]
    ) -> [String: Double] {
        var migrated: [String: Double] = [:]
        for attribute in attributes {
            let key = v1Key(v1StorageID, attribute)
            guard defaults.object(forKey: key) != nil else { continue }
            let value = defaults.double(forKey: key)
            // 迁移值标记 historical/unverified:不当作确认状态,不推断软件模式。
            migrated[attribute] = value
            defaults.set(value, forKey: v2Key(stableKey, "historical.\(attribute)"))
        }
        return migrated
    }

    /// 读取迁移的历史值(未确认)。
    func historicalValue(attribute: String, stableKey: String) -> Double? {
        guard defaults.object(forKey: v2Key(stableKey, "historical.\(attribute)")) != nil else { return nil }
        return defaults.double(forKey: v2Key(stableKey, "historical.\(attribute)"))
    }

    /// 是否已存在 v2 数据(重启恢复判断用)。
    func hasV2Data(stableKey: String) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("\(Self.v2Prefix).\(stableKey).") }
    }

    /// 清除某显示器的 v2 数据(用户重置/卸载)。
    func removeV2Data(stableKey: String) {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("\(Self.v2Prefix).\(stableKey).") }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
