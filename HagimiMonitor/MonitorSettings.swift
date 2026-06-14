import Combine
import Foundation
import ServiceManagement
import SwiftUI

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            String(localized: "theme.system")
        case .light:
            String(localized: "theme.light")
        case .dark:
            String(localized: "theme.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum MonitorColorSchemePreference: String, CaseIterable, Identifiable {
    case balanced
    case vibrant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            String(localized: "color-scheme.balanced")
        case .vibrant:
            String(localized: "color-scheme.vibrant")
        }
    }
}

final class MonitorSettings: ObservableObject {
    @Published var launchAtLogin: Bool = false
    @Published var themePreference: AppThemePreference = .system
    @Published var colorSchemePreference: MonitorColorSchemePreference = .balanced
    @Published var ringSource: HaloRingSource = .combined
    @Published var showBuiltInDisplays: Bool = true
    @Published var displayModuleVisible: Bool = false
    @Published var displayBrightnessControlEnabled: Bool = true
    @Published var displayVolumeControlEnabled: Bool = true
    @Published var displayContrastControlEnabled: Bool = false
    @Published var mediaKeyBrightnessEnabled: Bool = false
    @Published var mediaKeyVolumeEnabled: Bool = false
    @Published var mediaKeyShowOSD: Bool = true
    @Published var mediaKeyFineScaleBrightness: Bool = false
    @Published var mediaKeyFineScaleVolume: Bool = false
    @Published private(set) var visibleKinds: Set<MonitorKind> = []
    @Published private(set) var enabledMetrics: [MonitorKind: Set<String>] = [:]

    private let defaults: UserDefaults
    private var isUpdatingLaunchAtLogin = false
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let themeRawValue = defaults.string(forKey: Keys.themePreference) ?? AppThemePreference.system.rawValue
        themePreference = AppThemePreference(rawValue: themeRawValue) ?? .system

        let colorSchemeRawValue = defaults.string(forKey: Keys.colorSchemePreference) ?? MonitorColorSchemePreference.balanced.rawValue
        colorSchemePreference = MonitorColorSchemePreference(rawValue: colorSchemeRawValue) ?? .balanced

        let ringSourceRawValue = defaults.string(forKey: Keys.ringSource) ?? HaloRingSource.combined.rawValue
        ringSource = HaloRingSource(rawValue: ringSourceRawValue) ?? .combined

        showBuiltInDisplays = defaults.object(forKey: Keys.showBuiltInDisplays) as? Bool ?? true
        displayModuleVisible = defaults.object(forKey: Keys.displayModuleVisible) as? Bool ?? false
        displayBrightnessControlEnabled = defaults.object(forKey: Keys.displayBrightnessControlEnabled) as? Bool ?? true
        displayVolumeControlEnabled = defaults.object(forKey: Keys.displayVolumeControlEnabled) as? Bool ?? true
        displayContrastControlEnabled = defaults.object(forKey: Keys.displayContrastControlEnabled) as? Bool ?? false

        mediaKeyBrightnessEnabled = defaults.object(forKey: Keys.mediaKeyBrightnessEnabled) as? Bool ?? false
        mediaKeyVolumeEnabled = defaults.object(forKey: Keys.mediaKeyVolumeEnabled) as? Bool ?? false
        mediaKeyShowOSD = defaults.object(forKey: Keys.mediaKeyShowOSD) as? Bool ?? true
        mediaKeyFineScaleBrightness = defaults.object(forKey: Keys.mediaKeyFineScaleBrightness) as? Bool ?? false
        mediaKeyFineScaleVolume = defaults.object(forKey: Keys.mediaKeyFineScaleVolume) as? Bool ?? false

        if let storedKinds = defaults.array(forKey: Keys.visibleKinds) as? [String] {
            let kinds = storedKinds.compactMap(MonitorKind.init(rawValue:))
            visibleKinds = Set(kinds)
        } else {
            visibleKinds = Set(MonitorKind.allCases)
        }

        var loadedMetrics: [MonitorKind: Set<String>] = [:]
        for kind in MonitorKind.allCases {
            let key = Keys.enabledMetricsPrefix + kind.rawValue
            if let stored = defaults.array(forKey: key) as? [String] {
                let migrated = migrateMetrics(stored, for: kind)
                loadedMetrics[kind] = Set(migrated)
            }
        }
        enabledMetrics = loadedMetrics

        launchAtLogin = SMAppService.mainApp.status == .enabled

