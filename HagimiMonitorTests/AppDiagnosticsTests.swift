import Foundation
import Testing
@testable import HagimiMonitor

@Suite("App Diagnostics Tests")
struct AppDiagnosticsTests {
    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HagimiMonitorDiagnosticsTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("AppLogStore writes messages")
    func appLogStoreWritesMessages() throws {
        let directory = try temporaryDirectory()
        let store = AppLogStore(baseDirectory: directory)

        store.info("hello diagnostics", category: "test")
        store.flush()

        let files = store.logFileURLs()
        #expect(files.contains { $0.lastPathComponent == "app.log" })
        let text = try String(contentsOf: directory.appendingPathComponent("Logs/app.log"), encoding: .utf8)
        #expect(text.contains("[info] [test] hello diagnostics"))
    }

    @Test("AppLogStore rotates oversized log")
    func appLogStoreRotatesOversizedLog() throws {
        let directory = try temporaryDirectory()
        let store = AppLogStore(baseDirectory: directory, maxFileSize: 80)

        store.info(String(repeating: "a", count: 100), category: "test")
        store.flush()
        store.info("after rotation", category: "test")
        store.flush()

        let files = store.logFileURLs().map(\.lastPathComponent)
        #expect(files.contains("app.log"))
        #expect(files.contains("app.1.log"))
    }

    @Test("Launch state tracker detects unexpected previous run")
    func launchStateTrackerDetectsUnexpectedPreviousRun() throws {
        let directory = try temporaryDirectory()
        let tracker = AppLaunchStateTracker(baseDirectory: directory)

        #expect(tracker.markLaunch() == false)
        #expect(tracker.markLaunch() == true)
        tracker.markCleanExit()
        #expect(tracker.markLaunch() == false)
    }

    @Test("AppLogExporter creates diagnostics folder")
    func appLogExporterCreatesDiagnosticsFolder() throws {
        let base = try temporaryDirectory()
        let output = try temporaryDirectory("output")
        let store = AppLogStore(baseDirectory: base)
        let tracker = AppLaunchStateTracker(baseDirectory: base)
        _ = tracker.markLaunch()
        store.error("sample failure", category: "sampler")
        store.flush()

        let exporter = AppLogExporter(configuration: .init(
            outputDirectory: output,
            appLogStore: store,
            launchStateTracker: tracker,
            dateProvider: { Date(timeIntervalSince1970: 1_800_000_000) },
            compress: false
        ))

        let url = try exporter.export()
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("README.txt").path))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("metadata.json").path))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("logs/app.log").path))
    }
}
