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
            "跟随系统"
        case .light:
            "浅色"
        case .dark:
            "深色"
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
            "平衡"
        case .vibrant:
            "活力"
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
    @Published private(set) var visibleKinds: Set<MonitorKind> = []
    @Published private(set) var enabledMetrics: [MonitorKind: Set<String>] = [:]

    static let maximumEnabledMetricsPerKind = 4

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
                loadedMetrics[kind] = Set(stored)
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
        let current = enabledMetrics[kind] ?? defaultMetricIds(for: kind)
        return current.contains(id) || current.count < Self.maximumEnabledMetricsPerKind
    }

    func setMetric(_ id: String, enabled: Bool, for kind: MonitorKind) {
        var current = enabledMetrics[kind] ?? defaultMetricIds(for: kind)
        if enabled {
            guard current.contains(id) || current.count < Self.maximumEnabledMetricsPerKind else {
                return
            }
            current.insert(id)
        } else {
            current.remove(id)
        }
        enabledMetrics[kind] = current
    }

    func resetMetrics(for kind: MonitorKind) {
        enabledMetrics[kind] = defaultMetricIds(for: kind)
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
    static let visibleKinds = "settings.visibleKinds"
    static let enabledMetricsPrefix = "settings.enabledMetrics."
}
