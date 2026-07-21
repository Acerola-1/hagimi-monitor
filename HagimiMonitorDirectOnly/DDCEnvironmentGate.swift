import AppKit
import CoreGraphics
import Foundation

#if !arch(arm64)
#error("Display DDC control is Apple Silicon only. Do not compile this Direct-only module for Intel Mac.")
#endif

/// DDC 系统状态门禁:睡眠/唤醒/显示器重配置窗口内,IOAVService 内核调用极易长时间
/// 阻塞或返回垃圾数据。与其在事后用全局熔断补救级联失败,不如在这些危险窗口内**直接
/// 不发任何 DDC 报文**,从源头掐掉 hang。这是本模块可靠性的第一道也是最重要的一道防线。
///
/// 同时作为显示器/电源事件的**唯一信号源**:统一注册 CG 重配置回调与睡眠/唤醒通知,
/// 既维护 `isSuppressed`,又在合适时机(抑制窗口结束后)通知订阅者刷新,
/// 避免多处重复注册两套 CG 回调。
///
/// 线程安全:状态由 NSLock 保护,`isSuppressed` 可在任意 DDC 后台队列安全读取。
nonisolated final class DDCEnvironmentGate {
    static let shared = DDCEnvironmentGate()

    /// 唤醒后继续抑制的时长。部分显示器唤醒后需要数秒才恢复 DDC 响应。
    private let wakeSuppressSeconds: TimeInterval
    /// 重配置完成后的额外沉降时长,等待 DCP 稳定。
    private let reconfigureSettleSeconds: TimeInterval
    /// begin 之后若迟迟收不到完成回调的安全兜底抑制上限,避免永久卡在抑制态。
    private let reconfigureSafetySeconds: TimeInterval

    private let lock = NSLock()
    private var asleep = false
    private var suppressedUntil: Date?

    private var changeHandlers: [UUID: () -> Void] = [:]
    private var changeFireWorkItem: DispatchWorkItem?

    /// 生产环境用默认时长并注册系统观察者。测试可注入更短时长并跳过系统注册,
    /// 通过 `handleWillSleep()`/`handleDidWake()`/`handleReconfigure(flags:)` 手动触发。
    init(
        wakeSuppressSeconds: TimeInterval = 3,
        reconfigureSettleSeconds: TimeInterval = 1,
        reconfigureSafetySeconds: TimeInterval = 5,
        registerSystemObservers: Bool = true
    ) {
        self.wakeSuppressSeconds = wakeSuppressSeconds
        self.reconfigureSettleSeconds = reconfigureSettleSeconds
        self.reconfigureSafetySeconds = reconfigureSafetySeconds
        guard registerSystemObservers else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        CGDisplayRegisterReconfigurationCallback(Self.cgCallback, nil)
    }

    // MARK: - Suppression state

    /// 当前是否应抑制所有 DDC I/O。DDC 读写/探测入口据此直接跳过。
    /// 睡眠是持续状态(直到 didWake 清除);唤醒/重配置一律折算为**有时限**的
    /// `suppressedUntil`——即使某个完成回调丢失,也只会抑制到该时刻为止,
    /// 绝不永久卡死(重配置 begin 用 safety 时长兜底,收到完成回调再收敛到 settle)。
    var isSuppressed: Bool {
        lock.lock(); defer { lock.unlock() }
        if asleep {
            return true
        }
        if let until = suppressedUntil {
            if Date() < until {
                return true
            }
        }
        return false
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
        lock.lock()
        asleep = true
        lock.unlock()
    }

    @objc func handleDidWake() {
        lock.lock()
        asleep = false
        suppressedUntil = Date().addingTimeInterval(wakeSuppressSeconds)
        lock.unlock()
        // 抑制窗口结束后再刷新,确保探测读发生在总线就绪之后。
        scheduleChangeFire(after: wakeSuppressSeconds + 0.3)
    }

    func handleReconfigure(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            // begin:抑制到 safety 时刻为止。这是纯时限抑制——即使完成回调始终不来,
            // 最长也只抑制 reconfigureSafetySeconds,绝不永久卡死。
            lock.lock()
            suppressedUntil = Date().addingTimeInterval(reconfigureSafetySeconds)
            lock.unlock()
            return
        }

        // 某台显示器的重配置完成回调:收敛到较短的 settle 沉降窗口,等待 DCP 稳定。
        lock.lock()
        suppressedUntil = Date().addingTimeInterval(reconfigureSettleSeconds)
        lock.unlock()

        let structural = flags.contains(.addFlag)
            || flags.contains(.removeFlag)
            || flags.contains(.enabledFlag)
            || flags.contains(.disabledFlag)
        if structural {
            scheduleChangeFire(after: reconfigureSettleSeconds + 0.2)
        }
    }

    // MARK: - Debounced change firing

    private func scheduleChangeFire(after delay: TimeInterval) {
        lock.lock()
        changeFireWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.fireChangeHandlers()
        }
        changeFireWorkItem = item
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func fireChangeHandlers() {
        lock.lock()
        let handlers = Array(changeHandlers.values)
        changeFireWorkItem = nil
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
