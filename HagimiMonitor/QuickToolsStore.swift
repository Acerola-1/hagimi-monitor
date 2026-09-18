import Combine
import IOKit.pwr_mgt
import OSLog
import SwiftUI

/// 快捷功能:监控面板外的主动操作入口(键盘锁定/系统防休眠/不息屏)。
/// 与只读监控数据严格分离:状态由本 store 独立发布,浮层独立于面板
/// 每秒刷新,不引入面板重绘开销。
///
/// 键盘锁定的授权要求:辅助功能用于创建事件 tap,输入监控用于打开
/// 键盘类 HID 受限设备、接收按键事件与 HID 输入值。Direct 双授权,
/// App Store 沙盒仅有输入监控通道;媒体键接管仍只用辅助功能。
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
    /// 锁定中 HID 监听未拿到键盘设备(典型为缺输入监控或授权后未重建):
    /// 来源归因无从建立,「仅内置」会退化为全拦。浮层磁贴据此提示,
    /// 而不是让用户面对"键盘没反应"却毫无解释。
    @Published private(set) var keyboardLockEvidenceDegraded = false

    /// 浮层磁贴的提示行文案:常态为 nil,只在"此刻会出问题"的状态下出现。
    var keyboardLockHint: String? {
        // 来源归因不可用时优先提示:此时「有没有外接键盘」的判断也不可信,
        // 而且所有按键都会被当作内置吞掉。
        if keyboardLocked, keyboardLockScope == .internalOnly, keyboardLockEvidenceDegraded {
            return String(localized: "quicktools.keyboard-lock.evidence-unavailable")
        }
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
    /// 辅助功能授权:Direct 渠道建事件 tap 所需;App Store 沙盒不依赖它。
    private let keyboardLockPermission = AccessibilityPermissionService.shared
    /// 输入监控授权:打开键盘类 HID 受限设备、接收按键事件与 HID 输入值,
    /// 双渠道都需要。
    private let inputMonitoringPermission = InputMonitoringPermissionService.shared
    /// 挂起标记:已表达上锁意图、等待授权通过或 tap 可建立;
    /// 挂起期间再次点击开关视为撤销意图。
    private var pendingKeyboardLock = false
    private var permissionCancellable: AnyCancellable?
    #if !DIRECT_DISTRIBUTION
    /// 授权通过后事件 tap 侧信任缓存存在传播延迟(实测约 40 秒),
    /// 期间 tapCreate 失败,挂起态按固定间隔重试直到成功或超时。
    private var tapRetryTimer: DispatchSourceTimer?
    private var tapRetryAttempts = 0
    private static let tapRetryInterval: TimeInterval = 5
    private static let maxTapRetryAttempts = 12
    #endif

    /// 键盘锁需要的权限是否齐备:Direct 为辅助功能加输入监控,
    /// App Store 沙盒仅有输入监控通道。
    private var keyboardLockPermissionsReady: Bool {
        #if DIRECT_DISTRIBUTION
        return keyboardLockPermission.isTrusted && inputMonitoringPermission.isTrusted
        #else
        return inputMonitoringPermission.isTrusted
        #endif
    }

    /// 权限有缺失时优先指向缺失的那一项;齐备返回 nil。
    private var missingPermissionHintKey: String.LocalizationValue? {
        #if DIRECT_DISTRIBUTION
        if !keyboardLockPermission.isTrusted { return keyboardLockPermission.permissionHintKey }
        #endif
        if !inputMonitoringPermission.isTrusted { return inputMonitoringPermission.permissionHintKey }
        return nil
    }

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

    /// 已连接的外接键盘名称;空数组即没有外接键盘(浮层「仅内置」锁定中的
    /// 防呆提示据此判断还有没有可用输入)。
    var hasExternalKeyboard: Bool { !keyboardTopology.externalNames.isEmpty }

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
            refreshKeyboardLockEvidenceState()
        }
    }

    /// 设置页改动的自动解锁时长。下一轮锁定生效:本轮锁定中改档位不重排
    /// 已有截止时刻,避免静默缩短正在生效的锁定。
    func setKeyboardLockAutoUnlockMinutes(_ minutes: Int) {
        guard KeyboardLockController.autoUnlockMinuteOptions.contains(minutes) else { return }
        keyboardLockAutoUnlockMinutes = minutes
    }

    /// 键盘锁定的权限联动:授权齐备且处于挂起态时自动上锁;权限被撤销时
    /// tap 已失效,同步回未锁定;锁定中补授权时重建 HID 监听——受限设备
    /// 打开失败不会自动重试,重建后来源归因立即生效,无需重启应用。
    private func observeKeyboardLockPermission() {
        let permissionChanges: AnyPublisher<Void, Never>
        #if DIRECT_DISTRIBUTION
        permissionChanges = keyboardLockPermission.$isTrusted
            .combineLatest(inputMonitoringPermission.$isTrusted)
            .map { _ in () }
            .eraseToAnyPublisher()
        #else
        permissionChanges = inputMonitoringPermission.$isTrusted
            .map { _ in () }
            .eraseToAnyPublisher()
        #endif
        permissionCancellable = permissionChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.refreshPermissionHint()
                if self.keyboardLockPermissionsReady {
                    self.refreshKeyboardTopology()
                    if self.keyboardLocked {
                        self.keyboardLock.refreshHIDMonitoring()
                        self.refreshKeyboardLockEvidenceState()
                    } else {
                        self.attemptPendingLock()
                    }
                } else {
                    #if !DIRECT_DISTRIBUTION
                    self.stopTapRetry()
                    #endif
                    // 双授权渠道:补齐一项后若仍有缺失且上锁意图挂起,
                    // 自动衔接下一项的引导,用户不必再点一次开关。
                    if self.pendingKeyboardLock {
                        self.requestMissingKeyboardLockPermission()
                    }
                    if self.keyboardLocked {
                        self.keyboardLock.stop()
                        self.setKeyboardLocked(false)
                    }
                }
            }
    }

    /// 以授权状态刷新提示文案:有缺失项时给出对应权限名文案,齐备置 nil。
    private func refreshPermissionHint() {
        keyboardLockPermissionHint = missingPermissionHintKey.map { String(localized: $0) }
    }

    /// 浮层可见期间定期校准授权状态(撤销无事件通知,只能轮询)。
    /// 内部走各权限服务的 refresh,isTrusted 变化经
    /// observeKeyboardLockPermission 的 sink 联动落锁/解锁与提示行。
    func refreshKeyboardLockPermission() {
        keyboardLockPermission.refresh()
        inputMonitoringPermission.refresh()
    }

    /// 落锁/解锁后同步锁定态与倒计时截止时刻:两个 @Published 同拍
    /// 发布,header 徽章不会出现「已解锁还挂着倒计时」的中间帧。
    private func setKeyboardLocked(_ locked: Bool) {
        keyboardLocked = locked
        if !locked {
            let storedBlocksExternal = UserDefaults.standard.bool(forKey: Self.blocksExternalDefaultsKey)
            keyboardLockScope = storedBlocksExternal ? .all : .internalOnly
            keyboardLockEvidenceDegraded = false
        } else {
            refreshKeyboardLockEvidenceState()
        }
        keyboardLockAutoUnlockDate = keyboardLock.autoUnlockDeadline
    }

    /// 以 controller 的 HID 监听状态刷新降级标记:「仅内置」范围才依赖
    /// 来源区分能力,「全部拦截」不需要 HID 证据。
    private func refreshKeyboardLockEvidenceState() {
        keyboardLockEvidenceDegraded = keyboardLocked
            && keyboardLockScope == .internalOnly
            && !keyboardLock.hidMonitoringHealthy
    }

    /// 切换键盘锁定。权限不齐时触发授权引导,齐备后自动上锁;
    /// 挂起中的再次点击撤销上锁意图。
    func toggleKeyboardLock() {
        if keyboardLocked {
            keyboardLock.stop()
            setKeyboardLocked(false)
            return
        }
        // 授权撤销没有事件通知(输入监控只能轮询,且只有浮层可见期间在轮询),
        // isTrusted 可能停留在陈旧的已授权态。点击落锁是用户主动操作时刻,
        // 先同步校准一次授权状态再决定走引导还是落锁——否则撤销后点击会被
        // 陈旧判定吞进静默落锁流程,不弹引导、磁贴无任何反馈。
        refreshKeyboardLockPermission()
        guard keyboardLockPermissionsReady else {
            pendingKeyboardLock = true
            requestMissingKeyboardLockPermission()
            return
        }
        if pendingKeyboardLock {
            cancelPendingLock()
            return
        }
        pendingKeyboardLock = true
        attemptPendingLock()
    }

    /// 引导补齐缺失的权限项:Direct 先辅助功能后输入监控,App Store 走输入监控。
    private func requestMissingKeyboardLockPermission() {
        #if DIRECT_DISTRIBUTION
        if !keyboardLockPermission.isTrusted {
            keyboardLockPermission.request(
                titleKey: "quicktools.permission.accessibility.guide-title",
                subtitleKey: "quicktools.permission.accessibility.guide-subtitle"
            )
            return
        }
        #endif
        inputMonitoringPermission.request()
    }

    /// 尝试落锁:tap 建立成功则点亮锁定态;失败时在沙盒下启动重试,
    /// 解决刚授权后系统的信任缓存传播窗口延迟。
    private func attemptPendingLock() {
        guard pendingKeyboardLock, !keyboardLocked else { return }
        refreshKeyboardTopology()
        if keyboardLock.start(scope: keyboardLockScope, autoUnlockMinutes: keyboardLockAutoUnlockMinutes) {
            pendingKeyboardLock = false
            setKeyboardLocked(true)
            #if !DIRECT_DISTRIBUTION
            stopTapRetry()
            #endif
        } else {
            #if !DIRECT_DISTRIBUTION
            startTapRetry()
            #else
            pendingKeyboardLock = false
            #endif
        }
    }

    /// 撤销挂起的上锁意图并关闭权限引导浮窗。
    private func cancelPendingLock() {
        pendingKeyboardLock = false
        AccessibilityPermissionGuide.shared.dismiss()
        #if !DIRECT_DISTRIBUTION
        stopTapRetry()
        #endif
    }

    #if !DIRECT_DISTRIBUTION
    /// 传播窗口内按固定间隔重试建 tap,直到成功、超时或意图被撤销。
    private func startTapRetry() {
        guard tapRetryTimer == nil else { return }
        tapRetryAttempts = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.tapRetryInterval, repeating: Self.tapRetryInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.tapRetryAttempts += 1
            if self.tapRetryAttempts >= Self.maxTapRetryAttempts {
                self.stopTapRetry()
                self.pendingKeyboardLock = false
                return
            }
            self.attemptPendingLock()
        }
        tapRetryTimer = timer
        timer.resume()
    }

    private func stopTapRetry() {
        tapRetryTimer?.cancel()
        tapRetryTimer = nil
        tapRetryAttempts = 0
    }
    #endif

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
        #if !DIRECT_DISTRIBUTION
        tapRetryTimer?.cancel()
        #endif
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
