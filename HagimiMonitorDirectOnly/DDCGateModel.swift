import Foundation

/// 门禁纯状态模型(D4):以独立原因 + 截止时间解算抑制,
/// 注入单调时钟使其可被虚拟时钟测试。
///
/// 独立维护四类原因:systemAsleep(持续态)、displayAsleep(屏幕睡眠持续态)、
/// wakeUntil(唤醒沉降时限)、reconfigureUntil(重配置沉降时限)。
/// 总抑制 = 任一原因生效。重配置完成可以缩短**自身** begin safety 期限,
/// 但不能缩短唤醒期限——两种截止时间互不覆盖。
nonisolated struct GateStateModel {
    private var systemAsleep = false
    private var displayAsleep = false
    private var wakeUntil: MonotonicInstant?
    private var reconfigureUntil: MonotonicInstant?

    /// 当前时刻是否处于抑制。
    func isSuppressed(at now: MonotonicInstant) -> Bool {
        if systemAsleep || displayAsleep {
            return true
        }
        if let until = wakeUntil, now < until {
            return true
        }
        if let until = reconfigureUntil, now < until {
            return true
        }
        return false
    }

    /// 下一个自动解除时刻(无持续态且有未来期限时才有意义)。
    /// 到期后调用方必须重读当前状态(可能已被新的睡眠重新抑制)。
    func nextDeadline() -> MonotonicInstant? {
        let candidates = [wakeUntil, reconfigureUntil].compactMap { $0 }
        return candidates.min()
    }

    // MARK: 状态转移

    mutating func systemSleepStarted() {
        systemAsleep = true
    }

    /// 唤醒:清除持续态,进入唤醒沉降窗口。返回是否产生 true→false 恢复事件
    /// 由调用方统一判定(见 recoveryEvent)。
    mutating func systemWakeStarted(now: MonotonicInstant, settle: TimeInterval) {
        systemAsleep = false
        wakeUntil = now.advanced(by: settle)
    }

    mutating func displaySleepStarted() {
        displayAsleep = true
    }

    mutating func displayWakeStarted(now: MonotonicInstant, settle: TimeInterval) {
        displayAsleep = false
        // 屏幕睡眠解除不叠加唤醒沉降(系统未整机唤醒,但恢复通信窗口一致)。
        wakeUntil = now.advanced(by: settle)
    }

    /// 重配置 begin:设置/延长重配置抑制到 safety 期限。
    mutating func reconfigureStarted(now: MonotonicInstant, safety: TimeInterval) {
        reconfigureUntil = now.advanced(by: safety)
    }

    /// 重配置完成:收敛到较短的 settle 期限。只缩短 reconfigureUntil,
    /// 绝不触碰 wakeUntil。
    mutating func reconfigureCompleted(now: MonotonicInstant, settle: TimeInterval) {
        reconfigureUntil = now.advanced(by: settle)
    }

    /// 到期检查:期限已过则清掉对应期限,保持后续调度只使用有效截止时间。
    mutating func expireDeadlines(now: MonotonicInstant) {
        if let until = wakeUntil, now >= until {
            wakeUntil = nil
        }
        if let until = reconfigureUntil, now >= until {
            reconfigureUntil = nil
        }
    }
}

/// 门禁运行时:持有状态模型与时钟,管理解除检测定时器。
/// 到期后重新读取当前状态;如果仍有抑制原因,只重新安排下一次期限检查。
nonisolated final class DDCGateRuntime {
    private var model = GateStateModel()
    private let clock: MonotonicClock
    private let lock = NSLock()
    private var deadlineTimer: ScheduledWorkHandle?
    private var recoveryHandlers: [UUID: () -> Void] = [:]
    /// 配置时长。
    private let wakeSettle: TimeInterval
    private let reconfigureSettle: TimeInterval
    private let reconfigureSafety: TimeInterval

    init(
        clock: MonotonicClock = DispatchMonotonicClock(),
        wakeSettle: TimeInterval = 3,
        reconfigureSettle: TimeInterval = 1,
        reconfigureSafety: TimeInterval = 5
    ) {
        self.clock = clock
        self.wakeSettle = wakeSettle
        self.reconfigureSettle = reconfigureSettle
        self.reconfigureSafety = reconfigureSafety
    }

    var isSuppressed: Bool {
        lock.lock(); defer { lock.unlock() }
        return model.isSuppressed(at: clock.now)
    }

    func addRecoveryHandler(_ handler: @escaping () -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        recoveryHandlers[token] = handler
        lock.unlock()
        return token
    }

    func removeRecoveryHandler(_ token: UUID) {
        lock.lock()
        recoveryHandlers.removeValue(forKey: token)
        lock.unlock()
    }

    // MARK: 事件入口

    func systemSleepStarted() {
        lock.lock()
        model.systemSleepStarted()
        cancelDeadlineTimerLocked()
        lock.unlock()
    }

    func systemWakeStarted() {
        lock.lock()
        model.systemWakeStarted(now: clock.now, settle: wakeSettle)
        lock.unlock()
        armDeadlineTimer()
        notifyIfResuming()
    }

    func displaySleepStarted() {
        lock.lock()
        model.displaySleepStarted()
        lock.unlock()
    }

    func displayWakeStarted() {
        lock.lock()
        model.displayWakeStarted(now: clock.now, settle: wakeSettle)
        lock.unlock()
        armDeadlineTimer()
        notifyIfResuming()
    }

    func reconfigureStarted() {
        lock.lock()
        model.reconfigureStarted(now: clock.now, safety: reconfigureSafety)
        lock.unlock()
        armDeadlineTimer()
    }

    func reconfigureCompleted() {
        lock.lock()
        model.reconfigureCompleted(now: clock.now, settle: reconfigureSettle)
        lock.unlock()
        armDeadlineTimer()
    }

    // MARK: 内部

    /// 在锁外调用:读取下一截止时刻并安排定时器。
    private func armDeadlineTimer() {
        lock.lock()
        let next = model.nextDeadline()
        lock.unlock()
        guard let next else { return }
        let delay = clock.now.distance(to: next)
        deadlineTimer?.cancel()
        deadlineTimer = clock.schedule(after: Swift.max(delay, 0.01)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.model.expireDeadlines(now: self.clock.now)
            let stillSuppressed = self.model.isSuppressed(at: self.clock.now)
            self.lock.unlock()
            if stillSuppressed {
                // 新的抑制期限可能已设立;继续跟进。
                self.armDeadlineTimer()
            } else {
                self.notifyRecovery()
            }
        }
    }

    private func cancelDeadlineTimerLocked() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
    }

    private func notifyIfResuming() {
        lock.lock()
        let suppressed = model.isSuppressed(at: clock.now)
        lock.unlock()
        if !suppressed {
            notifyRecovery()
        }
    }

    private func notifyRecovery() {
        lock.lock()
        let handlers = Array(recoveryHandlers.values)
        lock.unlock()
        for handler in handlers {
            handler()
        }
    }
}
