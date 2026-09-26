import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

/// Game HUD 会话状态。区分「总开关」「前台命中」「窗口可确认」三层:
/// 设置页状态文案与 HUD 显隐都从这里读。
nonisolated enum GameHUDSessionState: Equatable, Sendable {
    case disabled
    case idle
    case eligibleNoWindow
    case hardwareVisible
    case controlledPending
    case controlledTelemetryVisible

    var rawValue: String {
        switch self {
        case .disabled: "disabled"
        case .idle: "idle"
        case .eligibleNoWindow: "eligibleNoWindow"
        case .hardwareVisible: "hardwareVisible"
        case .controlledPending: "controlledPending"
        case .controlledTelemetryVisible: "controlledTelemetryVisible"
        }
    }
}

/// Game HUD 会话控制器:总开关 × 前台游戏 × 目标窗口的三层判定与
/// 显示生命周期(见 design 决策 1)。
///
/// 轮询节奏:受 settings.gameHUDMasterEnabled 总开关门控,开启时每秒检测前台游戏与窗口几何;总开关关闭时停止轮询。
@MainActor
final class GameHUDSessionController: ObservableObject {

    @Published private(set) var state: GameHUDSessionState = .disabled
    /// 当前命中的前台游戏(仅名单命中时有值;设置页状态区读名称)。
    @Published private(set) var foregroundGame: GameHUDForegroundGame?
    /// 当前确认的目标窗口矩形(屏幕坐标系)。
    @Published private(set) var targetRect: CGRect?
    /// 目标窗口所属屏幕。
    @Published private(set) var targetScreen: NSScreen?

    /// HUD 显示侧:全局左/右设置,始终跟随(纯自动形态无启动快照)。
    var sidePreference: GameHUDSide {
        settings.gameHUDSidePreference
    }

    private let settings: MonitorSettings
    private let windowLocator: GameHUDWindowLocator
    private let dataSource: GameHUDSnapshotProviding
    /// HUD 卡片能塞进目标窗口的最小尺寸(pt)。
    let minimumWindowSize = CGSize(width: 260, height: 200)

    private var pollTimer: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var workspaceCancellables: Set<AnyCancellable> = []

    init(settings: MonitorSettings, dataSource: GameHUDSnapshotProviding) {
        self.settings = settings
        self.dataSource = dataSource
        self.windowLocator = GameHUDWindowLocator()
        observeSettings()
        if settings.gameHUDMasterEnabled {
            startPolling()
        }
    }

    /// 每轮轮询:前台识别 → 名单匹配 → 窗口确认 → 状态收敛。
    /// 全程只读公开 API,结果不可确认就隐藏,不做近似猜测。
    func poll() {
        guard settings.gameHUDMasterEnabled else {
            transition(to: .disabled)
            return
        }
        guard let game = foregroundMatchedGame() else {
            clearForeground()
            transition(to: .idle)
            return
        }
        if foregroundGame != game {
            foregroundGame = game
            onGameLaunched?(game)
        }
        switch windowLocator.resolveTargetWindow(processIdentifier: game.processIdentifier, minimumSize: minimumWindowSize) {
        case .unavailable:
            targetRect = nil
            targetScreen = nil
            transition(to: .eligibleNoWindow)
        case .target(let rect, let screen):
            targetRect = rect
            targetScreen = screen
            transition(to: state == .controlledPending || state == .controlledTelemetryVisible
                ? state
                : .hardwareVisible)
        }
    }

    /// 状态变化落一条诊断日志:显示门槛三层(开关/名单/窗口)哪层没过,
    /// 现场排障用;不逐轮刷屏(仅 transition 时打)。
    private func logTransition(_ from: GameHUDSessionState, to: GameHUDSessionState, game: GameHUDForegroundGame?) {
        let detail = game.map { " bundle=\($0.bundleID) pid=\($0.processIdentifier)" } ?? ""
        AppLogger.diagnostics.info("GameHUD state \(from.rawValue, privacy: .public) -> \(to.rawValue, privacy: .public)\(detail, privacy: .public)")
    }

    /// 名单内游戏启动时的自动预备钩子(官网版写 per-app 偏好)。由 AppDelegate 装配时注入。
    var onGameLaunched: ((GameHUDForegroundGame) -> Void)?


    // MARK: - 内部

    /// 前台应用 → 名单匹配。严格仅匹配 frontmostApplication。
    /// 当用户从全屏游戏通过 Cmd+Tab、三指滑动或点击 Dock 切出时，frontmostApplication
    /// 变为其他应用或系统，立刻判定为非前台并隐藏 HUD，避免将用户强行拽回游戏 Space。
    private func foregroundMatchedGame() -> GameHUDForegroundGame? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              GameHUDGameDirectory.matches(bundleID: app.bundleIdentifier, settings: settings) else {
            return nil
        }
        return GameHUDForegroundGame(
            bundleID: app.bundleIdentifier ?? "",
            processIdentifier: app.processIdentifier,
            localizedName: app.localizedName ?? ""
        )
    }

    private func clearForeground() {
        if foregroundGame != nil {
            foregroundGame = nil
        }
        if targetRect != nil {
            targetRect = nil
        }
        if targetScreen != nil {
            targetScreen = nil
        }
    }

    private func transition(to newState: GameHUDSessionState) {
        guard state != newState else { return }
        logTransition(state, to: newState, game: foregroundGame)
        state = newState
    }

    private func observeSettings() {
        settingsCancellable = settings.$gameHUDMasterEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.startPolling()
                } else {
                    self.stopPolling()
                }
            }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        AppLogger.diagnostics.info("GameHUD polling start, masterEnabled=\(self.settings.gameHUDMasterEnabled, privacy: .public) customGames=\(self.settings.gameHUDCustomGames.count, privacy: .public)")
        poll()
        pollTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.poll()
            }

        let nc = NSWorkspace.shared.notificationCenter
        workspaceCancellables.removeAll()
        nc.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.poll()
            }
            .store(in: &workspaceCancellables)
        nc.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.poll()
            }
            .store(in: &workspaceCancellables)
        nc.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.poll()
            }
            .store(in: &workspaceCancellables)
    }

    private func stopPolling() {
        pollTimer = nil
        workspaceCancellables.removeAll()
        clearForeground()
        transition(to: .disabled)
    }
}
