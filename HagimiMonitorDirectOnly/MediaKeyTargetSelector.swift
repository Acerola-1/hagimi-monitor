import CoreGraphics
import Foundation

// MARK: - 音频输出描述(D8/9.1)

/// 默认音频输出设备的只读描述。
nonisolated struct AudioOutputDescription: Equatable, Sendable {
    let deviceUID: String
    let name: String
    let transportType: String?
    /// 是否可被系统直接调节音量。
    let isControllable: Bool
}

// MARK: - 媒体键目标选择(D8/9.1/9.3)

/// 亮度键与音量键的独立目标策略。
/// - 音量:默认跟随系统音频输出对应的显示器(经 UID→身份映射);
///   无法确定或系统可控输出时交还系统,不吞键。
/// - 亮度:鼠标所在外接屏;鼠标在内建屏时交还系统;
///   无法取得鼠标所在屏幕且仅一台可控外接屏时用该屏,多台无法确定时交还系统。
nonisolated enum MediaKeyTargetSelector {
    /// 音量键目标。
    /// - Returns: nil = 交还系统(不消费事件)。
    static func volumeTarget(
        audioOutput: AudioOutputDescription?,
        boundIdentity: DisplayIdentity?,
        boundDisplayID: CGDirectDisplayID?,
        displays: [(identity: DisplayIdentity, displayID: CGDirectDisplayID, supportsVolume: Bool)]
    ) -> CGDirectDisplayID? {
        // 系统自身可调节输出优先交还系统。
        guard let audioOutput, !audioOutput.isControllable else {
            return nil
        }
        // 显式绑定:身份匹配时用绑定屏。
        if let boundIdentity, let boundDisplayID,
           displays.contains(where: { $0.identity == boundIdentity && $0.displayID == boundDisplayID && $0.supportsVolume }) {
            return boundDisplayID
        }
        // 唯一映射:音频输出对应唯一支持音量的外接屏。
        let volumeCapable = displays.filter { $0.supportsVolume }
        if volumeCapable.count == 1 {
            return volumeCapable.first?.displayID
        }
        // 未知映射:不猜测,交还系统。
        return nil
    }

    /// 亮度键目标(保留既有鼠标/单屏策略)。
    static func brightnessTarget(
        mouseDisplayID: CGDirectDisplayID?,
        displays: [(displayID: CGDirectDisplayID, isBuiltIn: Bool, supportsBrightness: Bool)]
    ) -> CGDirectDisplayID? {
        if let mouseDisplayID {
            // 鼠标在内建屏时交还系统,让 macOS 调节内建屏亮度。
            if displays.contains(where: { $0.displayID == mouseDisplayID && $0.isBuiltIn }) {
                return nil
            }
            // 鼠标所在外接屏。
            if let display = displays.first(where: { $0.displayID == mouseDisplayID && !$0.isBuiltIn && $0.supportsBrightness }) {
                return display.displayID
            }
            return nil
        }
        // 无法取得鼠标所在屏幕且仅一台可控外接屏时兜底。
        let controllableExternals = displays.filter { !$0.isBuiltIn && $0.supportsBrightness }
        if controllableExternals.count == 1 {
            return controllableExternals.first?.displayID
        }
        return nil
    }

    /// 调节方法是否接受操作:目标不存在/不支持/无基准 → 不接受(交还系统)。
    static func shouldAccept(
        key: MediaKeyKind,
        target: CGDirectDisplayID?,
        hasBaseline: Bool
    ) -> Bool {
        guard target != nil else { return false }
        switch key {
        case .volume:
            return hasBaseline
        case .brightness:
            return hasBaseline
        case .mute:
            // 静音不需要基线(归零);解除静音需恢复值。
            return true
        }
    }
}

/// 媒体键种类(供纯目标选择逻辑使用)。
nonisolated enum MediaKeyKind: Hashable, Sendable {
    case brightness
    case volume
    case mute
}

// MARK: - 静音恢复优先级(D8/9.4)

/// 静音恢复值解析:进程内最近非零 → 持久化非零 → 兜底。
/// 静音前可靠读到的当前音量纳入"进程内最近"。
nonisolated enum VolumeRestoreResolver {
    /// 兜底值(1/16 满量程,对齐 MonitorControl)。
    static let fallbackValue: Double = 100.0 / 16.0

    /// - Parameters:
    ///   - recentInProcess: 进程内最近非零音量(静音前捕获或最近设置)。
    ///   - persisted: 持久化非零音量(跨会话)。
    ///   - fallback: 兜底值。
    static func resolve(recentInProcess: Double?, persisted: Double?, fallback: Double = fallbackValue) -> Double {
        if let recent = recentInProcess, recent > 0 {
            return min(100, max(0, recent))
        }
        if let persistedValue = persisted, persistedValue > 0 {
            return min(100, max(0, persistedValue))
        }
        return fallback
    }

    /// 静音前捕获:仅当当前值可靠且非零时更新进程内最近值。
    /// - Returns: 更新后的进程内最近值。
    static func captureBeforeMute(current: Double?, recentInProcess: Double?) -> Double? {
        if let current, current > 0 {
            return current
        }
        return recentInProcess
    }
}
