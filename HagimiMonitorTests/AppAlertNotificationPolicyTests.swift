import Foundation
import Testing
@testable import HagimiMonitorDirect

/// N01–N03：通知策略不得把普通高占用写成系统压力，不得风暴，也不得绕过总开关。
/// 这里验证决策函数，不发送真实通知。
struct AppAlertNotificationPolicyTests {
    @Test func regularHighUsageWithoutSystemPressureDoesNotNotify() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: SystemPressureSnapshot(memoryLevel: 0, thermalLevel: 0, hasValidObservation: true),
            tier: 1,
            alreadyNotifiedTier: nil
        )
        #expect(decision == .skip(reason: .noConcurrentSystemPressure))
    }

    @Test func unknownPressureIsNotTreatedAsNormal() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: .unknown,
            tier: 1,
            alreadyNotifiedTier: nil
        )
        // 没有有效观测时既不判定为压力，也不发通知。
        #expect(decision == .skip(reason: .noConcurrentSystemPressure))
    }

    @Test func confirmedHighUsageWithConcurrentPressureNotifies() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: SystemPressureSnapshot(memoryLevel: 1, thermalLevel: 0, hasValidObservation: true),
            tier: 1,
            alreadyNotifiedTier: nil
        )
        #expect(decision == .send(tier: 1))
    }

    @Test func unconfirmedEventDoesNotNotify() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: false,
            systemPressure: SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true),
            tier: 1,
            alreadyNotifiedTier: nil
        )
        #expect(decision == .skip(reason: .belowSustainThreshold))
    }

    @Test func notificationsDisabledAlwaysSkips() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: false,
            isConfirmed: true,
            systemPressure: SystemPressureSnapshot(memoryLevel: 3, thermalLevel: 3, hasValidObservation: true),
            tier: 2,
            alreadyNotifiedTier: nil
        )
        #expect(decision == .skip(reason: .notificationsDisabled))
    }

    @Test func sameTierDoesNotNotifyTwice() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true),
            tier: 1,
            alreadyNotifiedTier: 1
        )
        #expect(decision == .skip(reason: .alreadyNotified))
    }

    @Test func severityEscalationSendsBoundedUpdate() {
        let decision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true),
            tier: 2,
            alreadyNotifiedTier: 1
        )
        #expect(decision == .update(tier: 2))
    }

    @Test func cooldownBlocksNewNotificationButAllowsSameEpisodeEscalation() {
        let pressure = SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true)
        let newDecision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: pressure,
            tier: 1,
            alreadyNotifiedTier: nil,
            inCooldown: true
        )
        #expect(newDecision == .skip(reason: .inCooldown))

        let escalationDecision = AppAlertNotificationPolicy.decide(
            notificationsEnabled: true,
            isConfirmed: true,
            systemPressure: pressure,
            tier: 2,
            alreadyNotifiedTier: 1,
            inCooldown: true
        )
        #expect(escalationDecision == .update(tier: 2))
    }

    @Test func tierUsesRelativeExceedanceAboveThreshold() {
        // CPU 门槛随逻辑核数自适应：刚好达标为 1 档，超过两倍为 2 档。
        let cpuThreshold = StatisticsMetricDefinition.attentionThreshold(
            for: .cpu,
            logicalCoreCount: StatisticsMetricDefinition.logicalCoreCount()
        )?.value ?? StatisticsMetricDefinition.cpuAttentionFloor
        #expect(AppAlertNotificationPolicy.tier(metric: .cpu, rawValue: cpuThreshold) == 1)
        #expect(AppAlertNotificationPolicy.tier(metric: .cpu, rawValue: cpuThreshold * 2 - 1) == 1)
        #expect(AppAlertNotificationPolicy.tier(metric: .cpu, rawValue: cpuThreshold * 2) == 2)
        // 网络门槛约 20 MiB/s。
        #expect(AppAlertNotificationPolicy.tier(metric: .network, rawValue: 20 * StatisticsMetricDefinition.mebibyte) == 1)
        #expect(AppAlertNotificationPolicy.tier(metric: .network, rawValue: 50 * StatisticsMetricDefinition.mebibyte) == 2)
    }

    @Test func memoryTierScalesWithPhysicalCapacity() {
        let physical = StatisticsMetricDefinition.physicalMemoryBytes() ?? 0
        let threshold = max(StatisticsMetricDefinition.memoryAttentionFloor, physical * 0.2)
        #expect(AppAlertNotificationPolicy.tier(metric: .memory, rawValue: threshold) == 1)
        #expect(AppAlertNotificationPolicy.tier(metric: .memory, rawValue: threshold * 2) == 2)
    }
}

/// 集成面：告警中心在无同期压力时不发送通知，但界面记录仍然更新。
@MainActor
struct ProcessAlertNotificationGateTests {
    actor RecordingSender: AppAlertNotificationSending {
        private(set) var sentIdentifiers: [String] = []
        func send(identifier: String, title: String, body: String) async throws {
            sentIdentifiers.append(identifier)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private var cpuThreshold: Double {
        StatisticsMetricDefinition.attentionThreshold(
            for: .cpu,
            logicalCoreCount: StatisticsMetricDefinition.logicalCoreCount()
        )?.value ?? StatisticsMetricDefinition.cpuAttentionFloor
    }

    private func cpu(_ name: String, _ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: name, pid: 200, usage: usage)]
    }

