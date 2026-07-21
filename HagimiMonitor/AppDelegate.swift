import AppKit
import KeyboardShortcuts
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

    private(set) lazy var pinnedPanelController: PinnedPanelController = {
        PinnedPanelController(store: store) { [weak self] in
            self?.fluidPanelController.dismissPanelForSettings()
            SettingsWindowPresenter.openFromOutsideSwiftUI()
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 触发 lazy 初始化
        _ = store
        _ = fluidPanelController
        _ = pinnedPanelController

        // 注册全局快捷键:切换钉住面板显隐。
        KeyboardShortcuts.onKeyUp(for: .togglePinnedPanel) { [weak self] in
            MainActor.assumeIsolated {
                self?.pinnedPanelController.toggle()
            }
        }

        // 若「开机自动显示」开启,则启动时显示钉住面板。
        if store.settings.pinnedPanelAutoShow {
            pinnedPanelController.show()
        }

        // 启动 Sparkle 自更新(仅直接分发版;App Store 版更新交由商店管理)。
        // 初始化即开始后台定时检查。
        #if DIRECT_DISTRIBUTION
        _ = UpdateService.shared
        #endif

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
