import AppKit
import Foundation
import SwiftUI

#if DEBUG
/// 原生验收夹具:由 `HAGIMI_GAMEHUD_VERIFY_CONFIG` 指向的 JSON 驱动。
///
/// 只在 Debug 构建、隔离偏好下启用;操作走设置页相同的 `GameHUDSettingsModel`
/// 与 `MonitorSettings` 通路,并把真实结果写入 `HAGIMI_GAMEHUD_VERIFY_LOG`。
/// 不参与正式运行,也不改变任何产品的默认路径。
@MainActor
enum GameHUDVerificationFixture {
    static func runIfRequested(store: MonitorStore) {
        guard let configPath = ProcessInfo.processInfo.environment["HAGIMI_GAMEHUD_VERIFY_CONFIG"],
              !configPath.isEmpty else {
            return
        }
        guard let data = FileManager.default.contents(atPath: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            NSLog("[gamehud-verify] cannot read config at %@", configPath)
            return
        }
        Runner(store: store, config: config).start()
    }

    struct Config: Decodable {
        var logPath: String?
        var openSettings: Bool?
        var windowHeight: Double?
        var operations: [Operation]
    }

    struct Operation: Decodable {
        var op: String
        var bundleID: String?
        var name: String?
        var path: String?
        var origin: String?
        var source: String?
        var style: String?
        var value: Double?
        var enabled: Bool?
        var force: Bool?
        var seconds: Double?
        var label: String?
        var apps: [ScanApp]?
    }

    struct ScanApp: Decodable {
        var bundleID: String
        var name: String
        var path: String?
        var source: String
    }

    @MainActor
    private final class Runner {
        private let store: MonitorStore
        private let config: Config
        private let model: GameHUDSettingsModel
        private let logURL: URL?

        init(store: MonitorStore, config: Config) {
            self.store = store
            self.config = config
            self.model = GameHUDSettingsModel(
                settings: store.settings,
                scanner: GameHUDGameScanner.shared
            )
            let resolvedLogPath = config.logPath
                ?? ProcessInfo.processInfo.environment["HAGIMI_GAMEHUD_VERIFY_LOG"]
            self.logURL = resolvedLogPath.flatMap { path in
                path.isEmpty ? nil : URL(fileURLWithPath: path)
            }
        }

        func start() {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                log("fixture start bundle=\(Bundle.main.bundleIdentifier ?? "?")")
                logSnapshot(label: "launch")
                for operation in config.operations {
                    await perform(operation)
                }
                if config.openSettings == true {
                    log("openSettings tab=gameHUD")
                    SettingsWindowPresenter.open(tab: .gameHUD)
                }
                try? await Task.sleep(for: .milliseconds(700))
                if let height = config.windowHeight {
                    resizeSettingsWindow(height: height)
                }
                logSnapshot(label: "final")
                try? await Task.sleep(for: .milliseconds(300))
                log("fixture done")
            }
        }

