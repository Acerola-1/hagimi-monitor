import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI
import UserNotifications

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
    /// 启动期的订阅(通知开关)。AppDelegate 与 App 同生命周期,不留释放路径。
    private var startupCancellables = Set<AnyCancellable>()

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
        if PanelMotionExperiment.enabled {
            fluidPanelController.presentAnimationPrototype()
            return false
        }
        SettingsWindowPresenter.open()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 通知代理须在启动完成前就位:前台横幅(菜单栏 App 打开面板时即前台)
        // 与通知点击路由都由它承接,冷启动自通知点击的场景也走这里。
        UNUserNotificationCenter.current().delegate = AlertNotificationDelegate.shared

        // 触发 lazy 初始化。菜单栏面板需在启动即常驻(承载状态项图标);
        // 快捷键面板则延迟到首次按下快捷键时再创建(见下方 onKeyUp),
        // 避免开机就构建第二棵完整的 SwiftUI 面板视图树、白白常驻内存。
        _ = store
        // 实时压力告警:订阅采样、记录开关与通知开关,驱动红点与系统通知。
        PressureAlertCenter.shared.attach(to: store)
        // 通知授权只在开关打开时申请一次:开关默认关,所以首次启动不弹授权窗;
        // 之后用户打开开关(或本次启动时它已经开着)才申请。
        store.settings.$alertNotificationsEnabled
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                guard enabled else { return }
                AlertNotificationDelegate.shared.requestAuthorizationIfNeeded()
            }
            .store(in: &startupCancellables)
        _ = fluidPanelController

        // 验证夹具模式(HAGIMI_STATS_FIXTURE):启动即打开「数据统计」页,
        // 供摘要各状态在设置窗口实际宽度下逐项目测;正式运行不受影响。
        if ProcessInfo.processInfo.environment["HAGIMI_STATS_FIXTURE"] != nil {
            DispatchQueue.main.async {
                SettingsWindowPresenter.open(tab: .statistics)
            }
        }

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
