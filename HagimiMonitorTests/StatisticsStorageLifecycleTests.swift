import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct StatisticsStorageLifecycleTests {
    @Test func disabledMonitorStoreStartupAndSettingCallbacksDoNotCreateStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "StatisticsStorageLifecycleTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "settings.statistics.enabled")
        defaults.set([MonitorKind.cpu.rawValue], forKey: "settings.visibleKinds")
        let settings = MonitorSettings(defaults: defaults)
        let recorder = StatisticsRecorder(databaseURL: root.appendingPathComponent("metrics.sqlite3"),
            processStoreDirectory: root.appendingPathComponent("processes"),
            processAlertCenter: ProcessAlertCenter(), recordingEnabled: settings.statisticsEnabled)
        let store = MonitorStore(settings: settings, statisticsRecorder: recorder)
        #expect(store.statisticsRecorder === recorder)
        #expect(recorder.hasStorageBacking)
        #expect(!FileManager.default.fileExists(atPath: root.path),
            "MonitorStore 启动检查不能触发建库")

        // Published 会发送同值赋值，覆盖已订阅的关闭回调及第二处配置 guard。
        settings.statisticsEnabled = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: root.path),
            "关闭状态的设置回调与正常采样不能触发建库")

        // 开启经过 MonitorStore 的订阅，存储维护随后在后台完成。
        settings.statisticsEnabled = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while recorder.storageInfo == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(recorder.storageInfo != nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("metrics.sqlite3").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("processes/AppStats.sqlite").path))
        settings.statisticsEnabled = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.reportDataProvider().loadMetricRows(now: Date()) != nil,
            "经过生产开关再次暂停后仍可读取历史")
    }

    @Test func disabledRecorderDefersStorageUntilHistoryIsRequested() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = root.appendingPathComponent("metrics.sqlite3")
        let processes = root.appendingPathComponent("processes")
        let recorder = StatisticsRecorder(databaseURL: database, processStoreDirectory: processes,
            recordingEnabled: false)
        recorder.record(modules: [.placeholder(kind: .cpu)], fans: [], freshKinds: [.cpu], at: Date())
        try await Task.sleep(for: .milliseconds(50))
        #expect(!FileManager.default.fileExists(atPath: root.path),
            "关闭记录且未查看历史时，不应创建任何数据库文件")

        // 暂停记录不妨碍查看历史；读取入口按需初始化存储。
        let rows = recorder.reportDataProvider().loadMetricRows(now: Date())
        #expect(rows != nil)
        #expect(FileManager.default.fileExists(atPath: database.path))
        #expect(FileManager.default.fileExists(atPath: processes.appendingPathComponent("AppStats.sqlite").path))
        #expect(rows?.minutes.isEmpty == true)

        recorder.resume()
        await withCheckedContinuation { continuation in
            recorder.loadOverview { continuation.resume() }
        }
        recorder.suspend()
        #expect(recorder.reportDataProvider().loadMetricRows(now: Date()) != nil,
            "再次暂停仍应保留历史读取能力")
    }
}
