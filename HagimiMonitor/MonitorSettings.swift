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

final class MonitorSettings: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            guard oldValue != launchAtLogin else { return }
            updateLaunchAtLogin()
        }
    }

    @Published var themePreference: AppThemePreference {
        didSet {
            defaults.set(themePreference.rawValue, forKey: Keys.themePreference)
        }
    }

    @Published private(set) var visibleKinds: Set<MonitorKind> {
        didSet {
            let values = visibleKinds.map(\.rawValue)
            defaults.set(values, forKey: Keys.visibleKinds)
        }
    }

    private let defaults: UserDefaults
    private var isUpdatingLaunchAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let themeRawValue = defaults.string(forKey: Keys.themePreference) ?? AppThemePreference.system.rawValue
        themePreference = AppThemePreference(rawValue: themeRawValue) ?? .system

        if let storedKinds = defaults.array(forKey: Keys.visibleKinds) as? [String] {
            let kinds = storedKinds.compactMap(MonitorKind.init(rawValue:))
            visibleKinds = Set(kinds)
        } else {
            visibleKinds = Set(MonitorKind.allCases)
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
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

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
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
    static let visibleKinds = "settings.visibleKinds"
}
