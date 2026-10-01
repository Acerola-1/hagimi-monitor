import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct StatisticsApplicationObservationTests {
    @Test func lowNetworkRateDoesNotBecomeHighUsageAfterRecording() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        let start = Date()
        for index in 0..<2 {
            recorder.recordProcesses(cpu: [], memory: [], gpu: [], network: [
                TopNetworkProcess(pid: 0, name: "Slow transfer", download: 1_048_576, upload: 0, icon: nil)
            ], disk: [], at: start.addingTimeInterval(Double(index) * 60))
        }
        #expect(alerts.activeAlerts.isEmpty)
        recorder.suspend()
    }

    @Test func highNetworkRateRetainsItsRateAndFormatsAsBytesPerSecond() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alerts = ProcessAlertCenter()
        let recorder = StatisticsRecorder(
            databaseURL: root.appendingPathComponent("statistics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: alerts
        )
        let start = Date()
        // 持续资格是 120 秒有效覆盖，因此需要三次间隔 60 秒的观测才会确认事件；
        // 两次只累计 60 秒，按新语义不应进入展示列表。
        for index in 0..<3 {
            recorder.recordProcesses(cpu: [], memory: [], gpu: [], network: [
                TopNetworkProcess(pid: 0, name: "Fast transfer", download: 25 * 1_048_576, upload: 0, icon: nil)
            ], disk: [], at: start.addingTimeInterval(Double(index) * 60))
        }
        let episode = try #require(alerts.activeAlerts.first)
        #expect(episode.metric == .network)
        // 原始值保留字节每秒,不折成 MiB,展示层再换算十进制单位。
        #expect(episode.averageUsage == 25 * StatisticsMetricDefinition.mebibyte)
        // 时长来自真实有效覆盖,不是采样次数。
        #expect(episode.continuousHighSeconds == 120)
        #expect(episode.observationCount == 3)
        #expect(StatisticsDisplayFormat.applicationObservationValue(episode.averageUsage, metric: episode.metric) == "26 MB/s")
        recorder.suspend()
    }

    @Test func displayKeepsMulticorePercentCapacityUnitsAndMissingValues() {
        #expect(StatisticsDisplayFormat.applicationObservationValue(240, metric: .cpu) == "240%")
        // 内存以原始字节计量:5.8 GiB 落在 4 GiB+ 段,不再是 8 GiB+。
        #expect(StatisticsDisplayFormat.applicationObservationValue(5.8 * StatisticsMetricDefinition.gibibyte, metric: .memory) == "5.8 GiB")
        #expect(StatisticsDisplayFormat.applicationObservationValue(512 * StatisticsMetricDefinition.mebibyte, metric: .memory) == "512 MiB")
        #expect(StatisticsDisplayFormat.applicationObservationValue(.nan, metric: .gpu) == "—")
        #expect(StatisticsDisplayFormat.applicationObservationValue(-1, metric: .network) == "—")
    }

    #if DEBUG
    @Test func previewDoesNotMutateSharedEventsOrReportInputs() {
        let center = ProcessAlertCenter.shared
        let activeIDs = center.activeAlerts.map(\.id)
        let recentIDs = center.recentAlerts.map(\.id)
        let fixtures = StatisticsApplicationFixture.make(scenario: "multi", at: Date())
        #expect(fixtures.count == 3)
        #expect(fixtures.first?.episodes.count == 2)
        #expect(center.activeAlerts.map(\.id) == activeIDs)
        #expect(center.recentAlerts.map(\.id) == recentIDs)
        #expect(StatisticsApplicationFixture.make(scenario: "empty", at: Date()).isEmpty)
    }
    #endif
}
