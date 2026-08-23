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
    /// @NSApplicationDelegateAdaptor 下 `NSApp.delegate` 是 SwiftUI 的转发壳
    /// (SwiftUI.AppDelegate),外部代码取真实实例需走这里。
    static private(set) weak var shared: AppDelegate?

    private(set) lazy var store: MonitorStore = MonitorStore()

    override init() {
        super.init()
        Self.shared = self
    }

    private(set) lazy var fluidPanelController: FluidPanelController = {
        FluidPanelController(
            store: store,
            openSettings: { [weak self] in
                self?.fluidPanelController.dismissPanelForSettings()
                SettingsWindowPresenter.open()
            }
        )
    }()

    private(set) lazy var pinnedPanelController: PinnedPanelController = {
        PinnedPanelController(store: store, openSettings: { [weak self] in
            self?.fluidPanelController.dismissPanelForSettings()
            SettingsWindowPresenter.open()
        })
    }()

    /// 用户经 Finder/Spotlight 重新打开已运行的应用时(rapp 事件)的落脚点:
    /// 纯菜单栏应用无 Dock 图标、无主窗口可恢复,默认行为下重新打开毫无可见
    /// 反馈,这里优先呈现设置窗口。返回 false:reopen 意图已由设置窗口承接,
    /// 无需系统再走"恢复隐藏窗口"的默认路径。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowPresenter.open()
        return false
    }

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
                // 退出前释放快捷功能的电源断言与键盘拦截。
                QuickToolsStore.shared.stop()
                // 退出时恢复所有显示器的 gamma 表,避免退出后显示器仍被压暗。
                // gamma 调光仅存在于 Direct 分发版(对应 HagimiMonitorDirectOnly 目录)。
                #if DIRECT_DISTRIBUTION
                GammaDimmingController.shared.resetAll()
                #endif
            }
        }
    }
}
