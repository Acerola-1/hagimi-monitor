import AppKit
import UserNotifications
import OSLog

/// 通知中心代理,补上菜单栏 App 最容易漏的一环:App 处于前台时(面板或设置
/// 窗口已打开)系统默认不弹横幅,这里显式返回 `.banner + .sound`——否则最
/// 常见的「开着面板时告警」反而只在通知中心里静默堆积。
/// 点击通知按类别路由:压力告警落到「数据统计」页,其余(风扇告警)只把
/// 设置窗口带到前台。
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotificationDelegate()

    /// 授权只申请一次:重复调用系统不再弹窗,这里再挡一道,免得日志里刷无效请求。
    private var didRequestAuthorization = false

    private override init() {
        super.init()
    }

    /// 申请通知权限(.alert + .sound)。
    ///
    /// **只在通知开关打开时调用**(见 AppDelegate):开关默认关,所以首次启动不会弹
    /// 授权窗——用户没打算要通知时不该被打扰。风扇告警与压力告警共用这一次申请。
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.sampler.error("通知授权失败: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                AppLogger.sampler.notice("用户未授权通知,告警将仅通过界面展示")
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
