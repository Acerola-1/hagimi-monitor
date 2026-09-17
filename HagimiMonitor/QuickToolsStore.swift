import Combine
import IOKit.pwr_mgt
import OSLog
import SwiftUI

/// 快捷功能:监控面板外的主动操作入口(键盘锁定/系统防休眠/不息屏)。
/// 与只读监控数据严格分离:状态由本 store 独立发布,浮层独立于面板
/// 每秒刷新,不引入面板重绘开销。
///
/// 键盘锁定双渠道同构:均由 KeyboardLockController 的事件 tap 拦截,
/// 差异仅在授权通道——Direct 为辅助功能(该权限同时服务媒体键接管),
/// App Store 为输入监控(沙盒内可用)。
@MainActor
final class QuickToolsStore: ObservableObject {
    static let shared = QuickToolsStore()

    /// 自动解锁时长的持久化键:设置页写入,本 store 启动时据此恢复一次。
    static let autoUnlockMinutesDefaultsKey = "settings.quickTools.keyboardLockAutoUnlockMinutes"
    /// 键盘锁定是否同时拦截外接键盘的持久化键:设置页写入,默认只拦截内置键盘。
    static let blocksExternalDefaultsKey = "settings.quickTools.keyboardLockBlocksExternal"

    /// 键盘锁定激活中:键盘事件被 tap 拦截,鼠标不受影响;解锁入口
    /// 为本功能开关(快捷键会被 tap 一并吞掉)。
    @Published private(set) var keyboardLocked = false
    /// 键盘锁定范围:默认只拦截内置键盘,依用户在设置中的偏好持久化。
    @Published private(set) var keyboardLockScope: KeyboardLockScope = .internalOnly
    /// 本轮锁定的自动解锁时长(分钟),取设置页的档位。
    @Published private(set) var keyboardLockAutoUnlockMinutes = KeyboardLockController.defaultAutoUnlockMinutes
    /// 键盘拓扑:已连接外接键盘名称与本机是否存在内置键盘。
    /// 未锁定时 controller 不持有 HID 监听,插拔回调不活跃,由调用方主动刷新。
    @Published private(set) var keyboardTopology = KeyboardLockController.KeyboardTopology()
    /// 本轮锁定的自动解锁截止时刻,未锁定为 nil。header 倒计时徽章
    /// 据此逐秒刷新,与 KeyboardLockController 的兜底计时器同源。
    @Published private(set) var keyboardLockAutoUnlockDate: Date?
    /// 键盘锁定权限未授予时的提示文案(当前渠道对应权限名的本地化),
    /// 已授权为 nil。浮层磁贴据此显示"需要什么授权"的小字;授权即隐、
    /// 撤销复现,与键盘锁定联动同拍发布。
    @Published private(set) var keyboardLockPermissionHint: String?

    /// 浮层磁贴的提示行文案:常态为 nil,只在"此刻会出问题"的状态下出现。
    /// 两种来源互斥——未授权时不可能处于已锁定态,故直接取先到者。
    var keyboardLockHint: String? {
        // 「仅内置」锁定中却没有外接键盘:内置键盘已被拦截,而机器上再没有
        // 别的输入源,用户会以为键盘坏了。
        if keyboardLocked, keyboardLockScope == .internalOnly, !hasExternalKeyboard {
            return String(localized: "quicktools.keyboard-lock.locked-without-external")
        }
        return keyboardLockPermissionHint
    }

    /// 系统防休眠激活中:阻止空闲引发的系统休眠(屏幕可正常熄灭;
    /// 合盖是否休眠由硬件/外接条件决定,断言不参与)。
    @Published private(set) var systemSleepPrevented = false
    /// 不息屏激活中:阻止空闲熄屏(连带阻止空闲休眠)。
    @Published private(set) var displayAwake = false

    var anyActive: Bool {
        if keyboardLocked { return true }
        return systemSleepPrevented || displayAwake
    }

    /// 单个工具是否处于激活状态。浮层过滤磁贴时对激活中的工具豁免:
    /// 用户隐藏了工具但该工具仍在运行(如键盘锁定),入口不能因此消失,
    /// 否则会失去唯一的关闭入口。
    func isActive(_ kind: QuickToolKind) -> Bool {
        switch kind {
        case .keyboardLock: keyboardLocked
        case .systemAwake: systemSleepPrevented
        case .displayAwake: displayAwake
        }
    }

