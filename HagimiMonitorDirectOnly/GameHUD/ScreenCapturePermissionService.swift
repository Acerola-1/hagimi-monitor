import AppKit
import CoreGraphics
import Combine

/// 屏幕录制授权服务(Game HUD SCK 测帧依赖)。
/// 交互与键盘锁定授权同型:弹出拖动式引导浮窗(把应用图标拖进系统设置的
/// 「屏幕录制」列表),轮询感知授权完成,无需用户手动刷新。
@MainActor
final class ScreenCapturePermissionService: ObservableObject {
    static let shared = ScreenCapturePermissionService()

    /// CGPreflightScreenCaptureAccess:已授权为 true。系统设置里用户手动
    /// 开关没有变更广播,轮询是唯一可靠的刷新途径;仅引导存活期间轮询。
    @Published private(set) var isTrusted: Bool

    private var pollTimer: AnyCancellable?
    /// 引导期间记录授权前状态,授权完成后回调一次(游戏会话即时补启测帧)。
    var onGranted: (() -> Void)?

    private init() {
        isTrusted = CGPreflightScreenCaptureAccess()
    }

    /// 弹出拖动式引导浮窗(与键盘锁定授权引导同型),并打开系统设置的
    /// 「屏幕录制」面板,开始轮询等待授权完成。
    func presentGuide() {
        refresh()
        guard !isTrusted else { return }
        AccessibilityPermissionGuide.shared.present(
            domain: .screenRecording,
            titleKey: "gamehud.permission.guide-title",
            subtitleKey: "gamehud.permission.guide-subtitle"
        )
        // 打开系统设置 → 隐私与安全性 → 屏幕录制。
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }

    /// 设置页出现时刷新一次并保持轮询(感知用户在系统设置里手动开关)。
    func activatePolling() {
        refresh()
        startPolling()
    }

    func deactivatePolling() {
        pollTimer = nil
    }

    func refresh() {
        let trusted = CGPreflightScreenCaptureAccess()
        let wasTrusted = isTrusted
        isTrusted = trusted
        if trusted && !wasTrusted {
            AccessibilityPermissionGuide.shared.dismiss(domain: .screenRecording)
            pollTimer = nil
            onGranted?()
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
}