        setupBindings()
    }

    func isVisible(_ kind: MonitorKind) -> Bool {
        visibleKinds.contains(kind)
    }

    func setVisible(_ isVisible: Bool, for kind: MonitorKind) {
        if isVisible {
            visibleKinds.insert(kind)
        } else {
            visibleKinds.remove(kind)
        }
    }

    func isMetricEnabled(_ id: String, for kind: MonitorKind) -> Bool {
        if let stored = enabledMetrics[kind] {
            return stored.contains(id)
        }
        return kind.availableMetrics.first(where: { $0.id == id })?.isDefault ?? false
    }

    func canEnableMetric(_ id: String, for kind: MonitorKind) -> Bool {
        return true
    }

    func setMetric(_ id: String, enabled: Bool, for kind: MonitorKind) {
        var current = enabledMetrics[kind] ?? defaultMetricIds(for: kind)
        if enabled {
            current.insert(id)
        } else {
            current.remove(id)
        }
        enabledMetrics[kind] = current
    }

    func resetMetrics(for kind: MonitorKind) {
        enabledMetrics[kind] = defaultMetricIds(for: kind)
    }

    private func migrateMetrics(_ ids: [String], for kind: MonitorKind) -> [String] {
        let mapping: [String: String] = {
            switch kind {
            case .cpu:
                return ["系统": "system", "用户": "user", "闲置": "idle", "启动时间": "uptime", "温度": "temperature"]
            case .gpu:
                return ["GPU内存": "gpu-memory", "已分配": "allocated", "渲染": "render", "分块": "tiler", "温度": "temperature"]
            case .memory:
                return ["已用": "used", "压力": "pressure", "交换已用": "swap-used", "总量": "total"]
            case .storage:
                return ["已用": "used", "可用": "free", "总量": "total"]
            case .network:
                return ["IP 地址": "ip-address", "上传": "upload", "下载": "download"]
            case .battery:
                return ["充电功率": "charging-power", "健康度": "health", "循环数": "cycle-count", "温度": "temperature", "适配器": "adapter", "功耗": "power"]
            }
        }()

        var result = Set<String>()
        for id in ids {
            if let mapped = mapping[id] {
                result.insert(mapped)
            } else {
                result.insert(id)
            }
        }

        let availableIds = Set(kind.availableMetrics.map { $0.id })
        let filtered = result.intersection(availableIds)

        if filtered.isEmpty {
            return Array(defaultMetricIds(for: kind))
        }

        return Array(filtered)
    }

    private func defaultMetricIds(for kind: MonitorKind) -> Set<String> {
        Set(kind.availableMetrics.filter { $0.isDefault }.map { $0.id })
    }

    private func setupBindings() {
        $launchAtLogin
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persistLaunchAtLogin(newValue)
            }
            .store(in: &cancellables)

        $themePreference
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.themePreference)
            }
            .store(in: &cancellables)

        $colorSchemePreference
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.colorSchemePreference)
            }
            .store(in: &cancellables)

        $ringSource
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.ringSource)
            }
            .store(in: &cancellables)

        $showBuiltInDisplays
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showBuiltInDisplays)
            }
            .store(in: &cancellables)

        $displayModuleVisible
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayModuleVisible)
            }
            .store(in: &cancellables)

        $displayBrightnessControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayBrightnessControlEnabled)
            }
            .store(in: &cancellables)

        $displayVolumeControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayVolumeControlEnabled)
            }
            .store(in: &cancellables)

        $displayContrastControlEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.displayContrastControlEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyBrightnessEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyBrightnessEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyVolumeEnabled
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyVolumeEnabled)
            }
            .store(in: &cancellables)

        $mediaKeyShowOSD
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyShowOSD)
            }
            .store(in: &cancellables)

        $mediaKeyFineScaleBrightness
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyFineScaleBrightness)
            }
            .store(in: &cancellables)

        $mediaKeyFineScaleVolume
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.mediaKeyFineScaleVolume)
            }
            .store(in: &cancellables)

        $visibleKinds
            .dropFirst()
            .sink { [weak self] newValue in
                let values = newValue.map(\.rawValue)
                self?.persist(values, forKey: Keys.visibleKinds)
            }
            .store(in: &cancellables)

        $enabledMetrics
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self else { return }
                for (kind, ids) in newValue {
                    let key = Keys.enabledMetricsPrefix + kind.rawValue
                    self.persist(Array(ids), forKey: key)
                }
            }
            .store(in: &cancellables)
    }

    private func persist<T>(_ value: T, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private func persistLaunchAtLogin(_ newValue: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }
        updateLaunchAtLogin(newValue)
    }

    private func updateLaunchAtLogin(_ newValue: Bool) {
        do {
            if newValue {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            isUpdatingLaunchAtLogin = true
            launchAtLogin.toggle()
            isUpdatingLaunchAtLogin = false
        }
    }
}

private enum Keys {
    static let themePreference = "settings.themePreference"
    static let colorSchemePreference = "settings.colorSchemePreference"
    static let ringSource = "settings.ringSource"
    static let displayModuleVisible = "settings.display.moduleVisible"
    static let showBuiltInDisplays = "settings.display.showBuiltInDisplays"
    static let displayBrightnessControlEnabled = "settings.display.brightnessControlEnabled"
    static let displayVolumeControlEnabled = "settings.display.volumeControlEnabled"
    static let displayContrastControlEnabled = "settings.display.contrastControlEnabled"
    static let mediaKeyBrightnessEnabled = "settings.mediaKey.brightnessEnabled"
    static let mediaKeyVolumeEnabled = "settings.mediaKey.volumeEnabled"
    static let mediaKeyShowOSD = "settings.mediaKey.showOSD"
    static let mediaKeyFineScaleBrightness = "settings.mediaKey.fineScaleBrightness"
    static let mediaKeyFineScaleVolume = "settings.mediaKey.fineScaleVolume"
    static let visibleKinds = "settings.visibleKinds"
    static let enabledMetricsPrefix = "settings.enabledMetrics."
}
