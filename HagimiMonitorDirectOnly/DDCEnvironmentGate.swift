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
nonisolated final class DDCEnvironmentGate {
    static let shared = DDCEnvironmentGate()

    private let lock = NSLock()
    private let runtime: DDCGateRuntime

    private var changeHandlers: [UUID: () -> Void] = [:]

    /// 生产环境用默认时长并注册系统观察者。测试可注入更短时长并跳过系统注册,
    /// 通过 `handleWillSleep()`/`handleDidWake()`/`handleReconfigure(flags:)` 手动触发。
    init(
        wakeSuppressSeconds: TimeInterval = 3,
        reconfigureSettleSeconds: TimeInterval = 1,
        reconfigureSafetySeconds: TimeInterval = 5,
        registerSystemObservers: Bool = true,
        clock: MonotonicClock = DispatchMonotonicClock()
    ) {
        self.runtime = DDCGateRuntime(
            clock: clock,
            wakeSettle: wakeSuppressSeconds,
            reconfigureSettle: reconfigureSettleSeconds,
            reconfigureSafety: reconfigureSafetySeconds
        )
        _ = runtime.addRecoveryHandler { [weak self] in
            DispatchQueue.main.async {
                self?.fireChangeHandlers()
            }
        }
        guard registerSystemObservers else { return }
        let center = NSWorkspace.shared.notificationCenter
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
    func addChangeHandler(_ handler: @escaping () -> Void) -> UUID {
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

    // MARK: - Event handlers

    @objc func handleWillSleep() {
        runtime.systemSleepStarted()
    }

    @objc func handleDidWake() {
        runtime.systemWakeStarted()
    }

    @objc func handleDisplayWillSleep() {
        runtime.displaySleepStarted()
    }

    @objc func handleDisplayDidWake() {
        runtime.displayWakeStarted()
    }

    func handleReconfigure(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            runtime.reconfigureStarted()
        } else {
            runtime.reconfigureCompleted()
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
    private nonisolated static let cgCallback: CGDisplayReconfigurationCallBack = { _, flags, _ in
        DDCEnvironmentGate.shared.handleReconfigure(flags: flags)
    }
}
