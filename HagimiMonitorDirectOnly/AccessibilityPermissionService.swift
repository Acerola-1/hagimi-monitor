import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @MainActor static let shared = AccessibilityPermissionService()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    /// 轮询最大时长(秒)。授权通过或用户拒绝/忽略均在此窗口内定案;
    /// 超时仍未授权即停止轮询。授权变化仍有系统广播(accessibilityChanged)兜底感知。
    private static let maxPollingSeconds: Int = 120

    private var pollTimer: DispatchSourceTimer?
    private var polledSeconds = 0

    init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityChanged(_:)),
            name: .init("com.apple.accessibility.api"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.cancel()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        // 等值守卫:浮层轮询期间同值不触发 objectWillChange,避免无意义的
        // 发布循环(本服务的撤销已有系统广播回调,流入的 refresh 多为同值)。
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// 键盘锁定未授权时磁贴下方的提示文案 key:值即系统「隐私与安全性」
    /// 中用户需打开的授权项名称。
    var permissionHintKey: String.LocalizationValue { "quicktools.permission.accessibility" }

    func request() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
        startPollingUntilGranted()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func accessibilityChanged(_ note: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    private func startPollingUntilGranted() {
        pollTimer?.cancel()
        polledSeconds = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.refresh()
            self.polledSeconds += 1
            // 授权通过或超过最长等待窗口(用户拒绝/忽略)即停止轮询。
            if self.isTrusted || self.polledSeconds >= Self.maxPollingSeconds {
                self.pollTimer?.cancel()
                self.pollTimer = nil
            }
        }
        pollTimer = timer
        timer.resume()
    }
}
