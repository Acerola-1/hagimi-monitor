import AppKit
import Combine
import OSLog
import SwiftUI

/// Game HUD 总装配:订阅会话状态与硬件快照,驱动浮窗显隐与内容更新。
///
/// 职责边界:
/// - 会话控制器只判定「显示什么、在哪显示」;
/// - 本协调器把判定结果落到 NSPanel,并在隐藏时断开快照订阅
///   (隐藏不重绘、不执行仅为 HUD 服务的后续工作,spec:生命周期和性能);
/// - 设置页与工具区开关都只改 `MonitorSettings.gameHUDMasterEnabled`,
///   会话控制器自行响应,不经过这里。
/// - 官方 HUD 的呈现走 per-app 偏好自动预备(见 observeGameLaunches),
///   玩家从任意途径正常启动游戏即可,无注入启动通路。
@MainActor
final class GameHUDCoordinator {

    /// 硬件浮窗「正在显示」标记:供菜单栏图标绘制 HUD 运行徽章。
    @Published private(set) var isShowing: Bool = false

    private let settings: MonitorSettings
    private let store: MonitorStore
    private let sessionController: GameHUDSessionController
    private let panelController: GameHUDPanelController
    private var snapshotCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var rectCancellable: AnyCancellable?
    private var sideCancellable: AnyCancellable?
    /// 最近一次快照(显示中逐轮更新;隐藏时清空,配合历史重置)。
    private var latestSnapshot = GameHUDSnapshot.empty
    private var history = GameHUDSampleHistory()
    /// SCK 窗口捕获测帧:对前台游戏窗口测实际呈现帧率(上屏口径),
    /// 覆盖非 Metal 游戏;Metal 游戏与官方 HUD 并存互补。
    private let frameMeter = GameHUDFrameMeter()
    private var frameStatsCancellable: AnyCancellable?

