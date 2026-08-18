import Combine
import IOKit.pwr_mgt
import OSLog
import SwiftUI

/// 快捷功能:监控面板外的主动操作入口(键盘锁定/系统防休眠/不息屏)。
/// 与只读监控数据严格分离:状态由本 store 独立发布,浮层独立于面板
/// 每秒刷新,不引入面板重绘开销。
///
/// 键盘锁定双渠道实现:Direct 为辅助功能权限下的事件 tap 拦截,
/// App Store 为全屏遮罩(见 KeyboardLockShield),状态语义一致。
@MainActor
final class QuickToolsStore: ObservableObject {
    static let shared = QuickToolsStore()

    /// 键盘锁定激活中(Direct:键盘事件被拦截,鼠标不受影响;
    /// App Store:全屏遮罩接管键盘与点击)。
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
    private let keyboardLock = KeyboardLockController()
    /// 已发起授权、等待授权通过后自动上锁的挂起标记。
    private var pendingKeyboardLock = false
    private var permissionCancellable: AnyCancellable?
    #else
    private let keyboardShield = KeyboardLockShieldController()
    #endif

    private init() {
        #if DIRECT_DISTRIBUTION
        configureKeyboardLock()
        #else
        keyboardShield.onAutoUnlock = { [weak self] in
            self?.keyboardLocked = false
        }
        keyboardShield.onUnlock = { [weak self] in
            self?.toggleKeyboardLock()
        }
        #endif
    }

    #if DIRECT_DISTRIBUTION
    /// 键盘锁定的权限联动:授权通过后若处于挂起态则自动上锁;
    /// 权限被撤销时 tap 已失效,同步回未锁定。
    private func configureKeyboardLock() {
        keyboardLock.onAutoUnlock = { [weak self] in
            self?.keyboardLocked = false
        }
        permissionCancellable = AccessibilityPermissionService.shared.$isTrusted
            .receive(on: RunLoop.main)
            .sink { [weak self] trusted in
                guard let self else { return }
                if trusted {
                    if self.pendingKeyboardLock && !self.keyboardLocked {
                        self.pendingKeyboardLock = false
                        self.keyboardLocked = self.keyboardLock.start()
                    }
                } else if self.keyboardLocked {
                    self.keyboardLock.stop()
                    self.keyboardLocked = false
                }
            }
    }
    #endif

    /// 切换键盘锁定。Direct 渠道未授权时触发系统授权引导(打开系统
    /// 设置 + 轮询),授权通过后自动上锁;App Store 渠道直接铺遮罩。
    func toggleKeyboardLock() {
        if keyboardLocked {
            #if DIRECT_DISTRIBUTION
            keyboardLock.stop()
            #else
            keyboardShield.dismiss()
            #endif
            keyboardLocked = false
            return
        }
        #if DIRECT_DISTRIBUTION
        guard AccessibilityPermissionService.shared.isTrusted else {
            pendingKeyboardLock = true
            AccessibilityPermissionService.shared.request()
            return
        }
        keyboardLocked = keyboardLock.start()
        #else
        // 遮罩会盖过菜单栏,浮层失去入口,先收起避免残留。
        popoverPresenter.dismiss()
        keyboardLocked = keyboardShield.present()
        #endif
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
            #if DIRECT_DISTRIBUTION
            keyboardLock.stop()
            #else
            keyboardShield.dismiss()
            #endif
            keyboardLocked = false
        }
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
