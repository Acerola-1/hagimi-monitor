import Foundation

// MARK: - 值模型(D2)

/// 单个控制属性的完整值状态。observed(设备读数)与 desired(用户目标)分离,
/// 未知值不得以默认百分比冒充读数。
nonisolated struct AttributeValueState: Equatable, Sendable {
    var observed: Double?
    var desired: Double?
    /// 最近一次发送成功(上总线)的值。只写模式以此展示"上次设置"。
    var lastApplied: Double?
    /// 持久化历史值(迁移或上次会话),标记未确认。
    var historical: Double?
    var source: AttributeValueSource = .unknown
    var writeStatus: AttributeWriteStatus = .idle
    /// 发出 desired 时的请求序号,用于判断回调是否属于当前请求。
    var activeRequestID: UInt64?

    /// UI 展示值:目标优先(带待确认语义),其次读数,其次历史。
    var displayValue: Double? {
        desired ?? observed ?? lastApplied ?? historical
    }
}

nonisolated enum AttributeValueSource: Equatable, Sendable {
    case observed
    case desired
    case historical
    case unknown
}

nonisolated enum AttributeWriteStatus: Equatable, Sendable {
    case idle
    /// 已进入待写槽,尚未提交底层。
    case pending
    /// 门禁抑制,等恢复窗口重放。
    case deferred
    /// 已上总线但未经设备确认(读数尚未对齐目标)。
    case sentUnverified
    /// 回读确认达到容差。
    case verified
    case failed
}

/// 控制属性统一枚举(沿用三参数,兼容现有 UI/持久化 key)。
nonisolated enum DisplayControlKind: Hashable, Sendable {
    case brightness
    case volume
    case contrast

    var storageKey: String {
        switch self {
        case .brightness: "brightness"
        case .volume: "volume"
        case .contrast: "contrast"
        }
    }
}/// 调度与确认的全部时序常量,集中一处;测试经虚拟时钟驱动这些间隔。
nonisolated enum DisplayControlTiming {
    /// 连续拖动节流:窗口到点提交当前最新目标,不停手也不会无限等待。
    static let throttleInterval: TimeInterval = 0.15
    /// 交互结束后的终值直接提交(节流窗口内的尾部)。
    static let finalCommitGrace: TimeInterval = 0.05
    /// 交互结束后安排一次回读确认的延迟。
    static let confirmReadDelay: TimeInterval = 0.3
    /// 确认回读未达目标的重试间隔(最多两次)。
    static let confirmRetryDelay: TimeInterval = 0.5
    /// 底层调用等待期限。
    static let callDeadline: TimeInterval = 2.0
    /// 故障自动恢复退避序列,四次后停止自动重试。
    static let recoveryBackoff: [TimeInterval] = [1, 2, 5, 15]
    /// 周期轮询间隔(面板可见且展开)。
    static let pollInterval: TimeInterval = 5
    /// 读取失败后的降频间隔。
    static let degradedPollIntervals: [TimeInterval] = [15, 30]
}

/// 量化容差判定:允许 1 raw unit 的偏差,且不低于 0.5 个 UI 百分点。
nonisolated func attributeValueMatches(observed: Double, desired: Double, max: UInt16) -> Bool {
    let rawTolerance = 1.0 / Double(Swift.max(max, 1)) * 100.0
    let tolerance = Swift.max(rawTolerance, 0.5)
    return abs(observed - desired) <= tolerance
}

// MARK: - 有限值校验(D2/3.4)

/// 连续值与范围的转换:完整 UInt16 可表示,拒绝非有限值。
nonisolated enum DDCRawConversion {
    static func ddcRaw(percent: Double, max: UInt16) -> UInt16? {
        guard percent.isFinite else { return nil }
        let clamped = min(100, Swift.max(0, percent))
        let scaled = clamped / 100.0 * Double(max)
        return UInt16(scaled.rounded())
    }

    static func percent(raw: UInt16, max: UInt16) -> Double? {
        guard max > 0 else { return nil }
        let value = Double(raw) / Double(max) * 100.0
        return min(100, Swift.max(0, value))
    }

    /// 零 max 视为无效范围(协议层结构校验失败),不静默替换为 1。
    static func isValidRange(max: UInt16) -> Bool {
        max > 0
    }
}
