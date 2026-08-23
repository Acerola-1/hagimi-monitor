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

    /// 键盘锁定激活中:键盘事件被 tap 拦截,鼠标不受影响;解锁入口
    /// 为本功能开关(快捷键会被 tap 一并吞掉)。
    @Published private(set) var keyboardLocked = false
    /// 系统防休眠激活中:阻止空闲引发的系统休眠(屏幕可正常熄灭;
    /// 合盖是否休眠由硬件/外接条件决定,断言不参与)。
    @Published private(set) var systemSleepPrevented = false
    /// 不息屏激活中:阻止空闲熄屏(连带阻止空闲休眠)。
    @Published private(set) var displayAwake = false

    var anyActive: Bool {
        if keyboardLocked { return true }
        return systemSleepPrevented || displayAwake
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
    #if DIRECT_DISTRIBUTION
    private typealias KeyboardLockPermission = AccessibilityPermissionService
    #else
    private typealias KeyboardLockPermission = InputMonitoringPermissionService
    #endif
    private let keyboardLock = KeyboardLockController()
    private let keyboardLockPermission = KeyboardLockPermission.shared
    /// 挂起标记:已表达上锁意图、等待授权通过或 tap 可建立;
    /// 挂起期间再次点击开关视为撤销意图。
    private var pendingKeyboardLock = false
    private var permissionCancellable: AnyCancellable?
    #if !DIRECT_DISTRIBUTION
    /// 授权通过后事件 tap 侧信任缓存存在传播延迟(实测约 40 秒),
    /// 期间 tapCreate 失败,挂起态按固定间隔重试直到成功。
    private var tapRetryTimer: DispatchSourceTimer?
    private static let tapRetryInterval: TimeInterval = 5
    #endif

    private init() {
        keyboardLock.onAutoUnlock = { [weak self] in
            self?.keyboardLocked = false
        }
        observeKeyboardLockPermission()
    }

    /// 键盘锁定的权限联动:授权通过且处于挂起态时自动上锁;
    /// 权限被撤销时 tap 已失效,同步回未锁定。
    private func observeKeyboardLockPermission() {
        permissionCancellable = keyboardLockPermission.$isTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    self.attemptPendingLock()
                } else if self.keyboardLocked {
                    self.keyboardLock.stop()
                    self.keyboardLocked = false
                }
            }
    }

    /// 切换键盘锁定。未授权时触发系统授权引导,授权通过后自动上锁;
    /// 挂起中的再次点击撤销上锁意图。
    func toggleKeyboardLock() {
        if keyboardLocked {
            keyboardLock.stop()
            keyboardLocked = false
            return
        }
        if pendingKeyboardLock {
            cancelPendingLock()
            return
        }
        pendingKeyboardLock = true
        guard keyboardLockPermission.isTrusted else {
            keyboardLockPermission.request()
            return
        }
        attemptPendingLock()
    }

    /// 尝试落锁:tap 建立成功则点亮锁定态;失败时 App Store 渠道
    /// 多处于授权后的信任缓存传播窗口,进入定时重试,Direct 渠道
    /// 授权即生效,失败直接放弃本次意图。
    private func attemptPendingLock() {
        guard pendingKeyboardLock, !keyboardLocked else { return }
        if keyboardLock.start() {
            pendingKeyboardLock = false
            keyboardLocked = true
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

    /// 撤销挂起的上锁意图。
    private func cancelPendingLock() {
        pendingKeyboardLock = false
        #if !DIRECT_DISTRIBUTION
        stopTapRetry()
        #endif
    }

    #if !DIRECT_DISTRIBUTION
    /// 传播窗口内按固定间隔重试建 tap,直到成功或意图被撤销。
    private func startTapRetry() {
        guard tapRetryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.tapRetryInterval, repeating: Self.tapRetryInterval)
        timer.setEventHandler { [weak self] in
            self?.attemptPendingLock()
        }
        tapRetryTimer = timer
        timer.resume()
    }

    private func stopTapRetry() {
        tapRetryTimer?.cancel()
        tapRetryTimer = nil
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
            keyboardLocked = false
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
