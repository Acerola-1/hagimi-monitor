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
    /// 合格游戏会话处于活跃态(窗口拖动期临时隐藏仍保持 true)，供 SMC 温度门控与设置页状态展示。
    @Published private(set) var isSessionActive: Bool = false
    /// 当前会话监测的游戏名称(支持同活跃态切换游戏时实时发布给设置页)。
    @Published private(set) var activeGameName: String?

    var foregroundGameName: String? {
        if let activeGameName, !activeGameName.isEmpty {
            return activeGameName
        }
        guard let name = sessionController.foregroundGame?.localizedName, !name.isEmpty else {
            return nil
        }
        return name
    }

    var sessionState: GameHUDSessionState {
        sessionController.state
    }

    private let settings: MonitorSettings
    private let dataSource: any GameHUDSnapshotProviding
    private let sessionController: GameHUDSessionController
    private let panelController: GameHUDPanelController
    private var snapshotCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var foregroundGameCancellable: AnyCancellable?
    private var sideCancellable: AnyCancellable?
    private var styleCancellable: AnyCancellable?
    private var metricsCancellable: AnyCancellable?
    private var transparencyCancellables: Set<AnyCancellable> = []
    private var registryCancellable: AnyCancellable?
    /// 最近一次快照；移动期继续缓存，真正结束会话时清空。
    private var latestSnapshot = GameHUDSnapshot.empty
    /// 系统 Metal 呈现统计；无可信样本时 HUD 保留占位。
    private let frameMeter: any GameHUDFrameMeasuring
    private var frameStatsCancellable: AnyCancellable?

    convenience init(settings: MonitorSettings, store: MonitorStore) {
        self.init(settings: settings, dataSource: store.gameHUDDataSource)
    }

    init(settings: MonitorSettings, dataSource: any GameHUDSnapshotProviding,
         sessionController: GameHUDSessionController? = nil, panelController: GameHUDPanelController? = nil,
         frameMeter: any GameHUDFrameMeasuring = GameHUDFrameMeter()) {
        self.settings = settings
        self.dataSource = dataSource
        self.sessionController = sessionController ?? GameHUDSessionController(settings: settings)
        self.panelController = panelController ?? GameHUDPanelController(settings: settings)
        self.frameMeter = frameMeter
        observeSession()
        observeGameLaunches()
        observeSideChanges()
        styleCancellable = settings.$gameHUDPresentationStyle
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.sessionController.targetRect != nil else { return }
                self.presentDisplay()
            }
        metricsCancellable = settings.$gameHUDEnabledMetricIDs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                guard let self, self.sessionController.isTargetPermitted else { return }
                self.latestSnapshot = self.dataSource.currentSnapshot(enabledIDs: ids)
                if GameHUDMetricCatalog.readableIDs(from: ids).isEmpty {
                    self.panelController.hide()
                    if self.isShowing { self.isShowing = false }
                    return
                }
                self.refreshVisibleContent()
            }
        // 透明度只改变背景渲染;数值更新不重启测帧/采样,也不重建材质。
        settings.$gameHUDCardTransparency
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibleContent() }
            .store(in: &transparencyCancellables)
        settings.$gameHUDTopStripTransparency
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibleContent() }
            .store(in: &transparencyCancellables)
        // 黑名单/名单变化时立即复核:已排除目标必须在下一次回调前隐藏。
        registryCancellable = settings.$gameHUDRegistry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.sessionController.state == .hardwareVisible else { return }
                guard self.sessionController.isTargetPermitted else {
                    self.teardownDisplay()
                    return
                }
                self.presentDisplay()
            }
        frameStatsCancellable = frameMeter.statsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshVisibleContent()
            }
    }

    // MARK: - 会话驱动

    private func observeSession() {
        stateCancellable = sessionController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.apply(state: self.sessionController.state)
            }
        foregroundGameCancellable = sessionController.$foregroundGame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] game in
                guard let self else { return }
                let resolved = game.flatMap { $0.localizedName.isEmpty ? nil : $0.localizedName }
                if self.activeGameName != resolved {
                    self.activeGameName = resolved
                }
            }
        // 完整发现与移动状态共用呈现门控，移动期间的回调不能恢复浮窗。
        sessionController.onSessionUpdated = { [weak self] in self?.presentDisplay(refreshContent: false) }
        sessionController.onGeometryChanged = { [weak self] in self?.updateGeometry() }
    }

    /// 普通会话中改侧边即时移动,此处只响应硬件窗几何。
    private func observeSideChanges() {
        sideCancellable = settings.$gameHUDSidePreference
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGeometry()
            }
    }

    private func apply(state: GameHUDSessionState) {
        switch state {
        case .disabled, .idle, .eligibleNoWindow:
            teardownDisplay()
        case .hardwareVisible:
            if !isSessionActive { isSessionActive = true }
            presentDisplay()
        }
    }

    private func presentDisplay(refreshContent: Bool = true) {
        // 所有呈现路径(状态、几何、快照、测帧、样式、透明度)都复核最新资格:
        // 排队中的旧回调不能在排除后重新显示目标。
        guard sessionController.isTargetPermitted,
              let rect = sessionController.targetRect else {
            teardownDisplay()
            return
        }
        if !isSessionActive { isSessionActive = true }
        subscribeSnapshotIfNeeded()
        syncFrameMeterTarget()
        guard !deferPresentationDuringMotion() else { return }
        if GameHUDMetricCatalog.readableIDs(from: settings.gameHUDEnabledMetricIDs).isEmpty {
            panelController.hide()
            if isShowing { isShowing = false }
            return
        }
        if !refreshContent {
            updateGeometry()
            return
        }
        // 身份/内容路径负责提交视图，停稳与位置设置走 updateGeometry。
        panelController.present(
            in: rect,
            screen: sessionController.targetScreen,
            snapshot: latestSnapshot,
            fpsStats: frameMeter.stats,
            enabledMetricIDs: settings.gameHUDEnabledMetricIDs,
            cardTransparency: settings.gameHUDCardTransparency,
            topStripTransparency: settings.gameHUDTopStripTransparency
        )
        finishPresentation()
    }

    private func updateGeometry() {
        guard sessionController.isTargetPermitted, let rect = sessionController.targetRect else {
            teardownDisplay()
            return
        }
        guard !deferPresentationDuringMotion() else { return }
        if GameHUDMetricCatalog.readableIDs(from: settings.gameHUDEnabledMetricIDs).isEmpty {
            panelController.hide()
            if isShowing { isShowing = false }
            return
        }
        let needsContent = panelController.updateFrame(
            in: rect, screen: sessionController.targetScreen, reserveTop: false, fpsStats: frameMeter.stats)
        if needsContent { refreshVisibleContent() }
        finishPresentation()
    }

    private func finishPresentation() {
        let visible = panelController.isVisible
        if isShowing != visible { isShowing = visible }
        if !visible {
            sessionController.suspendTrackingForUnavailableLayout()
        }
    }

    private func deferPresentationDuringMotion() -> Bool {
        guard sessionController.isMotionHidden else { return false }
        panelController.suspendForWindowMotion()
        if isShowing { isShowing = false }
        return true
    }

    /// 透明度/样式变化只更新持久化内容状态,不触碰会话、测帧或采样。
    private func refreshVisibleContent() {
        guard sessionController.isTargetPermitted,
              let rect = sessionController.targetRect else { return }
        guard !deferPresentationDuringMotion() else { return }
        if GameHUDMetricCatalog.readableIDs(from: settings.gameHUDEnabledMetricIDs).isEmpty {
            panelController.hide()
            if isShowing { isShowing = false }
            return
        }
        panelController.present(
            in: rect,
            screen: sessionController.targetScreen,
            snapshot: latestSnapshot,
            fpsStats: frameMeter.stats,
            enabledMetricIDs: settings.gameHUDEnabledMetricIDs,
            cardTransparency: settings.gameHUDCardTransparency,
            topStripTransparency: settings.gameHUDTopStripTransparency
        )
        finishPresentation()
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
        if isShowing { isShowing = false }
        if isSessionActive { isSessionActive = false }
        if activeGameName != nil { activeGameName = nil }
        snapshotCancellable = nil
        latestSnapshot = .empty
        frameMeter.stop()
        panelController.hide()
    }

    /// 名单内游戏启动时的运行时钩子:仅同步启动进程级 Metal 测帧与动态抑制，
    /// 不改写外部应用的持久化偏好。
    private func observeGameLaunches() {
        sessionController.onGameLaunched = { [weak self] game in
            guard let self else { return }
            guard self.settings.gameHUDMasterEnabled,
                  self.settings.gameHUDRegistry.isEligible(game.bundleID) else { return }
            if let running = NSRunningApplication(processIdentifier: game.processIdentifier) {
                self.frameMeter.start(target: running)
            }
        }
    }

    // MARK: - 快照订阅

    /// 合格会话订阅快照；移动期只缓存，真正 teardown 才取消。
    private func subscribeSnapshotIfNeeded() {
        guard snapshotCancellable == nil else { return }
        latestSnapshot = dataSource.currentSnapshot(enabledIDs: settings.gameHUDEnabledMetricIDs)
        snapshotCancellable = dataSource.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                self.refreshVisibleContent()
            }
    }
}
