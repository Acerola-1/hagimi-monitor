import AppKit
import SwiftUI

/// App 生命周期代理,持有 `MonitorStore` 和 `FluidPanelController`。
/// 使用 `@NSApplicationDelegateAdaptor` 接入 SwiftUI 生命周期。
///
/// MonitorStore 的所有权:AppDelegate 创建并持有唯一实例,
/// HagimiMonitorApp 通过 appDelegate.store 引用它。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) lazy var store: MonitorStore = MonitorStore()
    private(set) lazy var fluidPanelController: FluidPanelController = {
        FluidPanelController(store: store) { [weak self] in
            // 先关闭面板再打开设置窗口
            self?.fluidPanelController.dismissPanelForSettings()
            // 复用 openSettings 环境 action(与 Cmd+, 走同一条路径),
            // 而非依赖未公开的 showSettingsWindow: selector
            SettingsWindowPresenter.openFromOutsideSwiftUI()
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 触发 lazy 初始化
        _ = store
        _ = fluidPanelController

        // 注册 willTerminate 通知
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLaunchStateTracker.shared.markCleanExit()
                AppLogStore.shared.flush()
            }
        }
    }
}
