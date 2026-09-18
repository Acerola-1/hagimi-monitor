import AppKit
import Combine
import CoreGraphics
import Foundation

/// 「输入监控」授权服务。
///
/// 键盘锁的 HID 链路依赖它:macOS 27 起键盘类 HID 设备(内置键盘的
/// 键盘 collection 与蓝牙外接键盘)带 RequiresTCCAuthorization 标记,
/// 无此授权时设备打不开、键盘按键事件也不会投递给事件 tap——表现为
/// 字母全部穿透、媒体类系统事件被静默吞掉。与 AccessibilityPermissionService
/// 同构:发布 isTrusted,请求时打开系统设置并展示拖拽引导,轮询等待授权。
@MainActor
final class InputMonitoringPermissionService: ObservableObject {
    @MainActor static let shared = InputMonitoringPermissionService()

    @Published private(set) var isTrusted: Bool = CGPreflightListenEventAccess()

    /// 轮询最大时长(秒)。授权通过或用户拒绝/忽略均在此窗口内定案;
    /// 超时仍未授权即停止轮询(浮层展示期间的 refresh 仍在兜底校准)。
    private static let maxPollingSeconds: Int = 120

    private let cleanupBox = InputMonitoringServiceCleanupBox()
    private var polledSeconds = 0

    /// 键盘锁定未授权时磁贴下方的提示文案 key:值即系统「隐私与安全性」
    /// 中用户需打开的授权项名称。
    var permissionHintKey: String.LocalizationValue { "quicktools.permission.input-monitoring" }

    func refresh() {
        let trusted = CGPreflightListenEventAccess()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted {
            AccessibilityPermissionGuide.shared.dismiss()
        }
    }

    func request(
        titleKey: String.LocalizationValue = "quicktools.permission.accessibility.guide-title",
        subtitleKey: String.LocalizationValue = "quicktools.permission.input-monitoring.guide-subtitle"
    ) {
        // 触发系统请求(仅首次有效,已被拒绝的进程不会再弹),再打开
        // 设置页并展示拖拽引导;授权结果由轮询与后续 refresh 感知。
        // 引导浮窗使用专用副标题指出需要在「输入监控」中开启。
        _ = CGRequestListenEventAccess()
        openSystemSettings()
        AccessibilityPermissionGuide.shared.present(titleKey: titleKey, subtitleKey: subtitleKey)
        startPollingUntilGranted()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    private func startPollingUntilGranted() {
        cleanupBox.pollTimer?.cancel()
        polledSeconds = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.refresh()
            self.polledSeconds += 1
            if self.isTrusted || self.polledSeconds >= Self.maxPollingSeconds {
                self.cleanupBox.pollTimer?.cancel()
                self.cleanupBox.pollTimer = nil
            }
        }
        cleanupBox.pollTimer = timer
        timer.resume()
    }
}

/// 线程安全清理容器：在 deinit 阶段安全释放定时器。
private nonisolated final class InputMonitoringServiceCleanupBox: @unchecked Sendable {
    var pollTimer: DispatchSourceTimer?

    deinit {
        pollTimer?.cancel()
    }
}
