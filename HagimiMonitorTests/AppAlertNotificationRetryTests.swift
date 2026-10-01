import Foundation
import Testing
@testable import HagimiMonitorDirect

/// N03：发送失败不虚记成功；重试有界，不形成通知风暴。
/// 测试使用替身发送器，不向用户发送真实通知。
struct AppAlertNotificationRetryTests {

    /// 记录调用次数并可按脚本失败的替身。
    ///
    /// 用 actor 而非锁：send 是 async，锁在异步上下文里不可用。
    actor StubSender: AppAlertNotificationSending {
        private var attempts = 0
        private let failuresBeforeSuccess: Int
        private let alwaysFails: Bool

        init(failuresBeforeSuccess: Int = 0, alwaysFails: Bool = false) {
            self.failuresBeforeSuccess = failuresBeforeSuccess
            self.alwaysFails = alwaysFails
        }

        var attemptCount: Int { attempts }

        struct Boom: Error {}

        func send(identifier: String, title: String, body: String) async throws {
            attempts += 1
            if alwaysFails { throw Boom() }
            if attempts <= failuresBeforeSuccess { throw Boom() }
        }
    }

    @Test func successOnFirstAttemptIsDelivered() async {
        let sender = StubSender()
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 3)
        let result = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        #expect(result.delivered)
        #expect(result.attempts == 1)
        #expect(result.shouldMarkNotified)
    }

    @Test func transientFailureIsRetriedUntilSuccess() async {
        let sender = StubSender(failuresBeforeSuccess: 2)
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 3)
        let result = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        #expect(result.delivered)
        #expect(result.attempts == 3)
        #expect(result.shouldMarkNotified)
    }

    @Test func persistentFailureStopsAtAttemptLimit() async {
        let sender = StubSender(alwaysFails: true)
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 3)
        let result = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        #expect(result.delivered == false)
        #expect(result.attempts == 3)          // 有界，不无限重试
        #expect(result.shouldMarkNotified == false)   // 不虚记成功
        #expect(await sender.attemptCount == 3)
    }

    @Test func attemptLimitIsClampedToAtLeastOne() async {
        let sender = StubSender(alwaysFails: true)
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 0)
        let result = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        #expect(result.attempts == 1)
    }

    @Test func exhaustedRetriesLetAFutureEventTryAgain() async {
        let sender = StubSender(alwaysFails: true)
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 2)
        _ = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        // 未送达返回 shouldMarkNotified=false，调用方据此清掉档位记录以便日后重试。
        let second = await dispatcher.dispatch(identifier: "x", title: "t", body: "b")
        #expect(second.shouldMarkNotified == false)
        #expect(await sender.attemptCount == 4)
    }

    @Test func notificationIdentifiersAreStableAndDistinctPerMetric() {
        let cpu = ProcessAlertCenter.notificationIdentifier(appKey: "Safari", metric: .cpu)
        let memory = ProcessAlertCenter.notificationIdentifier(appKey: "Safari", metric: .memory)
        #expect(cpu == ProcessAlertCenter.notificationIdentifier(appKey: "Safari", metric: .cpu))
        #expect(cpu != memory)
        #expect(ProcessAlertCenter.stateKey(appKey: "Safari", metric: .cpu) !=
                ProcessAlertCenter.stateKey(appKey: "Safari", metric: .memory))
    }
}
