import AppKit
import Combine
import UserNotifications
import OSLog

/// 通知中心代理,补上菜单栏 App 最容易漏的一环:App 处于前台时(面板或设置
/// 窗口已打开)系统默认不弹横幅,这里显式返回 `.banner + .sound`——否则最
/// 常见的「开着面板时告警」反而只在通知中心里静默堆积。
/// 点击通知按类别路由:压力与进程告警落到「数据统计」页。
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = AlertNotificationDelegate()

    /// 当前系统通知授权状态，供设置页在用户拒权时展示前往系统设置的提示。
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// 授权只申请一次:重复调用系统不再弹窗,这里再挡一道,免得日志里刷无效请求。
    private var didRequestAuthorization = false
    private var didBecomeActiveObserver: (any NSObjectProtocol)?

    private override init() {
        super.init()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAuthorizationStatus()
            }
        }
    }

    /// 从系统通知中心刷新当前授权状态。
    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                self?.authorizationStatus = status
            }
        }
    }

    /// 申请通知权限(.alert + .sound)。
    ///
    /// **只在通知开关打开时调用**(见 AppDelegate):开关默认关,所以首次启动不会弹
    /// 授权窗——用户没打算要通知时不该被打扰。内存、温度和进程占用共用这一次申请。
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else {
            refreshAuthorizationStatus()
            return
        }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                AppLogger.sampler.error("通知授权失败: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                AppLogger.sampler.notice("用户未授权通知,告警将仅通过界面展示")
            }
            DispatchQueue.main.async {
                self?.refreshAuthorizationStatus()
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let isPressureAlert = response.notification.request.content.categoryIdentifier
            == PressureAlertCenter.notificationCategory
        await MainActor.run {
            SettingsWindowPresenter.open(tab: isPressureAlert ? .statistics : nil)
        }
    }
}
