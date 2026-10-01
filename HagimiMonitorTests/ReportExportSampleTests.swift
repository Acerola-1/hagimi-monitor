import Foundation
import Testing
@testable import HagimiMonitorDirect

/// 生成一份真实导出样本到仓库 tmp 目录，供人工检查打印版面与范围说明。
/// 平常等同常规断言；样本路径固定，便于核对。
struct ReportExportSampleTests {
    @Test func writesInspectableSampleForWeekRange() throws {
        let outDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tmp/statistics-metric/export", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let target = outDir.appendingPathComponent("sample-week.html")

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        // 造一段有内容的样本：近 7 日的轻度压力与两个应用。
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

        _ = try StandaloneHTMLReportExporter.write(
            to: target,
            snapshot: (minutes: [], hours: rows, days: []),
            meta: [
                "device": "REDMI Book Pro 14",
                "model": "Mac16,1",
                "os": "macOS 27.0",
                "days": 60,
                "appVersion": "1.6.1",
                "direct": true,
            ],
            committedRange: (label: "近 7 日", from: from, to: now)
        )

        let html = try String(contentsOf: target, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: target.path))
        // 范围与来源说明必须出现在纸面可见的元信息里。
        #expect(html.contains("committedRange"))
        #expect(html.contains("scopeNote"))
        #expect(html.contains("updatePrintScope"))
    }
}
