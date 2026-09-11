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

    private override init() {
        super.init()
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
