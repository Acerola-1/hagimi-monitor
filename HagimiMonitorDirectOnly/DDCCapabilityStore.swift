import CoreGraphics
import Foundation

// ControlKey 是纯值类型,作为 DDC 能力表与写入去重的字典 key,在后台队列上使用;
// 标 nonisolated 以脱离 MainActor 默认隔离,避免 Swift 6 严格并发下 Hashable
// conformance 跨上下文使用的告警/错误。
nonisolated struct ControlKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

/// DDC 控制能力三态。核心设计:把"这条控制到底支持不支持"(检测期的慢变量)与
/// "这一个数据包有没有送达"(运行期的瞬时丢包)彻底分离——瞬时丢包**永不**翻转能力。
///
/// - supported:显示器对该 VCP 明确回复"支持"(结果码 0x00),可读且可控。
/// - unsupported:显示器明确回复"不支持"(结果码 0x01)。这是**唯一**会让 UI 置灰的
///   确定性负例——因为它来自显示器自己的应答,不是我们的猜测。
/// - unknown:没有收到任何有效应答。可能是只写型显示器、暂时性丢包或不可读但可写。
///   此时保持**乐观**:仍显示控制、仍允许写入,绝不据此置灰。
nonisolated enum DDCCapability {
    case supported
    case unsupported
    case unknown
}

/// DDC 能力表。取代旧的 DDCFaultRegistry——不再基于运行期读写失败次数做禁用/冷却
/// (那会把正常的瞬时丢包升级成控制锁死)。能力只在检测/探测阶段写入,并在
/// 重配置/唤醒/面板打开时重新探测刷新。
///
/// 线程安全由内部 NSLock 保证,不依赖 actor 隔离。
nonisolated final class DDCCapabilityStore {
    private var capabilities: [ControlKey: DDCCapability] = [:]
    private let lock = NSLock()

    /// 读取能力。从未探测过的 key 返回 `.unknown`(乐观默认)。
    func capability(_ key: ControlKey) -> DDCCapability {
        lock.lock(); defer { lock.unlock() }
        return capabilities[key] ?? .unknown
    }

    func set(_ capability: DDCCapability, for key: ControlKey) {
        lock.lock(); defer { lock.unlock() }
        capabilities[key] = capability
    }

    func reset(displayID: CGDirectDisplayID) {
        lock.lock(); defer { lock.unlock() }
        for key in capabilities.keys where key.displayID == displayID {
            capabilities.removeValue(forKey: key)
        }
    }
}
