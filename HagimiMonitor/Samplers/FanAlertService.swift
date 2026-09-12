import Foundation
import Combine
import UserNotifications
import OSLog

/// 风扇告警服务:订阅 `FanSampler.status` 的变化,在状态恶化(→ warning / fault)
/// 时发送 macOS 用户通知;状态恢复到 normal 时发送恢复通知。
///
/// 告警策略(避免通知轰炸):
/// - 仅在状态「升级」(更严重)时触发告警通知;同一级别不重复发。
/// - 状态从 warning/fault 恢复到 normal 时发一条恢复通知。
/// - unknown 不触发任何通知(传感器数据不足,无法判断)。
///
/// 使用 `UNUserNotificationCenter`(系统通知中心),需用户授权。
/// 首次 attach 时请求授权;被拒后静默跳过(不影响采样与面板展示)。
final class FanAlertService {
    static let shared = FanAlertService()

    /// 单例私有的 FanSampler 引用,attach 后持有。
    private weak var sampler: FanSampler?
    private var cancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    /// 上一次触发过通知的状态(去重用)。初始为 unknown,首次到 normal 不发恢复通知。
    private var lastAlertedStatus: FanStatus = .unknown
    /// 通知设置的持有者。**必须由 attach 注入,不能反向取 `AppDelegate.shared?.store`**:
    /// attach 是在 `MonitorStore.init` 内部调用的,那时 store 的 `lazy var` 初始化还没返回,
    /// 反查会重入同一个惰性初始化并**直接死锁**(实测表现为测试宿主启动即挂起)。
    private weak var settings: MonitorSettings?

    /// 通知总开关:关着就完全不发。授权申请与压力告警共用一处
    /// (`AlertNotificationDelegate.requestAuthorizationIfNeeded`)。
    /// 关掉期间只更新 `lastAlertedStatus`、不发通知;重新打开时按当前状态补判一次。
    private var notificationsEnabled: Bool {
        settings?.alertNotificationsEnabled ?? false
    }

    private init() {}

    /// 绑定到 FanSampler,开始监听状态变化并发送告警通知。
    /// - Parameter sampler: 风扇采样器,弱引用持有,避免循环引用。
    func attach(to sampler: FanSampler, settings: MonitorSettings) {
        self.sampler = sampler
        self.settings = settings
        cancellable = sampler.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.handleStatusChange(newStatus, sampler: sampler)
            }
        // 通知重开时按**当前**状态补判一次:与压力告警「关掉即 reset、重开后重新累计」
        // 同一套语义。否则风扇一直停在 warning 时,重开通知也永远不响——状态没变化
        // 就不会再有新帧,`lastAlertedStatus` 永远等于它。
        settingsCancellable = settings.$alertNotificationsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self, enabled else { return }
                self.lastAlertedStatus = .unknown
                self.handleStatusChange(sampler.status, sampler: sampler)
            }
    }

    /// 处理状态变化:决定是否发送告警/恢复通知。
    /// - Parameters:
    ///   - newStatus: FanSampler 最新发布的风扇状态。
    ///   - sampler: 风扇采样器,用于读取当前风扇详情填充通知正文。
    private func handleStatusChange(_ newStatus: FanStatus, sampler: FanSampler) {
        // 通知关着时只更新已上报状态,不发任何通知——恢复通知同理。
        guard notificationsEnabled else {
            lastAlertedStatus = newStatus
            return
        }
        // 状态未变则不处理(理论上 Combine 已去重,这里二次保险)。
        guard newStatus != lastAlertedStatus else { return }

        switch newStatus {
        case .fault:
            // 停转或传感器异常:最高优先级,立即告警。
            sendFanAlert(status: .fault, fans: sampler.fans)
            lastAlertedStatus = .fault
        case .warning:
            // 仅在从未告警或上次是 normal/unknown 时告警(fault→warning 是恢复,不发告警)。
            if lastAlertedStatus < .warning {
                sendFanAlert(status: .warning, fans: sampler.fans)
            }
            lastAlertedStatus = .warning
        case .normal:
            // 从 warning/fault 恢复到正常:发恢复通知。
            if lastAlertedStatus == .warning || lastAlertedStatus == .fault {
                sendRecoveryAlert(fans: sampler.fans)
            }
            lastAlertedStatus = .normal
        case .unknown:
            // 传感器数据不足,不触发通知,但更新 lastAlertedStatus 以便下次正确判断。
            lastAlertedStatus = .unknown
        }
    }

    /// 发送风扇异常告警通知。
    /// - Parameters:
    ///   - status: 告警级别(.warning 或 .fault)。
    ///   - fans: 当前风扇读数,用于在通知正文中展示具体 RPM。
    private func sendFanAlert(status: FanStatus, fans: [FanInfo]) {
        let content = UNMutableNotificationContent()
        let maxRPM = fans.map(\.currentRPM).max() ?? 0

        switch status {
        case .fault:
            content.title = String(localized: "fan.alert.fault.title")
            content.body = String(localized: "fan.alert.fault.body \(maxRPM)")
            content.sound = .defaultCritical
        case .warning:
            content.title = String(localized: "fan.alert.warning.title")
            content.body = String(localized: "fan.alert.warning.body \(maxRPM)")
            content.sound = .default
        default:
            break
        }

        let request = UNNotificationRequest(
            identifier: "hagimi-fan-alert",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.sampler.error("发送风扇告警通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 发送风扇状态恢复通知(从 warning/fault 回到 normal)。
    private func sendRecoveryAlert(fans: [FanInfo]) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "fan.alert.recovery.title")
        let maxRPM = fans.map(\.currentRPM).max() ?? 0
        content.body = String(localized: "fan.alert.recovery.body \(maxRPM)")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "hagimi-fan-alert",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.sampler.error("发送风扇恢复通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
