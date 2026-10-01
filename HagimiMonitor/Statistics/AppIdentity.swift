import AppKit
import Foundation

/// 应用的稳定身份。
///
/// 优先使用可验证的 bundle identifier，系统进程使用规范化的可执行路径作为身份，
/// 无法解析稳定身份时标记为 unresolved 会话进程键，避免同名进程冲突。
nonisolated struct AppIdentity: Sendable, Equatable, Hashable {

    /// 身份的来源类别。展示层据此决定是否显示技术标识，以及历史是否可跨名称延续。
    enum Kind: String, Sendable, Codable, Equatable {
        /// 有 bundle identifier 的常规应用：跨改名保持同一历史。
        case bundle
        /// 系统进程或无 bundle 的可执行文件：用可执行路径类别作为身份。
        case systemExecutable
        /// 拿不到稳定身份，只能按本次会话的进程标识区分。
        /// 明确标记为 unresolved，避免与同名应用自动合并。
        case unresolved
    }

    let kind: Kind
    /// 稳定主键。bundle 类为 bundle identifier；可执行为规范化路径；否则为会话进程键。
    let stableKey: String
    /// 供展示的名称。名称变化不影响主键。
    let displayName: String

    /// 落库使用的主键，带类别前缀避免不同类别的键互相碰撞。
    var storageKey: String { "\(kind.rawValue):\(stableKey)" }

    /// 该身份是否可用于跨重启的历史延续。unresolved 不行。
    var isStableAcrossLaunches: Bool { kind != .unresolved }

    /// 是否为需要隐藏技术身份的普通行（系统进程与 unresolved 都给中性显示）。
    var prefersHiddenTechnicalIdentity: Bool { true }
}

/// 从运行中的进程解析稳定身份。
nonisolated enum AppIdentityResolver: Sendable {

    /// 由 pid 解析身份；进程已退出或信息不足时返回 unresolved。
    ///
    /// - Parameter sessionHint: 调用方提供的会话内唯一线索（例如可执行路径），
    ///   在拿不到 bundle 时用于区分同名进程。
    static func resolve(pid: pid_t, name: String, sessionHint: String? = nil) -> AppIdentity {
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier,
           !bundleID.isEmpty {
            return AppIdentity(kind: .bundle, stableKey: bundleID, displayName: name)
        }

        // 系统守护进程与命令行工具：用可执行路径作为可稳定验证的身份。
        if let path = executablePath(for: pid), !path.isEmpty {
            return AppIdentity(kind: .systemExecutable, stableKey: path, displayName: name)
        }

        // 无法获取稳定身份时回退为 unresolved 会话键。
        let hint = sessionHint ?? "pid-\(pid)"
        return AppIdentity(kind: .unresolved, stableKey: hint, displayName: name)
    }

    /// 通过 libproc 读取可执行路径；失败返回 nil。
    private static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