    init(settings: MonitorSettings, store: MonitorStore) {
        self.settings = settings
        self.store = store
        self.sessionController = GameHUDSessionController(settings: settings, dataSource: store.gameHUDDataSource)
        self.panelController = GameHUDPanelController(settings: settings)
        observeSession()
        observeGameLaunches()
        observeSideChanges()
        frameStatsCancellable = frameMeter.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                guard let self else { return }
                if let fps = stats?.displayFPS {
                    self.history.recordFPS(fps)
                }
                // 统计值变化时刷新内容(FPS 行出现/数值更新)。
                guard self.sessionController.state == .hardwareVisible,
                      let rect = self.sessionController.targetRect else { return }
                self.panelController.show(in: rect, reserveTop: false, fpsStats: stats, content: self.makeContentView())
            }
        // 屏幕录制授权完成:若有显示中的游戏会话,立即补启测帧(不用等下次启动)。
        ScreenCapturePermissionService.shared.onGranted = { [weak self] in
            guard let self, self.sessionController.state == .hardwareVisible,
                  let game = self.sessionController.foregroundGame,
                  let running = NSRunningApplication(processIdentifier: game.processIdentifier) else { return }
            self.frameMeter.start(target: running)
        }
    }

    // MARK: - 会话驱动

    private func observeSession() {
        stateCancellable = sessionController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.apply(state: state)
                self.isShowing = (state == .hardwareVisible)
            }
        // 每轮轮询都会重赋 targetRect(@Published 无同值抑制),这是真正的
        // 逐节拍路径:前台游戏身份比对(测帧重启)与浮窗落位都在这里做,
        // 不依赖 state 变化(游戏 A→B 切换 state 恒为 hardwareVisible)。
        rectCancellable = sessionController.$targetRect
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rect in
                guard let self else { return }
                guard rect != nil, self.sessionController.state == .hardwareVisible else { return }
                self.presentDisplay()
            }
    }

    /// 普通会话中改侧边即时移动,此处只响应硬件窗几何。
    private func observeSideChanges() {
        sideCancellable = settings.$gameHUDSidePreference
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.sessionController.targetRect != nil else { return }
                self.panelController.updateFrame(
                    in: self.sessionController.targetRect!,
                    reserveTop: false,
                    fpsStats: self.frameMeter.stats
                )
            }
    }

    private func apply(state: GameHUDSessionState) {
        switch state {
        case .disabled, .idle, .eligibleNoWindow:
            teardownDisplay()
        case .hardwareVisible:
            presentDisplay()
        case .controlledPending, .controlledTelemetryVisible:
            // 预留状态，对齐 hardwareVisible 呈现
            presentDisplay()
        }
    }

    private func presentDisplay() {
        guard let rect = sessionController.targetRect else {
            teardownDisplay()
            return
        }
        subscribeSnapshotIfNeeded()
        syncFrameMeterTarget()
        // 逐轮落位:窗口移动/缩放/换屏由 1s 轮询捕获,这里按最新矩形刷新。
        panelController.show(
            in: rect,
            reserveTop: false,
            fpsStats: frameMeter.stats,
            content: makeContentView()
        )
    }

    /// 测帧目标与前台游戏对齐(每轮轮询都调用):状态同为 hardwareVisible 时
    /// 游戏 A→B 切换不产生 state 变化,必须按身份比对重启,否则读到旧窗口。
    /// FrameMeter 自身对同一目标幂等(不重启流,保护样本窗口)。
    private func syncFrameMeterTarget() {
        guard let game = sessionController.foregroundGame else {
            frameMeter.stop()
            return
        }
        guard let running = NSRunningApplication(processIdentifier: game.processIdentifier) else {
            frameMeter.stop()
            return
        }
        frameMeter.start(target: running)
    }

    private func teardownDisplay() {
        isShowing = false
        snapshotCancellable = nil
        history.reset()
        latestSnapshot = .empty
        frameMeter.stop()
        panelController.hide()
    }

    /// 清理名单内游戏的官方 HUD 偏好:删除 per-app `MetalForceHudEnabled`,
    /// 确保纯净呈现 Hagimi 自研 HUD,不让系统自带 HUD 冒出来干扰。
    private func observeGameLaunches() {
        sessionController.onGameLaunched = { [weak self] game in
            guard let self else { return }
            self.cleanGame(bundleID: game.bundleID)
            if let running = NSRunningApplication(processIdentifier: game.processIdentifier) {
                self.frameMeter.start(target: running)
            }
        }
        scannerObservation = GameHUDGameScanner.shared.$discoveredGames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                guard let self, !games.isEmpty else { return }
                for game in games where !self.cleanedBundleIDs.contains(game.bundleID) {
                    self.cleanGame(bundleID: game.bundleID)
                }
            }
    }

    private var scannerObservation: AnyCancellable?
    /// 已清理过的游戏(进程内去重,避免重复 fork defaults)。
    private var cleanedBundleIDs: Set<String> = []

    private func cleanGame(bundleID: String) {
        guard !cleanedBundleIDs.contains(bundleID) else { return }
        cleanedBundleIDs.insert(bundleID)
        GameHUDGameScanner.cleanupPerAppHUD(bundleID: bundleID)
    }

    // MARK: - 快照订阅

    /// 仅显示期间订阅快照;teardown 取消订阅后发布链无消费者,
    /// provider 的比对成本也因无勾选快照短路(spec:隐藏不重绘)。
    private func subscribeSnapshotIfNeeded() {
        guard snapshotCancellable == nil else { return }
        history.reset()
        latestSnapshot = store.gameHUDDataSource.currentSnapshot(enabledIDs: settings.gameHUDEnabledMetricIDs)
        history.record(latestSnapshot)
        snapshotCancellable = store.gameHUDDataSource.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                self.history.record(snapshot)
                // 只刷新内容,不动 frame;几何变化走会话轮询路径。
                self.panelController.show(
                    in: self.sessionController.targetRect ?? .zero,
                    reserveTop: false,
                    fpsStats: self.frameMeter.stats,
                    content: self.makeContentView()
                )
            }
    }

    private func makeContentView() -> GameHUDContent {
        GameHUDContent(
            view: AnyView(GameHUDView(
                snapshot: latestSnapshot,
                fpsStats: frameMeter.stats,
                enabledMetricIDs: settings.gameHUDEnabledMetricIDs
            ))
        )
    }
}
