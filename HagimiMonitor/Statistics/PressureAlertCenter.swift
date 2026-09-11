import Combine
import Foundation
import OSLog
import UserNotifications

/// 实时压力告警中心:把内存/热压力的实时档位折成「episode + 未读」两件事,
/// 驱动菜单栏与面板红点、以及系统通知。判定与统计记录器同源同口径
/// (内存 pressure-level 0/1/2、CPU thermal-pressure 0...3)。
///
/// - 红点:任一维度进入非正常档即点亮;「查看统计页」或「恢复」后熄灭;
/// - 通知:仅严重档(内存 2;热 2/3)且持续满 `notificationSustain` 才发,
///   同一 episode 同档位只发一次;
/// - 关闭「数据统计」即静音:红点熄灭、不再通知(查看路径本就在统计页)。
final class PressureAlertCenter: ObservableObject {
    static let shared = PressureAlertCenter()

    /// 通知类别:点击通知据此路由到「数据统计」页(见 `AlertNotificationDelegate`)。
    static let notificationCategory = "hagimi-pressure-alert"

    /// 严重档持续门槛,兼挡两类误报:秒级瞬时抖动,以及睡眠唤醒后短时抬高的档位。
    static let notificationSustain: TimeInterval = 60

    /// 观测断档阈值:超过它没有新帧(睡眠/退出/采样停摆)后,严重档的
    /// 持续计时从新帧重新起算——跨断档不累计。
    static let observationBreak: TimeInterval = 30

    /// 菜单栏负载环 / 指标图标的红点:点开面板即清。
    @Published private(set) var menuBarUnread = false
    /// 面板右上角数据统计入口的红点:查看「数据统计」页即清。
    @Published private(set) var statisticsEntryUnread = false

    private var machine = PressureAlertStateMachine()
    private var cancellables = Set<AnyCancellable>()
    private var isEnabled = true

    /// 验证夹具(仅环境变量触发,正式运行零开销):
    /// - `1`:跳过实时判定、两处红点常亮,供截图核对落点;
    /// - `simulate`:固定喂「内存警告」档,仍走完整 episode/已读/清除链路,
    ///   便于确定性验收点击与清除行为,不必等真实压力出现。
    private let fixtureMode = ProcessInfo.processInfo.environment["HAGIMI_ALERT_FIXTURE"]
    private var isForcedOn: Bool { fixtureMode == "1" }
    private var isSimulating: Bool { fixtureMode == "simulate" }

    private init() {}

    /// 绑定实时采样与记录开关。
    func attach(to store: MonitorStore) {
        guard !isForcedOn else {
            menuBarUnread = true
            statisticsEntryUnread = true
            return
        }

        store.$modules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modules in
                self?.ingest(modules: modules)
            }
            .store(in: &cancellables)

        store.settings.$statisticsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.setEnabled(enabled)
            }
            .store(in: &cancellables)
    }

    /// 某个入口已被用户点开:只清该入口的红点(同一 episode 内不再重新点亮,
    /// 除非档位再升级)。
    func markRead(_ entry: PressureAlertStateMachine.Entry) {
        guard !isForcedOn else { return }
        machine.markRead(entry)
        publishIfChanged()
    }

    /// 用户已查看统计页:全部入口标记已读。
    func markAllRead() {
        guard !isForcedOn else { return }
        machine.markAllRead()
        publishIfChanged()
    }

    private func ingest(modules: [MonitorModule]) {
        guard isEnabled else { return }
        let levels = isSimulating ? (memory: 1, thermal: nil) : Self.levels(from: modules)
        let alerts = machine.ingest(
            memoryLevel: levels.memory,
            thermalLevel: levels.thermal,
            at: Date(),
            sustain: Self.notificationSustain,
            breakThreshold: Self.observationBreak
        )
        publishIfChanged()
        for alert in alerts {
            sendNotification(alert)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        // 关闭记录即静音:进行中的 episode 一并作废,重新打开后按新观测重新判定。
        if !enabled { machine.reset() }
        publishIfChanged()
    }

    private func publishIfChanged() {
        let menuBar = machine.isUnread(.menuBar)
        if menuBarUnread != menuBar { menuBarUnread = menuBar }
        let entry = machine.isUnread(.statisticsEntry)
        if statisticsEntryUnread != entry { statisticsEntryUnread = entry }
    }

    // MARK: - 档位提取

    /// 从一帧模块读数取两路压力档位;占位模块与 unknown 档位按「无观测」处理。
    static func levels(from modules: [MonitorModule]) -> (memory: Int?, thermal: Int?) {
        var memory: Int?
        var thermal: Int?
        for module in modules where !module.isPlaceholder {
            switch module.kind {
            case .memory:
                if let raw = numeric("pressure-level", in: module) {
                    memory = StatisticsRecorder.memoryLevel(raw)
                }
            case .cpu:
                if let raw = numeric("thermal-pressure", in: module) {
                    thermal = StatisticsRecorder.thermalLevel(raw)
                }
            default:
                break
            }
        }
        return (memory, thermal)
    }

    private static func numeric(_ name: String, in module: MonitorModule) -> Double? {
        module.metrics.first { $0.name == name }?.numericValue
    }

    // MARK: - 通知

    private func sendNotification(_ alert: PressureAlertStateMachine.Alert) {
        let content = UNMutableNotificationContent()
        switch alert.kind {
        case .memory:
            content.title = String(localized: "alert.pressure.memory.title")
            content.body = String(localized: "alert.pressure.memory.body \(levelName(alert))")
        case .thermal:
            content.title = String(localized: "alert.pressure.thermal.title")
            content.body = String(localized: "alert.pressure.thermal.body \(levelName(alert))")
        }
        // 压力告警用默认声音:critical 声音需专门 entitlement,留给事故级,
        // 不绕过用户的专注模式。
        content.sound = .default
        content.categoryIdentifier = Self.notificationCategory

        let request = UNNotificationRequest(
            identifier: alert.kind == .memory ? "hagimi-pressure-memory" : "hagimi-pressure-thermal",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.sampler.error("发送压力告警通知失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 通知只在严重档发出,档位名复用统计页同一批字符串。
    private func levelName(_ alert: PressureAlertStateMachine.Alert) -> String {
        switch (alert.kind, alert.level) {
        case (.memory, _): String(localized: "memory-pressure.critical")
        case (.thermal, 3): String(localized: "thermal-pressure.critical")
        default: String(localized: "thermal-pressure.serious")
        }
    }
}
