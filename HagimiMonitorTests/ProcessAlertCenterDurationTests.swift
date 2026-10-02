import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 事件时长、恢复与中断语义：以告警中心为集成面，验证状态机接入后的可观察行为。
@MainActor
struct ProcessAlertCenterDurationTests {
    private func center() -> ProcessAlertCenter {
        let center = ProcessAlertCenter()
        // 直接注入统计开启/通知关闭的内部状态无法从外部设置，这里只验证
        // 与通知无关的时长与状态语义，避免在测试里发真实通知。
        return center
    }

    private func cpu(_ name: String, _ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: name, pid: 100, usage: usage)]
    }

    private func memory(_ name: String, _ bytes: Double) -> [(name: String, pid: pid_t, bytes: Double)] {
        [(name: name, pid: 100, bytes: bytes)]
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func twoSamplesOneMinuteApartDoNotBecomeTwoMinutes() {
        let center = center()
        center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(0))
        center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(60))

        // 未达到 120 秒持续资格：不进入展示列表，也不虚报两分钟。
        #expect(center.activeAlerts.isEmpty)
        #expect(center.recentAlerts.isEmpty)
    }

    @Test func confirmedEventExposesRealSecondsNotSampleCount() {
        let center = center()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        let episode = try? #require(center.activeAlerts.first)
        #expect(episode?.continuousHighSeconds == 120)
        #expect(episode?.durationMinutes == 2)
        #expect(episode?.observationCount == 3)
    }

    @Test func reliableLowUsageConfirmsRecoveryWithEvidence() {
        let center = center()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        #expect(center.activeAlerts.count == 1)

        // 同一来源给出可靠的低于门槛观测。
        center.ingest(cpu: cpu("Heavy", 5), memory: [], gpu: [], network: [], at: at(180))
        #expect(center.activeAlerts.isEmpty)
        let recent = try? #require(center.recentAlerts.first)
        #expect(recent?.state == .recovered)
        #expect(recent?.endReason == .recovered)
        #expect(recent?.endedAt == at(120))
    }

    @Test func missingAppInProvidedBatchDoesNotCountAsRecovery() {
        let center = center()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        // 本拍采集了 CPU，但 Heavy 不在前列：这是未观测，不是已恢复。
        center.ingest(cpu: cpu("Other", 10), memory: [], gpu: [], network: [], at: at(180))
        #expect(center.activeAlerts.count == 1)
        #expect(center.recentAlerts.isEmpty)

        // 超过允许间隔后以中断结束，而不是恢复。
        center.ingest(cpu: cpu("Other", 10), memory: [], gpu: [], network: [], at: at(600))
        let recent = try? #require(center.recentAlerts.first)
        #expect(recent?.state == .interrupted)
        #expect(recent?.endReason == .observationGap)
    }

    @Test func suspendInterruptsOngoingEvent() {
        let center = center()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        center.interruptAll(reason: .suspended, at: at(130))
        #expect(center.activeAlerts.isEmpty)
        #expect(center.recentAlerts.first?.state == .interrupted)
        #expect(center.recentAlerts.first?.endReason == .suspended)
    }

    @Test func networkBatchDoesNotImplyCpuRecovery() {
        let center = center()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: [], gpu: [], network: [], at: at(offset))
        }
        // 本拍只有网络结果，CPU 批次未提供 → 不能宣告 CPU 事件恢复。
        center.ingest(
            cpu: [], memory: [], gpu: [],
            network: [(name: "Other", pid: 1, downBytes: 1_000, upBytes: 0)],
            at: at(180)
        )
        #expect(center.activeAlerts.count == 1)
        #expect(center.activeAlerts.first?.metric == .cpu)
    }

    @Test func memoryAndCpuTrackSeparately() {
        let center = center()
        let physical = StatisticsMetricDefinition.physicalMemoryBytes() ?? 0
        let heavyMemory = max(StatisticsMetricDefinition.memoryAttentionFloor, physical * 0.2) + StatisticsMetricDefinition.gibibyte
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu("Heavy", 70), memory: memory("Heavy", heavyMemory), gpu: [], network: [], at: at(offset))
        }
        let metrics = Set(center.activeAlerts.map(\.metric))
        #expect(metrics.contains(.cpu))
        #expect(metrics.contains(.memory))
    }
}
