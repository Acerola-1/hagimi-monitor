import Foundation

/// DDC 传输抽象:生产实现包装 IOAVService 私有调用,测试注入 fake。
/// 这是编排逻辑(调度/去重/门禁重放)与阻塞内核 I/O 之间的唯一边界,
/// 测试通过 fake 验证"哪些请求真正到达底层",不触碰真实显示器。
/// 回调在实现方的执行上下文触发;引擎侧负责回调后回到自身队列。
nonisolated protocol DDCTransport: AnyObject, Sendable {
    /// 读取 VCP 特征。返回 nil 表示无有效应答(超时/坏帧/无服务)。
    func read(service: DDCServiceHandle, vcpCode: UInt8, completion: @escaping @Sendable (DDCTransportReply?) -> Void)
    /// 写入 VCP 特征。返回 false 表示报文未能上总线。
    func write(service: DDCServiceHandle, vcpCode: UInt8, value: UInt16, completion: @escaping @Sendable (Bool) -> Void)
}

/// 结构上有效的 Get VCP Feature Reply。resultCode 0x00=支持,0x01=不支持。
nonisolated struct DDCTransportReply: Equatable, Sendable {
    let resultCode: UInt8
    let current: UInt16
    let max: UInt16
}

/// 对底层 IOAVService 句柄的不透明引用。生产实现持有真实 service 对象;
/// fake 实现只做相等性判断。生命周期由连接对象持有。
nonisolated struct DDCServiceHandle: Equatable, Sendable {
    let identity: String
    let chipAddress: UInt8
    /// 生产适配器用来从当前桥接器重新取得 IOAVService;fake 可保持默认值。
    let displayID: UInt32

    init(identity: String, chipAddress: UInt8, displayID: UInt32 = 0) {
        self.identity = identity
        self.chipAddress = chipAddress
        self.displayID = displayID
    }
}

/// 进程内单调时钟抽象。生产用 DispatchTime;测试注入虚拟时钟驱动
/// 节流/退避/超时,不依赖真实睡眠。
nonisolated protocol MonotonicClock: AnyObject, Sendable {
    var now: MonotonicInstant { get }
    /// 安排在延迟后执行。返回可取消的句柄。
    func schedule(after: TimeInterval, _ work: @escaping @Sendable () -> Void) -> ScheduledWorkHandle
}

/// 单调时刻:以纳秒为单位的可比值。避免直接依赖 DispatchTime 使测试可构造。
nonisolated struct MonotonicInstant: Comparable, Sendable {
    let nanoseconds: UInt64

    static func < (lhs: MonotonicInstant, rhs: MonotonicInstant) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }

    func advanced(by interval: TimeInterval) -> MonotonicInstant {
        MonotonicInstant(nanoseconds: nanoseconds + UInt64(max(0, interval) * 1_000_000_000))
    }

    func distance(to other: MonotonicInstant) -> TimeInterval {
        Double(other.nanoseconds >= nanoseconds ? other.nanoseconds - nanoseconds : 0) / 1_000_000_000
    }
}

nonisolated protocol ScheduledWorkHandle: AnyObject, Sendable {
    func cancel()
}

/// 包装 DispatchWorkItem 的工作句柄。DispatchWorkItem 内部具备线程安全的取消状态管理。
private nonisolated final class DispatchWorkItemHandle: ScheduledWorkHandle, @unchecked Sendable {
    private let item: DispatchWorkItem

    init(item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item.cancel()
    }
}

/// 生产单调时钟:DispatchTime 为源,定时器走全局队列。内部无易变共享状态。
nonisolated final class DispatchMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let queue = DispatchQueue(label: "hagimi.ddc.clock")

    var now: MonotonicInstant {
        MonotonicInstant(nanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    func schedule(after interval: TimeInterval, _ work: @escaping @Sendable () -> Void) -> ScheduledWorkHandle {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + max(0, interval), execute: item)
        return DispatchWorkItemHandle(item: item)
    }
}

/// 测试用虚拟时钟:手动推进时间,立即在当前线程执行到期任务。
/// schedule 返回的句柄可取消,用于验证过期任务不会解除后续状态。
/// 内部状态通过 NSLock 保护，支持测试中的多线程并发调度与步进。
nonisolated final class VirtualMonotonicClock: MonotonicClock, @unchecked Sendable {
    private final class CancelToken: ScheduledWorkHandle, @unchecked Sendable {
        private let lock = NSLock()
        private var _cancelled = false
        var cancelled: Bool {
            lock.withLock { _cancelled }
        }
        func cancel() {
            lock.withLock { _cancelled = true }
        }
    }

    private struct PendingWork: Sendable {
        let deadline: MonotonicInstant
        let token: CancelToken
        let work: @Sendable () -> Void
    }

    private enum NextAction {
        case done
        case skip
        case execute(@Sendable () -> Void)
    }

    private let lock = NSLock()
    private var currentNanoseconds: UInt64 = 0
    private var pending: [PendingWork] = []

    var now: MonotonicInstant {
        lock.withLock {
            MonotonicInstant(nanoseconds: currentNanoseconds)
        }
    }

    /// 推进时钟并按序执行到期任务。
    func advance(by interval: TimeInterval) {
        let target = lock.withLock {
            MonotonicInstant(nanoseconds: currentNanoseconds + UInt64(max(0, interval) * 1_000_000_000))
        }
        while true {
            let action: NextAction = lock.withLock {
                guard let next = pending.filter({ $0.deadline <= target }).min(by: { $0.deadline < $1.deadline }) else {
                    currentNanoseconds = target.nanoseconds
                    return .done
                }
                pending.removeAll { $0.token === next.token }
                currentNanoseconds = next.deadline.nanoseconds
                if !next.token.cancelled {
                    return .execute(next.work)
                }
                return .skip
            }
            switch action {
            case .done:
                return
            case .skip:
                continue
            case .execute(let work):
                work()
            }
        }
    }

    func schedule(after interval: TimeInterval, _ work: @escaping @Sendable () -> Void) -> ScheduledWorkHandle {
        let token = CancelToken()
        lock.withLock {
            let deadline = MonotonicInstant(nanoseconds: currentNanoseconds).advanced(by: interval)
            pending.append(PendingWork(
                deadline: deadline,
                token: token,
                work: work
            ))
        }
        return token
    }
}
