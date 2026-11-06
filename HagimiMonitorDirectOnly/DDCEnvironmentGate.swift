import AppKit
import CoreGraphics
import Foundation

#if !arch(arm64)
#error("Display DDC control is Apple Silicon only. Do not compile this Direct-only module for Intel Mac.")
#endif

/// DDC 系统状态门禁:睡眠/唤醒/显示器重配置窗口内,IOAVService 内核调用极易长时间
/// 阻塞或返回垃圾数据。危险窗口内直接不发 DDC 报文,从源头隔离这类调用风险。
///
/// 同时作为显示器/电源事件的**唯一信号源**:统一注册 CG 重配置回调与睡眠/唤醒通知,
/// 既维护 `isSuppressed`,又在合适时机(抑制窗口结束后)通知订阅者刷新,
/// 避免多处重复注册两套 CG 回调。
///
/// 内部状态由 `GateStateModel` 承载:独立维护系统睡眠、屏幕睡眠、唤醒期限与重配置
/// 期限,重配置完成只缩短自身期限,绝不缩短唤醒抑制;任一期限到期后重读当前状态,
/// 后续睡眠状态不会被过期的定时任务解除。
///
/// 线程安全:状态由 NSLock 保护,`isSuppressed` 可在任意 DDC 后台队列安全读取。
///
/// 继承 NSObject 是硬性要求:selector 式 NSWorkspace 通知派发走 objc_msgSend,
/// 纯 Swift 类不是合法的 Objective-C 对象,睡眠/唤醒通知触发时会派发失败。
nonisolated final class DDCEnvironmentGate: NSObject, @unchecked Sendable {
    static let shared = DDCEnvironmentGate()

    private let lock = NSLock()
    private let runtime: DDCGateRuntime

    private var changeHandlers: [UUID: @Sendable () -> Void] = [:]
    private var topologyHandlers: [UUID: @Sendable (CGDirectDisplayID?, CGDisplayChangeSummaryFlags) -> Void] = [:]
    private var systemSleeping = false
    private var shuttingDown = false
    var isShuttingDown: Bool { lock.withLock { shuttingDown } }

    /// 拓扑救援只避让系统睡眠，不受单个显示器睡眠的 DDC 门禁阻断。
    var isSystemSleeping: Bool { lock.withLock { systemSleeping } }

    /// 生产环境用默认时长并注册系统观察者。测试可注入更短时长并跳过系统注册,
    /// 通过 `handleWillSleep()`/`handleDidWake()`/`handleReconfigure(flags:)` 手动触发。
    init(
        wakeSuppressSeconds: TimeInterval = 3,
        reconfigureSettleSeconds: TimeInterval = 1,
        reconfigureSafetySeconds: TimeInterval = 5,
        registerSystemObservers: Bool = true,
        clock: MonotonicClock = DispatchMonotonicClock()
    ) {
        // 先初始化自身存储,再 super.init(),之后才能把 self 交给通知中心。
        self.runtime = DDCGateRuntime(
            clock: clock,
            wakeSettle: wakeSuppressSeconds,
            reconfigureSettle: reconfigureSettleSeconds,
            reconfigureSafety: reconfigureSafetySeconds
        )
        super.init()
        _ = runtime.addRecoveryHandler { [weak self] in
            DispatchQueue.main.async {
                self?.fireChangeHandlers()
            }
        }
        guard registerSystemObservers else { return }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleWillPowerOff), name: NSWorkspace.willPowerOffNotification, object: nil)
        center.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleDisplayWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleDisplayDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        CGDisplayRegisterReconfigurationCallback(Self.cgCallback, nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenParameters),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - Suppression state

    /// 当前是否应抑制所有 DDC I/O。DDC 读写/探测入口据此直接跳过。
    /// 任一原因生效即抑制:系统睡眠/屏幕睡眠为持续态(直到对应唤醒清除);
    /// 唤醒/重配置折算为有时限的期限——即使某个完成回调丢失,也只会抑制到该
    /// 时刻为止,绝不永久卡死。
    var isSuppressed: Bool {
        runtime.isSuppressed
    }

    // MARK: - Change subscription

    /// 注册"显示器/电源状态发生实质变化、应重新检测"的回调。回调在主线程调用,
    /// 且经过抑制窗口对齐——只在总线大概率就绪后才触发,避免刚唤醒就读到空值。
    func addChangeHandler(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        changeHandlers[token] = handler
        lock.unlock()
        return token
    }

    func removeChangeHandler(_ token: UUID) {
        lock.lock()
        changeHandlers.removeValue(forKey: token)
        lock.unlock()
    }

    /// 连接救援不能等 DDC 门禁解除：拔屏可能同时进入持续的显示器睡眠状态。
    func addTopologyHandler(_ handler: @escaping @Sendable (CGDirectDisplayID?, CGDisplayChangeSummaryFlags) -> Void) -> UUID {
        let token = UUID()
        lock.withLock { topologyHandlers[token] = handler }
        return token
    }

    func removeTopologyHandler(_ token: UUID) { _ = lock.withLock { topologyHandlers.removeValue(forKey: token) } }

    private func fireTopologyHandlers(displayID: CGDirectDisplayID? = nil, flags: CGDisplayChangeSummaryFlags = []) {
        let handlers = lock.withLock { Array(topologyHandlers.values) }
        for handler in handlers { handler(displayID, flags) }
    }

    // MARK: - Event handlers

    @objc func handleWillSleep() {
        lock.withLock { systemSleeping = true }
        runtime.systemSleepStarted()
    }

    @objc func handleWillPowerOff() { lock.withLock { shuttingDown = true } }

    @objc func handleDidWake() {
        lock.withLock { systemSleeping = false }
        runtime.systemWakeStarted()
        fireTopologyHandlers()
    }

    @objc func handleDisplayWillSleep() {
        runtime.displaySleepStarted()
        fireTopologyHandlers()
    }

    @objc func handleDisplayDidWake() {
        runtime.displayWakeStarted()
        fireTopologyHandlers()
    }

    @objc private func handleScreenParameters() { fireTopologyHandlers() }

    func handleReconfigure(displayID: CGDirectDisplayID? = nil, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            runtime.reconfigureStarted()
        } else {
            runtime.reconfigureCompleted()
            fireTopologyHandlers(displayID: displayID, flags: flags)
        }
    }

    // MARK: - Change firing

    private func fireChangeHandlers() {
        lock.lock()
        let handlers = Array(changeHandlers.values)
        lock.unlock()
        for handler in handlers {
            handler()
        }
    }

    // MARK: - CG callback

    // C 函数指针不依赖实例上下文;单例在回调触发时必已完成初始化。
    private nonisolated static let cgCallback: CGDisplayReconfigurationCallBack = { displayID, flags, _ in
        DDCEnvironmentGate.shared.handleReconfigure(displayID: displayID, flags: flags)
    }
}
