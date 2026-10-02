import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 1.4：基线探针复现的三个错误，在修复后必须不再出现。
///
/// 基线输出（2026-10-01，旧实现）：
///  - `two_samples_elapsed_60s_reported_minutes=2`（两次相隔 60 秒被算成两分钟）
///  - `after_59_minute_gap_start_preserved=true`（59 分钟缺口后旧事件被接续）
///  - `true_1MiB_per_second_network_alerts=1, shown_average=60`（1 MiB/s 被放大 60 倍并报警）
@MainActor
struct BaselineRegressionProbeTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset) }

    private func cpu(_ usage: Double) -> [(name: String, pid: pid_t, usage: Double)] {
        [(name: "AuditCPU", pid: 0, usage: usage)]
    }

    @Test func twoSamplesSixtySecondsApartAreNotReportedAsTwoMinutes() {
        let center = ProcessAlertCenter()
        center.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(0))
        center.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(60))
        // 旧实现报 2 分钟；现在两次瞬时观测只证明 60 秒，未达 120 秒资格，
        // 因此不进入展示列表，也不虚报时长。
        #expect(center.activeAlerts.isEmpty)
    }

    @Test func fiftyNineMinuteGapDoesNotExtendTheOldEvent() {
        let center = ProcessAlertCenter()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            center.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(offset))
        }
        // 59 分钟后回来：旧事件以中断结束，新样本建立新基线，缺口不被补入。
        center.ingest(cpu: cpu(70), memory: [], gpu: [], network: [], at: at(3600))
        let finished = center.recentAlerts.first
        #expect(finished?.endReason == .observationGap)
        #expect((finished?.continuousHighSeconds ?? 0) < 200)
        #expect(finished?.endedAt == at(120))
    }

    @Test func oneMiBPerSecondIsNotAmplifiedIntoAnAlert() {
        let center = ProcessAlertCenter()
        // 真实 1 MiB/s 速率，两拍。
        for offset in [0.0, 60.0] {
            center.ingest(
                cpu: [], memory: [], gpu: [],
                network: [(name: "AuditNetwork", pid: 0, downBytes: 1_048_576, upBytes: 0)],
                at: at(offset)
            )
        }
        // 旧实现把速率乘 60 后再当速率用，触发 20 MiB/s 门槛并显示 averageUsage=60。
        #expect(center.activeAlerts.isEmpty)
        #expect(center.recentAlerts.isEmpty)
    }
}
