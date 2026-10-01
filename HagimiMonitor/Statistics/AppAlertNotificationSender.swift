import Foundation
import UserNotifications

/// 应用告警通知发送接口，解耦通知决策与系统通知发送副作用。
nonisolated protocol AppAlertNotificationSending: Sendable {
    /// 发送一条通知；失败时抛出错误。
    func send(identifier: String, title: String, body: String) async throws
}

/// 生产实现：交给系统通知中心。
nonisolated struct SystemNotificationSender: AppAlertNotificationSending {
    func send(identifier: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = PressureAlertCenter.notificationCategory
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}

/// 支持有限重试的应用告警通知调度器。
nonisolated struct AppAlertNotificationDispatcher: Sendable {
    let sender: AppAlertNotificationSending
    /// 最大尝试次数（含首次）。
    let maxAttempts: Int

    init(sender: AppAlertNotificationSending = SystemNotificationSender(), maxAttempts: Int = 3) {
        self.sender = sender
        self.maxAttempts = max(1, maxAttempts)
    }

    struct Result: Sendable, Equatable {
        let delivered: Bool
        let attempts: Int
        /// 是否已成功送达并可标记为已通知。
        let shouldMarkNotified: Bool
    }

    /// 发送并做有界重试。返回结果供调用方决定是否记录「已通知」。
    func dispatch(identifier: String, title: String, body: String) async -> Result {
        var attempts = 0
        while attempts < maxAttempts {
            attempts += 1
            do {
                try await sender.send(identifier: identifier, title: title, body: body)
                return Result(delivered: true, attempts: attempts, shouldMarkNotified: true)
            } catch {
                // 发送失败继续重试直至达到最大尝试次数。
                continue
            }
        }
        return Result(delivered: false, attempts: attempts, shouldMarkNotified: false)
    }
}