        private func perform(_ operation: Operation) async {
            switch operation.op {
            case "reset":
                store.settings.resetGameHUDStateForVerification()
                log("reset registry + transparency")
            case "setMaster":
                store.settings.gameHUDMasterEnabled = operation.enabled ?? false
                log("setMaster enabled=\(store.settings.gameHUDMasterEnabled)")
            case "mergeScan":
                let apps = (operation.apps ?? []).map { app in
                    GameHUDScannedApp(
                        bundleID: app.bundleID,
                        name: app.name,
                        applicationPath: app.path,
                        source: recognitionSource(app.source)
                    )
                }
                store.settings.mergeGameHUDScannedApps(apps)
                log("mergeScan count=\(apps.count)")
            case "addManual":
                guard let path = operation.path else {
                    log("addManual missing path")
                    return
                }
                model.addApplication(at: URL(fileURLWithPath: path))
                log("addManual path=\(path) feedback=\(model.feedback?.message ?? "-")")
            case "addPreviouslyAdded":
                let change = store.settings.addGameHUDManualApp(
                    bundleID: operation.bundleID ?? "",
                    name: operation.name ?? "",
                    applicationPath: operation.path,
                    origin: .previouslyAdded
                )
                log("addPreviouslyAdded id=\(operation.bundleID ?? "-") created=\(change.createdRecord) enabled=\(change.isEnabled)")
            case "addExclusion":
                guard let path = operation.path else {
                    log("addExclusion missing path")
                    return
                }
                model.addExclusion(at: URL(fileURLWithPath: path))
                log("addExclusion path=\(path) feedback=\(model.feedback?.message ?? "-")")
            case "exclude":
                guard let id = operation.bundleID,
                      let record = store.settings.gameHUDRegistry.record(for: id) else {
                    log("exclude missing record id=\(operation.bundleID ?? "-")")
                    return
                }
                model.exclude(record)
                log("exclude id=\(id) feedback=\(model.feedback?.message ?? "-")")
            case "removeExclusion":
                guard let id = operation.bundleID,
                      let record = store.settings.gameHUDRegistry.record(for: id) else {
                    log("removeExclusion missing record id=\(operation.bundleID ?? "-")")
                    return
                }
                model.removeExclusion(record)
                log("removeExclusion id=\(id) feedback=\(model.feedback?.message ?? "-")")
            case "setStyle":
                store.settings.gameHUDPresentationStyle = GameHUDPresentationStyle(
                    fromStored: operation.style ?? ""
                )
                log("setStyle style=\(store.settings.gameHUDPresentationStyle.rawValue)")
            case "setTransparency":
                guard let style = parseStyle(operation.style) else {
                    log("setTransparency missing style")
                    return
                }
                let value = operation.value ?? 0
                store.settings.setGameHUDBackgroundTransparency(value, for: style)
                log("setTransparency style=\(style.rawValue) value=\(store.settings.gameHUDBackgroundTransparency(for: style))")
            case "resetTransparency":
                guard let style = parseStyle(operation.style) else {
                    log("resetTransparency missing style")
                    return
                }
                store.settings.resetGameHUDBackgroundTransparency(for: style)
                log("resetTransparency style=\(style.rawValue) value=\(store.settings.gameHUDBackgroundTransparency(for: style))")
            case "rescan":
                let force = operation.force ?? true
                GameHUDGameScanner.shared.invalidate()
                GameHUDGameScanner.shared.rescanFromSettings(force: force)
                let deadline = Date().addingTimeInterval(25)
                while GameHUDGameScanner.shared.isScanning, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                log("rescan force=\(force) finished=\(!GameHUDGameScanner.shared.isScanning) count=\(GameHUDGameScanner.shared.lastScanCount) failed=\(GameHUDGameScanner.shared.lastScanFailed)")
            case "wait":
                let seconds = operation.seconds ?? 1
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                log("wait seconds=\(seconds)")
            case "snapshot":
                logSnapshot(label: operation.label ?? "snapshot")
            case "openSettings":
                log("openSettings tab=gameHUD")
                SettingsWindowPresenter.open(tab: .gameHUD)
            case "windowHeight":
                resizeSettingsWindow(height: operation.value ?? 800)
            case "log":
                log(operation.label ?? "")
            default:
                log("unknown op=\(operation.op)")
            }
        }

        private func parseStyle(_ raw: String?) -> GameHUDPresentationStyle? {
            switch raw {
            case "card": .card
            case "topStrip", "top-strip": .topStrip
            default: nil
            }
        }

        private func recognitionSource(_ raw: String) -> GameHUDRecognitionSource {
            switch raw {
            case "epic", "epicManifest": .epicManifest
            case "steam", "steamManifest": .steamManifest
            default: .applicationCategory
            }
        }

        private func resizeSettingsWindow(height: Double) {
            guard let window = SettingsWindowPresenter.settingsWindow else {
                log("resizeSettingsWindow missing window")
                return
            }
            var frame = window.frame
            frame.origin.y += frame.height - height
            frame.size.height = height
            window.setFrame(frame, display: true)
            log("resizeSettingsWindow height=\(height) actual=\(window.frame.height)")
        }

        private func logSnapshot(label: String) {
            let settings = store.settings
            log("snapshot[\(label)] master=\(settings.gameHUDMasterEnabled) style=\(settings.gameHUDPresentationStyle.rawValue) side=\(settings.gameHUDSidePreference.rawValue) cardTransparency=\(settings.gameHUDCardTransparency) stripTransparency=\(settings.gameHUDTopStripTransparency) hudShowing=\(AppDelegate.shared?.gameHUDCoordinator.isShowing ?? false)")
            log("snapshot[\(label)] enabled=\(settings.gameHUDRegistry.enabledApps.count) excluded=\(settings.gameHUDRegistry.excludedApps.count)")
            for app in settings.gameHUDRegistry.enabledApps {
                let available = GameHUDPackageLocator.applicationURL(for: app) != nil
                log("enabled id=\(app.bundleID) name=\(app.name) badge=\(app.badge?.rawValue ?? "none") sources=\(app.sources.map(\.rawValue).sorted().joined(separator: "+")) available=\(available)")
            }
            for app in settings.gameHUDRegistry.excludedApps {
                let available = GameHUDPackageLocator.applicationURL(for: app) != nil
                log("excluded id=\(app.bundleID) name=\(app.name) badge=\(app.badge?.rawValue ?? "none") sources=\(app.sources.map(\.rawValue).sorted().joined(separator: "+")) available=\(available)")
            }
        }

        private func log(_ message: String) {
            let stamped = "[\(Self.timestamp())] \(message)"
            NSLog("[gamehud-verify] %@", message)
            guard let logURL else { return }
            let line = Data((stamped + "\n").utf8)
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: logURL)
            }
        }

        private static func timestamp() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: Date())
        }
    }
}
#endif
