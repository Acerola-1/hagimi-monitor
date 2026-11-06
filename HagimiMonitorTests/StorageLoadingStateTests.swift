import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct StorageLoadingStateTests {
    @Test func failedOpenIsDistinctFromEmptyDatabaseAndExplicitRetryRecovers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hagimi-storage-state-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("statistics.sqlite3")
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = StatisticsRecorder(databaseURL: databaseURL,
            processStoreDirectory: root.appendingPathComponent("process"),
            processAlertCenter: ProcessAlertCenter(), recordingEnabled: false)
        #expect(recorder.storageInfo == nil)
        await withCheckedContinuation { continuation in
            recorder.loadOverview { continuation.resume() }
        }
        #expect(recorder.storageReadFailed)
        #expect(recorder.storageInfo == nil)
        #expect(recorder.reportDataProvider().loadMetricRows(now: Date()) == nil)

        try FileManager.default.removeItem(at: databaseURL)
        await withCheckedContinuation { continuation in
            recorder.loadOverview { continuation.resume() }
        }
        #expect(!recorder.storageReadFailed)
        #expect(recorder.storageInfo != nil)
        #expect(recorder.recordDays == 0)
        let rows = try #require(recorder.reportDataProvider().loadMetricRows(now: Date()))
        #expect(rows.minutes.isEmpty)
        #expect(rows.hours.isEmpty)
        #expect(rows.days.isEmpty)
        let database = StatisticsDatabase(url: databaseURL)
        database.insertMinuteRow(StatisticsRow(t: Int64(Date().timeIntervalSince1970), n: 1))
        await withCheckedContinuation { continuation in
            recorder.loadOverview { continuation.resume() }
        }
        #expect(recorder.recordDays > 0)
        #expect(!recorder.storageReadFailed)

    }
}
