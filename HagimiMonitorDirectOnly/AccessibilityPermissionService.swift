import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @MainActor static let shared = AccessibilityPermissionService()

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: DispatchSourceTimer?

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
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.refresh()
            if self.isTrusted {
                self.pollTimer?.cancel()
                self.pollTimer = nil
            }
        }
        pollTimer = timer
        timer.resume()
    }
}
