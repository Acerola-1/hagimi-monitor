import Foundation
import Testing
@testable import HagimiMonitorDirect

/// A03：速率型指标的区间总量按真实采样间隔积分，不使用固定乘数。
/// 间隔计算是纯函数，这里直接验证边界，不依赖落库。
@MainActor
struct ProcessSampleIntervalTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func firstSampleHasNoIntegrableInterval() {
        // 首次采样没有可积分的区间：不应凭空产生一分钟的累计量。
        #expect(StatisticsRecorder.sampleInterval(previous: nil, at: t0) == 0)
    }

    @Test func normalPerMinuteCadenceIntegratesSixtySeconds() {
        let previous = t0
        let now = t0.addingTimeInterval(60)
        #expect(StatisticsRecorder.sampleInterval(previous: previous, at: now) == 60)
    }

    @Test func intervalCapSitsAboveThePerMinuteSchedule() {
        // 上限必须大于每分钟排期，否则每次正常采样都会被判为越界而完全不积分。
        #expect(StatisticsRecorder.processSampleIntegrationCap > 60)
        #expect(StatisticsRecorder.processSampleIntegrationCap <= 180)
    }

    @Test func sleepSizedGapContributesNothing() {
        let previous = t0
        // 一小时后才回来：间隔越界，不积分，避免把睡眠时长算成流量。
        #expect(StatisticsRecorder.sampleInterval(previous: previous, at: t0.addingTimeInterval(3600)) == 0)
    }

    @Test func clockGoingBackwardsDoesNotIntegrate() {
        let previous = t0.addingTimeInterval(60)
        #expect(StatisticsRecorder.sampleInterval(previous: previous, at: t0) == 0)
    }

    @Test func slightScheduleJitterStillIntegrates() {
        let previous = t0
        // 排期抖动（65 秒）仍应积分真实间隔，而不是退回固定 60。
        #expect(StatisticsRecorder.sampleInterval(previous: previous, at: t0.addingTimeInterval(65)) == 65)
    }

    @Test func lowRateOverRealIntervalDoesNotBecomeHighUsage() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        let start = Date()
        for index in 0..<3 {
            recorder.recordProcesses(cpu: [], memory: [], gpu: [], network: [
                TopNetworkProcess(pid: 1, name: "Slow", download: 1_048_576, upload: 0, icon: nil)
            ], disk: [], at: start.addingTimeInterval(Double(index) * 60))
        }
        // 1 MiB/s 远低于 20 MiB/s 门槛，按真实间隔积分后依然在关注范围之外。
        #expect(alerts.activeAlerts.isEmpty)
        recorder.suspend()
    }
}

/// A02 / E06：批次门卫。空批次不恢复其他维度、重复批次只计一次、
/// 唤醒后重新建立基线，关闭记录期间的在途回调被丢弃。
@MainActor
struct ProcessBatchGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func makeRecorder() -> (StatisticsRecorder, ProcessAlertCenter) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        return (recorder, alerts)
    }

    /// recordProcesses 接受真实的 TopCPUProcess 值类型。
    private func cpu(_ name: String, _ usage: Double) -> [TopCPUProcess] {
        [TopCPUProcess(pid: 300, name: name, cpuUsage: usage, icon: nil, translated: false)]
    }

    private var highCPU: Double {
        (StatisticsMetricDefinition.attentionThreshold(
            for: .cpu,
            logicalCoreCount: StatisticsMetricDefinition.logicalCoreCount()
        )?.value ?? StatisticsMetricDefinition.cpuAttentionFloor) + 10
    }

    @Test func duplicateBatchAtSameTimestampCountsOnce() {
        let (recorder, alerts) = makeRecorder()
        // 同一次采样被投递两次：第二次必须被丢弃，否则时长会翻倍。
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(offset))
            recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(offset))
        }
        let episode = try? #require(alerts.activeAlerts.first)
        #expect(episode?.continuousHighSeconds == 120)
        #expect(episode?.observationCount == 3)
        recorder.suspend()
    }

    @Test func callbacksAfterSuspendAreDropped() {
        let (recorder, alerts) = makeRecorder()
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(offset))
        }
        recorder.suspend()
        // 关闭记录后在途回调到达：不得继续累计。
        recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(180))
        let episode = try? #require(alerts.activeAlerts.first)
        #expect(episode?.continuousHighSeconds == 120)
    }

    @Test func outOfOrderBatchIsIgnored() {
        let (recorder, alerts) = makeRecorder()
        recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(120))
        recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(60))
        recorder.recordProcesses(cpu: cpu("Heavy", highCPU), memory: [], gpu: [], network: [], disk: [], at: at(180))
        let episode = try? #require(alerts.activeAlerts.first)
        // 60 秒那拍被丢弃，只有 120 与 180 两拍计入 60 秒，未达资格。
        #expect(episode == nil)
        recorder.suspend()
    }

    @Test func interleavedFastAndNetworkPipelinesKeepIndependentCursorsAndMetrics() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        defer { recorder.suspend() }

        let networkSample = [TopNetworkProcess(pid: 301, name: "Downloader", download: 1_000_000, upload: 0, icon: nil)]
        for offset in stride(from: 0.0, through: 120.0, by: 60.0) {
            recorder.recordProcesses(
                cpu: cpu("Heavy", highCPU),
                memory: [],
                gpu: [],
                network: [],
                disk: [],
                at: at(offset),
                providedMetrics: [.cpu, .memory, .gpu]
            )
            // 仅隔 200ms 到达的网络采样不得消费掉 CPU/快样本的时间间隔，也不得打断/推进 CPU 事件。
            recorder.recordProcesses(
                cpu: [],
                memory: [],
                gpu: [],
                network: networkSample,
                disk: [],
                at: at(offset + 0.2),
                providedMetrics: [.network]
            )
        }

        // 再来一拍纯网络批次：CPU 的 lastSeenAt 不得被虚推，也不会误判恢复或中断。
        recorder.recordProcesses(
            cpu: [],
            memory: [],
            gpu: [],
            network: networkSample,
            disk: [],
            at: at(150),
            providedMetrics: [.network]
        )

        let episode = try #require(alerts.activeAlerts.first)
        #expect(episode.metric == .cpu)
        #expect(episode.continuousHighSeconds == 120)
        #expect(episode.lastSeenAt == at(120))

        recorder.processStore?.flushSynchronously()
        let day = StatisticsProcessStore.dayKey(at(0), calendar: .current)
        let topNet = recorder.processStore?.topApps(fromDay: day, toDay: day, category: .network) ?? []
        let downloaderBytes = topNet.first(where: { $0.name == "Downloader" })?.value ?? 0
        // 共 4 次纯网络采样包含 3 个间隔（60s + 60s + 29.8s ≈ 149.8 MB），而不是每次都被 200ms 前的快样本打断（~0.2 MB）。
        #expect(downloaderBytes > 100_000_000)
    }
}

