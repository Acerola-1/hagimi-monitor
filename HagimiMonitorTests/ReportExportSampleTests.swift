import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 生成真实原生导出样本（Markdown / JSON / PDF）到仓库 tmp 目录，供人工检查版面与内容口径。
struct ReportExportSampleTests {
    @Test @MainActor func writesInspectableSamplesForWeekRange() throws {
        let outDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tmp/statistics-metric/export", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let now = Date()
        var rows: [StatisticsRow] = []
        for index in 0..<(7 * 24) {
            var values = [Double?](repeating: nil, count: StatisticsRow.columns.count)
            func set(_ name: String, _ value: Double) {
                if let i = StatisticsRow.columns.firstIndex(where: { $0.name == name }) { values[i] = value }
            }
            let t = Int64(now.timeIntervalSince1970) - Int64(index) * 3600
            set("cpu_avg", 18 + Double(index % 24))
            set("gpu_avg", 30 + Double(index % 17))
            set("mem_pct_avg", 60 + Double(index % 12))
            set("mem_warn_s", index % 12 == 0 ? 3600 : 0)
            set("cover_s", 3600)
            rows.append(StatisticsRow(t: t, n: 3600, values: values))
        }

        let meta = ReportMeta(
            deviceName: "REDMI Book Pro 14",
            modelName: "Mac16,1",
            osVersion: "macOS 27.0",
            recordDays: 60,
            appVersion: "1.6.1",
            isDirect: true
        )
        let snapshot = ReportSnapshot(
            capturedAt: now,
            meta: meta,
            minutes: [],
            hours: rows,
            days: [],
            process: nil,
            hardware: nil,
            systemSleepIntervals: []
        )
        let model = ReportDataAggregator.aggregate(snapshot: snapshot, range: .week, now: now)

        let mdTarget = outDir.appendingPathComponent("sample-week.md")
        let md = ReportExportService.generateMarkdownReport(model: model, meta: meta)
        try md.write(to: mdTarget, atomically: true, encoding: .utf8)

        let jsonTarget = outDir.appendingPathComponent("sample-week.json")
        let jsonData = try ReportExportService.generateJSONReport(model: model, meta: meta)
        try jsonData.write(to: jsonTarget, options: .atomic)

        let pdfTarget = outDir.appendingPathComponent("sample-week.pdf")
        let pdfData = ReportExportService.renderPDFData(model: model, meta: meta, hardware: nil)
        try pdfData.write(to: pdfTarget, options: .atomic)

        #expect(FileManager.default.fileExists(atPath: mdTarget.path))
        #expect(FileManager.default.fileExists(atPath: jsonTarget.path))
        #expect(FileManager.default.fileExists(atPath: pdfTarget.path))
        #expect(pdfData.starts(with: Data("%PDF".utf8)))
    }
}