    @Test func confirmedEventIsRecordedEvenWhenNotificationIsSkipped() {
        let center = ProcessAlertCenter()
        center.updateSystemPressure(SystemPressureSnapshot(memoryLevel: 0, thermalLevel: 0, hasValidObservation: true))
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", cpuThreshold + 10), memory: [], gpu: [], network: [], at: at(offset))
        }
        // 通知被跳过，但事件照常进入展示列表。
        let episode = try? #require(center.activeAlerts.first)
        #expect(episode?.notified == false)
        #expect(episode?.continuousHighSeconds == 120)
    }

    @Test func cpuBelowAdaptiveThresholdDoesNotTriggerEpisode() {
        let center = ProcessAlertCenter()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", max(0, cpuThreshold - 1)), memory: [], gpu: [], network: [], at: at(offset))
        }
        #expect(center.activeAlerts.isEmpty)
        #expect(center.recentAlerts.isEmpty)
    }

    @Test func fairThermalDoesNotCountAsElevatedSystemPressure() {
        let fairOnly = SystemPressureSnapshot(memoryLevel: 0, thermalLevel: 1, hasValidObservation: true)
        #expect(fairOnly.hasElevatedPressure == false)

        let seriousThermal = SystemPressureSnapshot(memoryLevel: 0, thermalLevel: 2, hasValidObservation: true)
        #expect(seriousThermal.hasElevatedPressure == true)
    }

    @Test func pressureSnapshotSeverityReflectsWorstChannel() {
        let snapshot = SystemPressureSnapshot(memoryLevel: 1, thermalLevel: 3, hasValidObservation: true)
        #expect(snapshot.severity == 3)
        #expect(snapshot.hasElevatedPressure)
        #expect(SystemPressureSnapshot.unknown.hasElevatedPressure == false)
    }

    @Test func ignoredAppsFilterActiveListAndSuppressNotifications() async throws {
        let sender = RecordingSender()
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 1)
        let center = ProcessAlertCenter(notificationDispatcher: dispatcher)
        center.updateNotificationPreferences(enabled: true, highLoadAppEnabled: true)
        center.updateSystemPressure(SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true))
        center.updateIgnoredApps([
            AlertIgnoredApp(id: "Heavy", displayName: "Heavy", bundleIdentifier: nil)
        ])

        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", cpuThreshold + 20), memory: [], gpu: [], network: [], at: at(offset))
        }
        try await Task.sleep(for: .milliseconds(30))

        // 白名单应用不出现在活跃列表、不发通知，但移除忽略后可见 underlying 观测仍在。
        #expect(center.activeAlerts.isEmpty)
        #expect(center.activeAppGroups.isEmpty)
        #expect(await sender.sentIdentifiers.isEmpty)

        center.updateIgnoredApps([])
        #expect(center.activeAppGroups.count == 1)
        #expect(center.activeAppGroups.first?.episodes.first?.notified == false)
    }

    @Test func disabledHighLoadCategorySuppressesNotificationWhileKeepingObservation() async throws {
        let sender = RecordingSender()
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 1)
        let center = ProcessAlertCenter(notificationDispatcher: dispatcher)
        center.updateNotificationPreferences(enabled: true, highLoadAppEnabled: false)
        center.updateSystemPressure(SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true))

        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", cpuThreshold + 20), memory: [], gpu: [], network: [], at: at(offset))
        }
        try await Task.sleep(for: .milliseconds(30))

        #expect(center.activeAlerts.count == 1)
        #expect(center.activeAlerts.first?.notified == false)
        #expect(await sender.sentIdentifiers.isEmpty)
    }

    @Test func crossEpisodeNotificationCooldownSuppressesImmediateRepeatAlert() async throws {
        let sender = RecordingSender()
        let dispatcher = AppAlertNotificationDispatcher(sender: sender, maxAttempts: 1)
        let center = ProcessAlertCenter(notificationDispatcher: dispatcher)
        center.updateNotificationPreferences(enabled: true, highLoadAppEnabled: true)
        center.updateSystemPressure(SystemPressureSnapshot(memoryLevel: 2, thermalLevel: 0, hasValidObservation: true))

        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", cpuThreshold + 20), memory: [], gpu: [], network: [], at: at(offset))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await sender.sentIdentifiers.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sender.sentIdentifiers.count == 1)
        #expect(center.activeAlerts.first?.notified == true)

        // 恢复后 5 分钟内再次持续高负载：处于 15 分钟冷却期内，不重复发送通知。
        center.ingest(cpu: cpu("Heavy", 5), memory: [], gpu: [], network: [], at: at(180))
        for offset in [300.0, 360.0, 420.0] {
            center.ingest(cpu: cpu("Heavy", cpuThreshold + 20), memory: [], gpu: [], network: [], at: at(offset))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(center.activeAlerts.first?.notified == false)
        #expect(await sender.sentIdentifiers.count == 1)
    }
}
