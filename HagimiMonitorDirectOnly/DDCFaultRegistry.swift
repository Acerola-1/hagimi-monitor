import CoreGraphics
import Foundation

// ControlKey 是纯值类型,作为 DDC 写入队列与 fault registry 的字典 key,
// 在后台队列上使用;标 nonisolated 以脱离 MainActor 默认隔离,避免 Swift 6
// 严格并发下 Hashable conformance 跨上下文使用的告警/错误。
nonisolated struct ControlKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

// DDCFaultRegistry 在 DDC 读写后台队列与 UI 间共享;线程安全由内部 NSLock 保证,
// 不依赖 actor 隔离。标 nonisolated 脱离项目默认的 MainActor 隔离。
nonisolated final class DDCFaultRegistry {
    static let readFaultDisableThreshold = 5
    static let readFaultLongerDelayThreshold = 3
    static let writeFaultDisableThreshold = 10
    /// 禁用冷却时长。到期后 isDisabled 放行一次半开探测,成功即自愈,失败则重新冷却。
    /// 取较短值:用户拖动滑轨时若控制曾被误禁,最多等这么久就能再次尝试。
    static let disableCooldown: TimeInterval = 5

    private struct State {
        var readFaults: Int = 0
        var writeFaults: Int = 0
        var disabled: Bool = false
        /// 禁用到期时刻(Date)。nil 表示未禁用。到期后允许一次半开探测。
        var disabledUntil: Date?
    }

    private var states: [ControlKey: State] = [:]
    private let lock = NSLock()

    func recordReadFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.readFaults += 1
        if s.readFaults >= Self.readFaultDisableThreshold {
            s.disabled = true
            s.disabledUntil = Date().addingTimeInterval(Self.disableCooldown)
        }
        states[key] = s
    }

    func recordReadSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        // 一次成功即自愈:清零故障计数并解除禁用。
        // DDC 是偶发丢包协议,失败常是瞬时抖动;只要能读到一次,就说明链路恢复,
        // 不应再因历史累计的失败把控制永久挡在 isDisabled 之外。
        s.readFaults = 0
        s.disabled = false
        s.disabledUntil = nil
        states[key] = s
    }

    func recordWriteFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.writeFaults += 1
        if s.writeFaults >= Self.writeFaultDisableThreshold {
            s.disabled = true
            s.disabledUntil = Date().addingTimeInterval(Self.disableCooldown)
        }
        states[key] = s
    }

    func recordWriteSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        // 一次成功即自愈,理由同 recordReadSuccess:避免历史累计失败导致控制永久禁用。
        s.writeFaults = 0
        s.disabled = false
        s.disabledUntil = nil
        states[key] = s
    }

    func isDisabled(_ key: ControlKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let s = states[key], s.disabled else { return false }
        // 冷却到期则放行一次半开探测:此处不清 disabled,等真正读写成功才在
        // recordXxxSuccess 里自愈。若探测再失败,recordXxxFailure 会重置 disabledUntil
        // 延长冷却。这样既能从误禁中恢复,又不会在链路仍坏时每次都白发 I2C。
        if let until = s.disabledUntil, Date() >= until {
            return false
        }
        return true
    }

    func shouldUseLongerDelay(_ key: ControlKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (states[key]?.readFaults ?? 0) >= Self.readFaultLongerDelayThreshold
    }

    func reset(displayID: CGDirectDisplayID) {
        lock.lock(); defer { lock.unlock() }
        for key in states.keys where key.displayID == displayID {
            states.removeValue(forKey: key)
        }
    }
}
