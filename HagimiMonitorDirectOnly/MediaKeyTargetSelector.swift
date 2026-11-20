import CoreGraphics
import Foundation

// MARK: - 音频输出描述

/// 默认音频输出设备的只读描述。
nonisolated struct AudioOutputDescription: Equatable, Sendable {
    let deviceUID: String
    let name: String
    let transportType: String?
    /// 是否可被系统直接调节音量。
    let isControllable: Bool
}

// MARK: - 媒体键目标选择

/// 音量跟随默认音频输出，亮度跟随鼠标所在的可控显示器。
nonisolated enum MediaKeyTargetSelector {
    /// 返回应通过 DDC 调整音量的显示器。系统可调音量的设备由 Core Audio 处理。
    static func volumeTarget(
        audioOutput: AudioOutputDescription?,
        boundIdentity: DisplayIdentity?,
        boundDisplayID: CGDirectDisplayID?,
        displays: [(identity: DisplayIdentity, displayID: CGDirectDisplayID, supportsVolume: Bool)],
        displayNames: [CGDirectDisplayID: String]? = nil
    ) -> CGDirectDisplayID? {
        guard let audioOutput, !audioOutput.isControllable else {
            return nil
        }
        // 显式绑定:身份匹配时用绑定屏。
        if let boundIdentity, let boundDisplayID,
           displays.contains(where: { $0.identity == boundIdentity && $0.displayID == boundDisplayID && $0.supportsVolume }) {
            return boundDisplayID
        }
        let volumeCapable = displays.filter { $0.supportsVolume }
        if let displayNames {
            let outputName = audioOutput.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !outputName.isEmpty else { return nil }
            let sameName = volumeCapable.filter {
                displayNames[$0.displayID]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(outputName) == .orderedSame
            }
            return sameName.count == 1 ? sameName.first?.displayID : nil
        }
        // 调用方仅提供能力列表时，沿用唯一可控屏的选择规则。
        if volumeCapable.count == 1 {
            return volumeCapable.first?.displayID
        }
        // 未知映射:不猜测,交还系统。
        return nil
    }

    /// 无法定位鼠标时，仅在目标唯一时接管亮度键。
    static func brightnessTarget(
        mouseDisplayID: CGDirectDisplayID?,
        displays: [(displayID: CGDirectDisplayID, supportsBrightness: Bool)]
    ) -> CGDirectDisplayID? {
        let available = displays.filter { $0.supportsBrightness }
        if let mouseDisplayID {
            return available.first { $0.displayID == mouseDisplayID }?.displayID
        }
        return available.count == 1 ? available[0].displayID : nil
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

// MARK: - 静音恢复优先级

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
