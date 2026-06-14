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

    private struct State {
        var readFaults: Int = 0
        var writeFaults: Int = 0
        var disabled: Bool = false
    }

    private var states: [ControlKey: State] = [:]
    private let lock = NSLock()

    func recordReadFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.readFaults += 1
        if s.readFaults >= Self.readFaultDisableThreshold {
            s.disabled = true
        }
        states[key] = s
    }

    func recordReadSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.readFaults = max(0, s.readFaults - 1)
        states[key] = s
    }

    func recordWriteFailure(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.writeFaults += 1
        if s.writeFaults >= Self.writeFaultDisableThreshold {
            s.disabled = true
        }
        states[key] = s
    }

    func recordWriteSuccess(_ key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        var s = states[key] ?? State()
        s.writeFaults = max(0, s.writeFaults - 1)
        states[key] = s
    }

    func isDisabled(_ key: ControlKey) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return states[key]?.disabled ?? false
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
