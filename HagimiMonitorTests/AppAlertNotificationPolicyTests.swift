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

    @Test func tierUsesRelativeExceedanceAboveThreshold() {
        // CPU 门槛 60%：刚好达标为 1 档，超过两倍为 2 档。
        #expect(AppAlertNotificationPolicy.tier(metric: .cpu, rawValue: 60) == 1)
        #expect(AppAlertNotificationPolicy.tier(metric: .cpu, rawValue: 130) == 2)
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
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func cpu(_ name: String, _ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: name, pid: 200, usage: usage)]
    }

    @Test func confirmedEventIsRecordedEvenWhenNotificationIsSkipped() {
        let center = ProcessAlertCenter()
        center.updateSystemPressure(SystemPressureSnapshot(memoryLevel: 0, thermalLevel: 0, hasValidObservation: true))
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        // 通知被跳过，但事件照常进入展示列表。
        let episode = try? #require(center.activeAlerts.first)
        #expect(episode?.notified == false)
        #expect(episode?.continuousHighSeconds == 120)
    }

    @Test func pressureSnapshotSeverityReflectsWorstChannel() {
        let snapshot = SystemPressureSnapshot(memoryLevel: 1, thermalLevel: 3, hasValidObservation: true)
        #expect(snapshot.severity == 3)
        #expect(snapshot.hasElevatedPressure)
        #expect(SystemPressureSnapshot.unknown.hasElevatedPressure == false)
    }
}
