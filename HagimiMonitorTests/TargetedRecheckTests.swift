import Foundation
import Testing
@testable import HagimiMonitorDirect

/// E05 / 3.4：关注应用的有界定向复查。
///
/// 复查复用合法采样来源，只追踪少量活跃关注应用；复查失败不得被当作已恢复。
@MainActor
struct TargetedRecheckTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func cpu(_ name: String, _ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: name, pid: 500, usage: usage)]
    }

    private func confirm(_ center: ProcessAlertCenter, _ name: String) {
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu(name, 70), memory: [], gpu: [], network: [], at: at(offset))
        }
    }

    @Test func recheckListIsBounded() {
        let center = ProcessAlertCenter()
        // 建立多个进行中事件。
        for index in 0..<(ProcessAlertCenter.targetedRecheckLimit + 4) {
            for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
                center.ingest(
                    cpu: cpu("App\(index)", 70), memory: [], gpu: [], network: [],
                    at: at(offset + Double(index) * 0.1)
                )
            }
        }
        let needing = center.applicationsNeedingRecheck()
        // 上限存在，关注集合不会无界增长。
        #expect(needing.count <= ProcessAlertCenter.targetedRecheckLimit)
        #expect(needing.count > 0)
    }

    @Test func recheckListOnlyContainsRunningEvents() {
        let center = ProcessAlertCenter()
        confirm(center, "Heavy")
        #expect(center.applicationsNeedingRecheck().contains { $0.appKey == "Heavy" })

        // 可靠低值确认恢复后，不再需要复查。
        center.ingest(cpu: cpu("Heavy", 5), memory: [], gpu: [], network: [], at: at(180))
        #expect(center.applicationsNeedingRecheck().contains { $0.appKey == "Heavy" } == false)
    }

    @Test func recheckFailureDoesNotDeclareRecovery() {
        let center = ProcessAlertCenter()
        confirm(center, "Heavy")
        // 复查失败：不得推进有效证据，也不得宣告恢复。
        center.noteRecheckFailure(appKey: "Heavy", metric: .cpu, at: at(150))
        #expect(center.activeAlerts.count == 1)
        #expect(center.recentAlerts.isEmpty)
    }

    @Test func recheckFailureFollowedByGapEndsAsInterrupted() {
        let center = ProcessAlertCenter()
        confirm(center, "Heavy")
        center.noteRecheckFailure(appKey: "Heavy", metric: .cpu, at: at(150))
        // 超过允许间隔后仍以中断结束，而不是恢复。
        center.ingest(cpu: cpu("Other", 10), memory: [], gpu: [], network: [], at: at(600))
        #expect(center.recentAlerts.first?.state == .interrupted)
        #expect(center.recentAlerts.first?.endReason != .recovered)
    }

    @Test func recheckFailureForUnknownAppIsIgnored() {
        let center = ProcessAlertCenter()
        // 没有进行中事件时记录失败不应产生任何状态。
        center.noteRecheckFailure(appKey: "Ghost", metric: .cpu, at: at(0))
        #expect(center.activeAlerts.isEmpty)
        #expect(center.recentAlerts.isEmpty)
    }
}