/// 网络探针三态结果（首拍建基线 / 有效空榜 / 探针失败）与统计通道集成契约：
/// 探针失败不得推进时间基线，也不得把多窗口平均速率错当单窗口积分或误触发高负载事件收敛。
@MainActor
struct NetworkSampleOutcomeTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func nettopCSV(downloadBytes: UInt64, uploadBytes: UInt64 = 0) -> String {
        "time,bytes_in,bytes_out\nSyntheticNet.999999,\(downloadBytes),\(uploadBytes)\n"
    }

    private func makeRecorder() -> (root: URL, recorder: StatisticsRecorder, alerts: ProcessAlertCenter) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        return (root, recorder, alerts)
    }

    private func replayOutcome(
        _ outcome: NetworkSampleOutcome,
        into recorder: StatisticsRecorder
    ) {
        switch outcome {
        case .failed:
            return
        case .baselineEstablished(let sampledAt):
            recorder.establishNetworkBaseline(at: sampledAt)
        case .sampled(let raw, let sampledAt):
            let network = raw.map {
                TopNetworkProcess(
                    pid: $0.pid,
                    name: $0.name,
                    download: Int(clamping: $0.download),
                    upload: Int(clamping: $0.upload),
                    icon: nil
                )
            }
            recorder.recordProcesses(
                cpu: [],
                memory: [],
                gpu: [],
                network: network,
                disk: [],
                at: sampledAt,
                providedMetrics: [.network]
            )
        }
    }

    @Test func cursorDistinguishesBaselineFailureAndEmptyDeltaWithoutMovingBaselineOnFailure() {
        let cursor = NetworkDeltaCursor()

        guard case .baselineEstablished(let baselineAt) = cursor.consume(
            csvOutput: nettopCSV(downloadBytes: 1_000),
            at: at(0),
            limit: 5,
            includeSystemProcesses: true
        ) else {
            Issue.record("首帧有效输出应返回 .baselineEstablished")
            return
        }
        #expect(baselineAt == at(0))

        // 探针失败（nil 或空串）返回 .failed，且不得改动先前记录在 at(0) 的快照与时间基线。
        if case .failed = cursor.consume(csvOutput: nil, at: at(5), limit: 5, includeSystemProcesses: true) {
        } else {
            Issue.record("nil 输出应返回 .failed")
        }
        if case .failed = cursor.consume(csvOutput: "", at: at(8), limit: 5, includeSystemProcesses: true) {
        } else {
            Issue.record("空输出应返回 .failed")
        }

        // 第 10 秒恢复正常且累计涨到 10_000 字节：应按 t=0→t=10 (9000 / 10 = 900 B/s) 计算速率。
        guard case .sampled(let sampled, let sampledAt) = cursor.consume(
            csvOutput: nettopCSV(downloadBytes: 10_000),
            at: at(10),
            limit: 5,
            includeSystemProcesses: true
        ) else {
            Issue.record("失败后的首帧有效输出应基于原基线返回 .sampled")
            return
        }
        #expect(sampledAt == at(10))
        #expect(sampled.count == 1)
        #expect(sampled.first?.download == 900)

        // 合法空榜：delta 为 0 时返回 .sampled([]) 而非 .failed。
        guard case .sampled(let emptySample, _) = cursor.consume(
            csvOutput: nettopCSV(downloadBytes: 10_000),
            at: at(20),
            limit: 5,
            includeSystemProcesses: true
        ) else {
            Issue.record("零增量的有效采集应返回 .sampled([])")
            return
        }
        #expect(emptySample.isEmpty)

        // 墙钟未前进或回拨（dt <= 0）返回 .failed，避免按空榜推进下游状态。
        if case .failed = cursor.consume(
            csvOutput: nettopCSV(downloadBytes: 20_000),
            at: at(15),
            limit: 5,
            includeSystemProcesses: true
        ) {
        } else {
            Issue.record("墙钟回拨应返回 .failed")
        }
    }

    @Test func failedProbePreservesGapProtectionInsteadOfHalfIntegratingAcrossTwoWindows() {
        let (root, recorder, _) = makeRecorder()
        defer {
            recorder.suspend()
            try? FileManager.default.removeItem(at: root)
        }
        let cursor = NetworkDeltaCursor()

        // t = 0s: 建立游标与记录器基线
        replayOutcome(
            cursor.consume(csvOutput: nettopCSV(downloadBytes: 0), at: at(0), limit: 5, includeSystemProcesses: true),
            into: recorder
        )
        // t = 60s: nettop 失败 → 不得推进 StatisticsRecorder 的网络时间基线
        replayOutcome(
            cursor.consume(csvOutput: nil, at: at(60), limit: 5, includeSystemProcesses: true),
            into: recorder
        )
        // t = 120s: nettop 恢复，120s 内累计 120_000_000 B (均值 1_000_000 B/s)；
        // 因记录器基线仍停在 t=0s，120s 超过 processSampleIntegrationCap(90s)，触发断档保护，
        // 避免误按 1_000_000 B/s × 60s 将真实流量腰斩落库。
        replayOutcome(
            cursor.consume(csvOutput: nettopCSV(downloadBytes: 120_000_000), at: at(120), limit: 5, includeSystemProcesses: true),
            into: recorder
        )
        // t = 180s: 正常 60s 窗口增量 60_000_000 B → 精确积分 60_000_000 B。
        replayOutcome(
            cursor.consume(csvOutput: nettopCSV(downloadBytes: 180_000_000), at: at(180), limit: 5, includeSystemProcesses: true),
            into: recorder
        )

        recorder.processStore?.flushSynchronously()
        let day = StatisticsProcessStore.dayKey(at(0), calendar: .current)
        let topNet = recorder.processStore?.topApps(fromDay: day, toDay: day, category: .network) ?? []
        let syntheticBytes = topNet.first(where: { $0.name == "SyntheticNet" })?.value ?? 0
        #expect(syntheticBytes == 60_000_000)
    }

    @Test func emptySampleEndsAlertWhileFailedProbeDoesNotTriggerUnobservedTimeout() throws {
        let (root, recorder, alerts) = makeRecorder()
        defer {
            recorder.suspend()
            try? FileManager.default.removeItem(at: root)
        }
        let cursor = NetworkDeltaCursor()

        // 连续高于 20 MiB/s 门槛 (25_000_000 B/s) 触发确认高负载事件
        let rateBytesPerSecond: UInt64 = 25_000_000
        for (index, second) in [0, 60, 120, 180].enumerated() {
            let total = rateBytesPerSecond * UInt64(index * 60)
            replayOutcome(
                cursor.consume(csvOutput: nettopCSV(downloadBytes: total), at: at(TimeInterval(second)), limit: 5, includeSystemProcesses: true),
                into: recorder
            )
        }

        let active = try #require(alerts.activeAlerts.first)
        #expect(active.metric == .network)
        #expect(active.continuousHighSeconds == 120)

        // t = 300s 探针失败（超出 90s 未知容忍窗口）：因跳过上报，不能被误判为「观测到空榜并结束事件」
        replayOutcome(
            cursor.consume(csvOutput: nil, at: at(300), limit: 5, includeSystemProcesses: true),
            into: recorder
        )
        #expect(alerts.activeAlerts.count == 1)

        // t = 301s nettop 正常完成且确认为零增量有效空榜：显式 [.network] 推进未观测超时收敛
        let lastTotal = rateBytesPerSecond * 180
        replayOutcome(
            cursor.consume(csvOutput: nettopCSV(downloadBytes: lastTotal), at: at(301), limit: 5, includeSystemProcesses: true),
            into: recorder
        )
        #expect(alerts.activeAlerts.isEmpty)
        let finished = try #require(alerts.recentAlerts.first)
        #expect(finished.endReason == .observationGap)
    }
}