    /// 工具浮层呈现器:浮层是面板的子窗口,生命周期必须长于
    /// MonitorPanelView(面板每秒重渲染会重建 @State),故挂在本单例上。
    lazy var popoverPresenter = QuickToolsPopoverPresenter { [weak self] in
        self?.isPopoverPresented = false
    }
    /// 浮层是否正在呈现(仅供面板入口按钮绘制打开态高亮)。
    @Published var isPopoverPresented = false

    private var displayAssertionID: IOPMAssertionID?
    private var systemAssertionID: IOPMAssertionID?
    private let keyboardLock = KeyboardLockController()
    private let keyboardLockPermission = AccessibilityPermissionService.shared
    /// 挂起标记:已表达上锁意图、等待授权通过或 tap 可建立;
    /// 挂起期间再次点击开关视为撤销意图。
    private var pendingKeyboardLock = false
    private var permissionCancellable: AnyCancellable?

    private init() {
        let storedAutoUnlock = UserDefaults.standard.object(forKey: Self.autoUnlockMinutesDefaultsKey) as? Int
        if let storedAutoUnlock, KeyboardLockController.autoUnlockMinuteOptions.contains(storedAutoUnlock) {
            keyboardLockAutoUnlockMinutes = storedAutoUnlock
        }
        let storedBlocksExternal = UserDefaults.standard.bool(forKey: Self.blocksExternalDefaultsKey)
        keyboardLockScope = storedBlocksExternal ? .all : .internalOnly

        keyboardLock.onAutoUnlock = { [weak self] in
            // controller 到点已自行 stop,此处只同步发布态(倒计时随之清空)。
            Task { @MainActor [weak self] in
                self?.setKeyboardLocked(false)
            }
        }
        keyboardLock.onExternalKeyboardDisconnected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.keyboardLocked && self.keyboardLockScope == .internalOnly {
                    self.keyboardLock.stop()
                    self.setKeyboardLocked(false)
                }
                self.refreshKeyboardTopology()
            }
        }
        keyboardLock.onExternalKeyboardsChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshKeyboardTopology()
            }
        }
        observeKeyboardLockPermission()
        refreshKeyboardTopology()
    }

    /// 已连接的外接键盘名称;空数组即没有外接键盘。
    var externalKeyboardNames: [String] { keyboardTopology.externalNames }
    var hasExternalKeyboard: Bool { !keyboardTopology.externalNames.isEmpty }
    var hasBuiltInKeyboard: Bool { keyboardTopology.hasBuiltIn }

    /// 刷新键盘拓扑。范围设为「仅内置」时,它决定锁定后还有没有可用输入,
    /// 因此设置页每次出现与每次落锁前都重新扫一次。
    func refreshKeyboardTopology() {
        keyboardTopology = KeyboardLockController.scanKeyboardTopology()
    }

    /// 切换锁定范围(设置页「外接键盘」子开关);锁定中则平滑热切换新范围。
    func setKeyboardLockScope(_ scope: KeyboardLockScope) {
        guard keyboardLockScope != scope else { return }
        keyboardLockScope = scope
        UserDefaults.standard.set(scope == .all, forKey: Self.blocksExternalDefaultsKey)
        if keyboardLocked {
            _ = keyboardLock.start(scope: scope, autoUnlockMinutes: keyboardLockAutoUnlockMinutes)
        }
    }

    /// 设置页改动的自动解锁时长。下一轮锁定生效:本轮锁定中改档位不重排
    /// 已有截止时刻,避免静默缩短正在生效的锁定。
    func setKeyboardLockAutoUnlockMinutes(_ minutes: Int) {
        guard KeyboardLockController.autoUnlockMinuteOptions.contains(minutes) else { return }
        keyboardLockAutoUnlockMinutes = minutes
    }

    /// 键盘锁定的权限联动:授权通过且处于挂起态时自动上锁;
    /// 权限被撤销时 tap 已失效,同步回未锁定。权限状态变化时同步
    /// 刷新磁贴下面的提示文案。
    private func observeKeyboardLockPermission() {
        permissionCancellable = keyboardLockPermission.$isTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                guard let self else { return }
                self.refreshPermissionHint()
                if trusted {
                    self.attemptPendingLock()
                } else if self.keyboardLocked {
                    self.keyboardLock.stop()
                    self.setKeyboardLocked(false)
                }
            }
    }

    /// 以授权状态刷新提示文案:未授权给出来源渠道的权限名文案,已授权置 nil。
    private func refreshPermissionHint() {
        keyboardLockPermissionHint = keyboardLockPermission.isTrusted
            ? nil
            : String(localized: keyboardLockPermission.permissionHintKey)
    }

    /// 浮层可见期间定期校准授权状态(App Store 渠道撤销无事件通知,只能轮询)。
    /// 内部走各渠道对应权限服务的 refresh,isTrusted 变化经
    /// observeKeyboardLockPermission 的 sink 联动落锁/解锁与提示行。
    func refreshKeyboardLockPermission() {
        keyboardLockPermission.refresh()
    }

    /// 落锁/解锁后同步锁定态与倒计时截止时刻:两个 @Published 同拍
    /// 发布,header 徽章不会出现「已解锁还挂着倒计时」的中间帧。
    private func setKeyboardLocked(_ locked: Bool) {
        keyboardLocked = locked
        if !locked {
            let storedBlocksExternal = UserDefaults.standard.bool(forKey: Self.blocksExternalDefaultsKey)
            keyboardLockScope = storedBlocksExternal ? .all : .internalOnly
        }
        keyboardLockAutoUnlockDate = keyboardLock.autoUnlockDeadline
    }

    /// 切换键盘锁定。未授权时触发系统授权引导,授权通过后自动上锁;
    /// 挂起中的再次点击撤销上锁意图。
    func toggleKeyboardLock() {
        if keyboardLocked {
            keyboardLock.stop()
            setKeyboardLocked(false)
            return
        }
        guard keyboardLockPermission.isTrusted else {
            pendingKeyboardLock = true
            keyboardLockPermission.request(titleKey: "quicktools.permission.accessibility.guide-title")
            return
        }
        if pendingKeyboardLock {
            cancelPendingLock()
            return
        }
        pendingKeyboardLock = true
        attemptPendingLock()
    }

    /// 尝试落锁:tap 建立成功则点亮锁定态;失败直接放弃本次意图。
    private func attemptPendingLock() {
        guard pendingKeyboardLock, !keyboardLocked else { return }
        refreshKeyboardTopology()
        if keyboardLock.start(scope: keyboardLockScope, autoUnlockMinutes: keyboardLockAutoUnlockMinutes) {
            pendingKeyboardLock = false
            setKeyboardLocked(true)
        } else {
            pendingKeyboardLock = false
        }
    }

    /// 撤销挂起的上锁意图并关闭权限引导浮窗。
    private func cancelPendingLock() {
        pendingKeyboardLock = false
        AccessibilityPermissionGuide.shared.dismiss()
    }

    // MARK: - 系统防休眠

    /// PreventUserIdleSystemSleep 断言阻止空闲引发的系统休眠;
    /// App Store 沙盒内可用,与 caffeinate -i 同型。
    func toggleSystemSleepPrevention() {
        if systemSleepPrevented {
            releaseAssertion(&systemAssertionID)
            systemSleepPrevented = false
            return
        }
        systemAssertionID = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            reason: "HagimiMonitor: prevent idle system sleep"
        )
        systemSleepPrevented = systemAssertionID != nil
    }

    // MARK: - 不息屏

    func toggleDisplayAwake() {
        if displayAwake {
            releaseAssertion(&displayAssertionID)
            displayAwake = false
            return
        }
        displayAssertionID = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
            reason: "HagimiMonitor: keep display awake"
        )
        displayAwake = displayAssertionID != nil
    }

    /// 退出前清理:释放断言、解除键盘锁定。进程终止本身也会回收,
    /// 此处保证 stop 语义完整(如测试或热重启场景)。
    func stop() {
        if keyboardLocked {
            keyboardLock.stop()
            setKeyboardLocked(false)
        }
        cancelPendingLock()
        releaseAssertion(&displayAssertionID)
        releaseAssertion(&systemAssertionID)
        displayAwake = false
        systemSleepPrevented = false
        popoverPresenter.dismiss()
    }

    deinit {
        if let id = displayAssertionID { IOPMAssertionRelease(id) }
        if let id = systemAssertionID { IOPMAssertionRelease(id) }
    }

    // MARK: - 电源断言

    private func createAssertion(type: String, reason: String) -> IOPMAssertionID? {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, .init(kIOPMAssertionLevelOn), reason as CFString, &assertionID)
        guard result == kIOReturnSuccess else {
            AppLogger.ui.error("QuickTools: assertion create failed \(result)")
            return nil
        }
        return assertionID
    }

    private func releaseAssertion(_ id: inout IOPMAssertionID?) {
        guard let current = id else { return }
        IOPMAssertionRelease(current)
        id = nil
    }
}
