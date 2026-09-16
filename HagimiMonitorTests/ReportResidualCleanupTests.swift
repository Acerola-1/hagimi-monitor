import Combine
import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
private final class ReportReadingsBox {
    var value: [String: String]

    init(value: [String: String]) {
        self.value = value
    }
}

@Suite("报表实时源门控")
@MainActor
struct ReportLiveHardwareSourceTests {
    @Test func hiddenAndNonHardwareModulesDoNotSample() {
        var calls = 0
        let source = ReportLiveHardwareSource(readingsProvider: { module in
            calls += 1
            return ["module": module.rawValue]
        })

        source.setActiveModule(.cpu)
        source.start()
        #expect(calls == 0)

        source.setWindowVisible(true)
        #expect(calls == 1)
        #expect(source.liveReadings == ["module": "cpu"])

        source.setWindowVisible(false)
        source.setActiveModule(.overview)
        #expect(calls == 1)
        #expect(source.liveReadings.isEmpty)

        source.setWindowVisible(true)
        source.setActiveModule(.gpu)
        #expect(calls == 2)
        #expect(source.liveReadings == ["module": "gpu"])

        source.stop()
    }

    @Test func unchangedSnapshotsAreNotPublishedAndResumeRefreshesImmediately() {
        let readings = ReportReadingsBox(value: ["value": "1"])
        var publications = 0
        let source = ReportLiveHardwareSource(readingsProvider: { _ in readings.value })
        let cancellable = source.$liveReadings.sink { _ in publications += 1 }
        defer { cancellable.cancel(); source.stop() }

        source.setActiveModule(.memory)
        source.start()
        source.setWindowVisible(true)
        let afterFirstSnapshot = publications

        source.pause()
        source.resume()
        #expect(publications == afterFirstSnapshot)

        readings.value = ["value": "2"]
        source.pause()
        source.resume()
        #expect(source.liveReadings == ["value": "2"])
        #expect(publications == afterFirstSnapshot + 1)
    }
}

@Suite("报表打印会话清理")
@MainActor
struct TransientReportPrintSessionTests {
    @Test func finishIsIdempotentAndRemovesTemporaryFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hagimi-print-test-\(UUID().uuidString).html")
        try Data("<html></html>".utf8).write(to: url)
        var finishCalls = 0
        let session = TransientReportPrintSession(
            fileURL: url,
            parentWindow: nil,
            webViewFactory: { nil },
            onFinish: { finishCalls += 1 }
        )

        session.start()
        session.finish()

        #expect(session.state == .finished)
        #expect(session.cleanupCount == 1)
        #expect(finishCalls == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(session.webView == nil)
        #expect(session.fileURL == nil)
    }
}

@Suite("独立 HTML 导出残留")
struct StandaloneHTMLReportExporterTests {
    @Test func writesRequestedTargetWithoutDeadHardwareLiveGroup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hagimi-report-export-" + UUID().uuidString, isDirectory: true)
        let target = directory.appendingPathComponent("nested/report.html")
        defer { try? FileManager.default.removeItem(at: directory) }

        let written = try StandaloneHTMLReportExporter.write(
            to: target,
            snapshot: (minutes: [], hours: [], days: []),
            meta: ["device": "Test Mac", "model": "Test Model", "direct": false]
        )
        let html = try String(contentsOf: target, encoding: .utf8)

        #expect(written == target)
        #expect(FileManager.default.fileExists(atPath: target.path))
        #expect(html.contains("window.__DATA__ ="))
        #expect(!html.contains("__HAGIMI_HARDWARE_LIVE__"))
        #expect(!html.contains("data-hw-scope"))
        #expect(!html.contains("hwLiveGroup"))
    }
}
