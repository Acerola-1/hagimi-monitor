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
    @Published var menuBarDisplayMode: MenuBarDisplayMode = .ring
    @Published private(set) var menuBarMetricKinds: [MenuBarMetricKind] = MenuBarMetricKind.defaultSelection
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
    @Published var showMemoryProcesses: Bool = true
    @Published var memoryShowSystemProcesses: Bool = false
    @Published var showCPUProcesses: Bool = false
    @Published var cpuShowSystemProcesses: Bool = false
    @Published var showDiskProcesses: Bool = false
    @Published var diskShowSystemProcesses: Bool = false
    @Published var showNetworkProcesses: Bool = false
    @Published var networkShowSystemProcesses: Bool = false
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

        ringSource = .combined

        let menuBarDisplayModeRawValue = defaults.string(forKey: Keys.menuBarDisplayMode) ?? MenuBarDisplayMode.ring.rawValue
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: menuBarDisplayModeRawValue) ?? .ring
        menuBarMetricKinds = MonitorSettings.validatedMenuBarMetrics(
            defaults.array(forKey: Keys.menuBarMetricKinds) as? [String]
        )

        showBuiltInDisplays = defaults.object(forKey: Keys.showBuiltInDisplays) as? Bool ?? true
        displayModuleVisible = defaults.object(forKey: Keys.displayModuleVisible) as? Bool ?? false
        displayBrightnessControlEnabled = defaults.object(forKey: Keys.displayBrightnessControlEnabled) as? Bool ?? true
        displayVolumeControlEnabled = defaults.object(forKey: Keys.displayVolumeControlEnabled) as? Bool ?? true
        displayContrastControlEnabled = defaults.object(forKey: Keys.displayContrastControlEnabled) as? Bool ?? false
        showMemoryProcesses = defaults.object(forKey: Keys.showMemoryProcesses) as? Bool ?? true
        memoryShowSystemProcesses = defaults.object(forKey: Keys.memoryShowSystemProcesses) as? Bool ?? false
        showCPUProcesses = defaults.object(forKey: Keys.showCPUProcesses) as? Bool ?? false
        cpuShowSystemProcesses = defaults.object(forKey: Keys.cpuShowSystemProcesses) as? Bool ?? false
        showDiskProcesses = defaults.object(forKey: Keys.showDiskProcesses) as? Bool ?? false
        diskShowSystemProcesses = defaults.object(forKey: Keys.diskShowSystemProcesses) as? Bool ?? false
        showNetworkProcesses = defaults.object(forKey: Keys.showNetworkProcesses) as? Bool ?? false
        networkShowSystemProcesses = defaults.object(forKey: Keys.networkShowSystemProcesses) as? Bool ?? false

        mediaKeyBrightnessEnabled = defaults.object(forKey: Keys.mediaKeyBrightnessEnabled) as? Bool ?? false
        mediaKeyVolumeEnabled = defaults.object(forKey: Keys.mediaKeyVolumeEnabled) as? Bool ?? false
        mediaKeyShowOSD = defaults.object(forKey: Keys.mediaKeyShowOSD) as? Bool ?? true
        mediaKeyFineScaleBrightness = defaults.object(forKey: Keys.mediaKeyFineScaleBrightness) as? Bool ?? false
        mediaKeyFineScaleVolume = defaults.object(forKey: Keys.mediaKeyFineScaleVolume) as? Bool ?? false

        if let storedKinds = defaults.array(forKey: Keys.visibleKinds) as? [String] {
            let kinds = storedKinds.compactMap(MonitorKind.init(rawValue:))
            visibleKinds = Set(kinds)
        } else {
            visibleKinds = Set(MonitorKind.userVisibleCases)
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

    func isMenuBarMetricSelected(_ kind: MenuBarMetricKind) -> Bool {
        menuBarMetricKinds.contains(kind)
    }

    func canSelectMenuBarMetric(_ kind: MenuBarMetricKind) -> Bool {
        isMenuBarMetricSelected(kind) || menuBarMetricKinds.count < MenuBarMetricKind.maximumSelectionCount
    }

    func setMenuBarMetric(_ kind: MenuBarMetricKind, selected: Bool) {
        var current = menuBarMetricKinds
        if selected {
            guard !current.contains(kind), current.count < MenuBarMetricKind.maximumSelectionCount else { return }
            current.append(kind)
        } else {
            current.removeAll { $0 == kind }
        }
        menuBarMetricKinds = current.isEmpty ? MenuBarMetricKind.defaultSelection : current
    }

    func moveMenuBarMetric(_ kind: MenuBarMetricKind, direction: Int) {
        guard let index = menuBarMetricKinds.firstIndex(of: kind) else { return }
        let target = index + direction
        guard menuBarMetricKinds.indices.contains(target) else { return }
        menuBarMetricKinds.swapAt(index, target)
    }

    private static func validatedMenuBarMetrics(_ rawValues: [String]?) -> [MenuBarMetricKind] {
        guard let rawValues else {
            return MenuBarMetricKind.defaultSelection
        }

        var result: [MenuBarMetricKind] = []
        for rawValue in rawValues {
            guard let kind = MenuBarMetricKind(rawValue: rawValue), !result.contains(kind) else {
                continue
            }
            result.append(kind)
            if result.count == MenuBarMetricKind.maximumSelectionCount {
                break
            }
        }

        return result.isEmpty ? MenuBarMetricKind.defaultSelection : result
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
                return ["IP 地址": "ipv4", "上传": "upload", "下载": "download"]
            case .battery:
                return ["充电功率": "charging-power", "健康度": "health", "循环数": "cycle-count", "温度": "temperature", "适配器": "adapter", "功耗": "power"]
            case .power:
                return ["功率": "power-watts"]
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
            .sink { [weak self] _ in
                self?.persist(HaloRingSource.combined.rawValue, forKey: Keys.ringSource)
            }
            .store(in: &cancellables)

        $menuBarDisplayMode
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.rawValue, forKey: Keys.menuBarDisplayMode)
            }
            .store(in: &cancellables)

        $menuBarMetricKinds
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue.map(\.rawValue), forKey: Keys.menuBarMetricKinds)
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

        $showMemoryProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showMemoryProcesses)
            }
            .store(in: &cancellables)

        $memoryShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.memoryShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showCPUProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showCPUProcesses)
            }
            .store(in: &cancellables)

        $cpuShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.cpuShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showDiskProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showDiskProcesses)
            }
            .store(in: &cancellables)

        $diskShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.diskShowSystemProcesses)
            }
            .store(in: &cancellables)

        $showNetworkProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.showNetworkProcesses)
            }
            .store(in: &cancellables)

        $networkShowSystemProcesses
            .dropFirst()
            .sink { [weak self] newValue in
                self?.persist(newValue, forKey: Keys.networkShowSystemProcesses)
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
    static let menuBarDisplayMode = "settings.menuBar.displayMode"
    static let menuBarMetricKinds = "settings.menuBar.metricKinds"
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
    static let showMemoryProcesses = "settings.memory.showProcesses"
    static let memoryShowSystemProcesses = "settings.memory.showSystemProcesses"
    static let showCPUProcesses = "settings.cpu.showProcesses"
    static let cpuShowSystemProcesses = "settings.cpu.showSystemProcesses"
    static let showDiskProcesses = "settings.disk.showProcesses"
    static let diskShowSystemProcesses = "settings.disk.showSystemProcesses"
    static let showNetworkProcesses = "settings.network.showProcesses"
    static let networkShowSystemProcesses = "settings.network.showSystemProcesses"
    static let visibleKinds = "settings.visibleKinds"
    static let enabledMetricsPrefix = "settings.enabledMetrics."
}
