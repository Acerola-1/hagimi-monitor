#if !DIRECT_DISTRIBUTION
import Combine
import CoreGraphics
import Foundation

/// 输入监控权限服务:沙盒内创建过滤型事件 tap 的授权通道
/// (CGPreflightListenEventAccess / CGRequestListenEventAccess)。
/// 接口形态与 Direct 渠道的 AccessibilityPermissionService 对齐,
/// QuickToolsStore 以同一套引导流程消费两种权限。
///
/// 授权通过后,事件 tap 侧的信任缓存存在数十秒传播延迟(实测约
/// 40 秒),期间 CGEventTapCreate 仍会失败;该窗口由 owner
/// (QuickToolsStore)以挂起重试兜底,本服务只负责授权状态本身。
@MainActor
final class InputMonitoringPermissionService: ObservableObject {
    @MainActor static let shared = InputMonitoringPermissionService()

    @Published private(set) var isTrusted: Bool = CGPreflightListenEventAccess()

    private var pollTimer: DispatchSourceTimer?

    deinit {
        pollTimer?.cancel()
    }

    func refresh() {
        isTrusted = CGPreflightListenEventAccess()
    }

    /// 请求授权:触发系统授权弹窗并轮询直到通过。
    /// 弹窗自带「打开系统设置」入口,不重复主动拉起设置页。
    func request() {
        _ = CGRequestListenEventAccess()
        startPollingUntilGranted()
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
#endif
