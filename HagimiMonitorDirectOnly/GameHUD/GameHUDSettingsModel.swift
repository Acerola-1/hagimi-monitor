import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// 设置页操作的对象明确反馈。文案统一在本地化资源里维护,
/// 颜色只作补充,不把状态塞进行内徽章之外的角落。
nonisolated enum GameHUDActionFeedback: Equatable, Sendable {
    case added(String)
    case addedAfterRemoval(String)
    case alreadyEnabled(String)
    case excluded(String)
    case excludedEarly(String)
    case alreadyExcluded(String)
    case removedExclusion(String)
    case removedExclusionWithoutSource(String)
    case readFailed
    case scanFinished(Int)
    case scanFailed

    var message: String {
        switch self {
        case .added(let name):
            String(localized: "gamehud.games.feedback.added \(name)")
        case .addedAfterRemoval(let name):
            String(localized: "gamehud.games.feedback.added-after-removal \(name)")
        case .alreadyEnabled(let name):
            String(localized: "gamehud.games.feedback.already-enabled \(name)")
        case .excluded(let name):
            String(localized: "gamehud.games.feedback.excluded \(name)")
        case .excludedEarly(let name):
            String(localized: "gamehud.games.feedback.excluded-early \(name)")
        case .alreadyExcluded(let name):
            String(localized: "gamehud.games.feedback.already-excluded \(name)")
        case .removedExclusion(let name):
            String(localized: "gamehud.games.feedback.removed-exclusion \(name)")
        case .removedExclusionWithoutSource(let name):
            String(localized: "gamehud.games.feedback.removed-exclusion-no-source \(name)")
        case .readFailed:
            String(localized: "gamehud.games.feedback.read-failed")
        case .scanFinished(let count):
            String(localized: "gamehud.games.feedback.scan-finished \(count)")
        case .scanFailed:
            String(localized: "gamehud.games.feedback.scan-failed")
        }
    }
}

/// Game HUD 设置页的交互入口。视图只负责选择应用包并把 URL 交进来,
/// 所有登记修改都走 `MonitorSettings` 的单一通路,便于原生验收脚本复用。
@MainActor
final class GameHUDSettingsModel: ObservableObject {
    @Published private(set) var feedback: GameHUDActionFeedback?
    @Published private(set) var isScanning = false

    private let settings: MonitorSettings
    private let scanner: GameHUDGameScanner
    private var cancellables: Set<AnyCancellable> = []
    private var iconCache: [String: NSImage] = [:]
    private var lastHandledScanDate: Date?

    init(settings: MonitorSettings, scanner: GameHUDGameScanner) {
        self.settings = settings
        self.scanner = scanner
        scanner.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scanning in
                self?.isScanning = scanning
            }
            .store(in: &cancellables)
        scanner.$lastScanCompletedAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                guard let self, let date, date != self.lastHandledScanDate else { return }
                self.lastHandledScanDate = date
                self.feedback = self.scanner.lastScanFailed
                    ? .scanFailed
                    : .scanFinished(self.scanner.lastScanCount)
            }
            .store(in: &cancellables)
    }

    /// 总开关开启时复用常驻扫描缓存;关闭时不用打开页面本身触发扫描。
    /// 关闭状态下的单次扫描只由明确的「重新扫描」按钮发起。
    func onAppear() {
        guard settings.gameHUDMasterEnabled else { return }
        scanner.rescanFromSettings(force: false)
    }

    func rescan() {
        scanner.invalidate()
        scanner.rescanFromSettings(force: true)
    }

    func addApplication(at url: URL?) {
        guard let url, let identity = GameHUDApplicationIdentity(applicationURL: url) else {
            publish(.readFailed)
            return
        }
        let change = settings.addGameHUDManualApp(
            bundleID: identity.bundleID,
            name: identity.name,
            applicationPath: identity.applicationPath
        )
        if change.wasExcluded {
            publish(.addedAfterRemoval(identity.name))
        } else if !change.createdRecord {
            publish(.alreadyEnabled(identity.name))
        } else {
            publish(.added(identity.name))
        }
    }

    /// 提前排除:选择任意有效应用包,不要求它已被扫描发现。
    func addExclusion(at url: URL?) {
        guard let url, let identity = GameHUDApplicationIdentity(applicationURL: url) else {
            publish(.readFailed)
            return
        }
        let change = settings.excludeGameHUDGame(
            bundleID: identity.bundleID,
            name: identity.name,
            applicationPath: identity.applicationPath
        )
        if change.wasExcluded {
            publish(.alreadyExcluded(identity.name))
        } else if change.createdRecord {
            publish(.excludedEarly(identity.name))
        } else {
            publish(.excluded(identity.name))
        }
    }

    func exclude(_ app: GameHUDRegisteredApp) {
        let change = settings.excludeGameHUDGame(
            bundleID: app.bundleID,
            name: app.name,
            applicationPath: app.applicationPath
        )
        publish(change.wasExcluded ? .alreadyExcluded(displayName(for: app)) : .excluded(displayName(for: app)))
    }

    func removeExclusion(_ app: GameHUDRegisteredApp) {
        guard let change = settings.removeGameHUDExcludedGame(app.bundleID) else { return }
        let name = displayName(for: app)
        publish(change.isEnabled ? .removedExclusion(name) : .removedExclusionWithoutSource(name))
    }

    func displayName(for app: GameHUDRegisteredApp) -> String {
        if !app.name.isEmpty, app.name != app.bundleID {
            return app.name
        }
        if let url = packageURL(for: app) {
            let displayName = FileManager.default.displayName(atPath: url.path)
            if !displayName.isEmpty {
                return displayName
            }
        }
        return app.name.isEmpty ? app.bundleID : app.name
    }

    func packageURL(for app: GameHUDRegisteredApp) -> URL? {
        GameHUDPackageLocator.applicationURL(for: app)
    }

    func icon(for app: GameHUDRegisteredApp) -> NSImage {
        if let cached = iconCache[app.bundleID] {
            return cached
        }
        let icon: NSImage
        if let url = packageURL(for: app) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        iconCache[app.bundleID] = icon
        return icon
    }

    private func publish(_ feedback: GameHUDActionFeedback) {
        self.feedback = feedback
        AppLogger.diagnostics.info("GameHUD action: \(feedback.message, privacy: .public)")
        AccessibilityNotification.Announcement(feedback.message).post()
    }
}
