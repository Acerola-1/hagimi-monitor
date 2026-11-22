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
