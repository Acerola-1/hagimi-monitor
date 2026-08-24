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

    /// 轮询最大时长(秒)。授权通过或用户拒绝/忽略均在此窗口内定案;
    /// 超时仍未授权即停止轮询,避免常驻菜单栏 app 无限空转查询权限状态。
    private static let maxPollingSeconds: Int = 120

    private var pollTimer: DispatchSourceTimer?
    private var polledSeconds = 0

    deinit {
        pollTimer?.cancel()
    }

    func refresh() {
        let trusted = CGPreflightListenEventAccess()
        // 等值守卫:浮层 2s 轮询期间同值不触发 objectWillChange,避免
        // 无意义的发布循环。
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// 键盘锁定未授权时磁贴下方的提示文案 key:值即系统「隐私与安全性」
    /// 中用户需打开的授权项名称,与 request() 引导的入口一致。
    var permissionHintKey: String.LocalizationValue { "quicktools.permission.input-monitoring" }

    /// 请求授权:触发系统授权弹窗并轮询直到通过。
    /// 弹窗自带「打开系统设置」入口,不重复主动拉起设置页。
    func request() {
        _ = CGRequestListenEventAccess()
        startPollingUntilGranted()
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
#endif
