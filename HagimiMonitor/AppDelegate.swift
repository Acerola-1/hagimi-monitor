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
        FluidPanelController(
            store: store,
            openSettings: { [weak self] in
                self?.fluidPanelController.dismissPanelForSettings()
                SettingsWindowPresenter.openFromOutsideSwiftUI()
            }
        )
    }()

    private(set) lazy var pinnedPanelController: PinnedPanelController = {
        PinnedPanelController(store: store) { [weak self] in
            self?.fluidPanelController.dismissPanelForSettings()
            SettingsWindowPresenter.openFromOutsideSwiftUI()
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 触发 lazy 初始化。菜单栏面板需在启动即常驻(承载状态项图标);
        // 快捷键面板则延迟到首次按下快捷键时再创建(见下方 onKeyUp),
        // 避免开机就构建第二棵完整的 SwiftUI 面板视图树、白白常驻内存。
        _ = store
        _ = fluidPanelController

        // 注册全局快捷键:切换钉住面板显隐。首次触发时惰性创建 pinnedPanelController。
        KeyboardShortcuts.onKeyUp(for: .togglePinnedPanel) { [weak self] in
            MainActor.assumeIsolated {
                self?.pinnedPanelController.toggle()
            }
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
