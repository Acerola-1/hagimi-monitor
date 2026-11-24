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

@Suite("原生多格式导出服务")
struct NativeReportExportServiceTests {
    private func sampleModel() -> (model: ReportActiveRangeModel, meta: ReportMeta) {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var row = StatisticsRow(t: Int64(now.timeIntervalSince1970) - 3600, n: 60)
        row.cpuAvg = 22.5
        row.cpuMax = 48.0
        row.gpuAvg = 15.0
        row.memPctAvg = 64.0
        row.memPressureAvg = 18.0
        row.coverS = 3600

        let meta = ReportMeta(
            deviceName: "Test Mac",
            modelName: "Mac16,1",
            osVersion: "macOS 27.0",
            recordDays: 7,
            appVersion: "1.6.1",
            isDirect: true
        )
        let snapshot = ReportSnapshot(
            capturedAt: now,
            meta: meta,
            minutes: [],
            hours: [row],
            days: [],
            process: nil,
            hardware: nil,
            systemSleepIntervals: []
        )
        let model = ReportDataAggregator.aggregate(snapshot: snapshot, range: .week, now: now)
        return (model, meta)
    }

    @Test func markdownAndJSONExportsIncludeCommittedRangeAndScopeNote() throws {
        let (model, meta) = sampleModel()

        let md = ReportExportService.generateMarkdownReport(model: model, meta: meta)
        #expect(md.contains("Test Mac"))
        #expect(md.contains(model.range.label))
        #expect(md.contains("22.5%"))

        let jsonData = try ReportExportService.generateJSONReport(model: model, meta: meta)
        let jsonText = try #require(String(data: jsonData, encoding: .utf8))
        #expect(jsonText.contains("committedRange"))
        #expect(jsonText.contains("scopeNote"))
        #expect(jsonText.contains("Test Mac"))
    }

    @Test @MainActor func pdfRenderProducesValidPDFDocument() {
        let (model, meta) = sampleModel()
        let data = ReportExportService.renderPDFData(model: model, meta: meta, hardware: nil)
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(data.count > 1000)
    }

    @Test func defaultFileNamesIncludeTimestampAndExtension() {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let pdfName = ReportExportService.defaultFileName(for: .pdf, date: date)
        let mdName = ReportExportService.defaultFileName(for: .markdown, date: date)
        #expect(pdfName.hasPrefix("HagimiMonitor-Report-"))
        #expect(pdfName.hasSuffix(".pdf"))
        #expect(mdName.hasSuffix(".md"))
    }
}
