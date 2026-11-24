import AppKit
import Foundation
import UniformTypeIdentifiers

/// 原始采样数据表导出格式（CSV / Markdown / JSON，纯原生无 HTML 模板依赖）。
enum ReportExportFormat: String, CaseIterable, Identifiable {
    case csv
    case markdown
    case json

    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return String(localized: "stats.r.exportCSV", defaultValue: "Excel / CSV 表格 (.csv)")
        case .markdown: return String(localized: "stats.r.exportMarkdown", defaultValue: "Markdown 表格 (.md)")
        case .json: return String(localized: "stats.r.exportJSON", defaultValue: "JSON 数据 (.json)")
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .markdown: return "md"
        case .json: return "json"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .markdown: return .plainText
        case .json: return .json
        }
    }
}

/// 报表原始数据导出生成器。
nonisolated enum ReportDataExporter {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    private static let fileDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df
    }()

    // MARK: - CSV 导出（缺失值一律输出空串 `""`，速率采用十进制 KB/s 与界面同源）

    static func generateCSV(rows: [StatisticsRow], bucketSeconds: Double) -> String {
        var lines: [String] = []
        let bom = "\u{FEFF}"

        let headers = [
            String(localized: "stats.r.col.time", defaultValue: "时间"),
            String(localized: "stats.r.col.frames", defaultValue: "采样帧数"),
            String(localized: "stats.r.col.cpuAvg", defaultValue: "CPU平均(%)"),
            String(localized: "stats.r.col.cpuMax", defaultValue: "CPU峰值(%)"),
            String(localized: "stats.r.col.cpuUser", defaultValue: "CPU用户态(%)"),
            String(localized: "stats.r.col.cpuSys", defaultValue: "CPU系统态(%)"),
            String(localized: "stats.r.col.cpuP", defaultValue: "性能核P(%)"),
            String(localized: "stats.r.col.cpuE", defaultValue: "能效核E(%)"),
            String(localized: "stats.r.col.cpuTemp", defaultValue: "CPU核心温度(°C)"),
            String(localized: "stats.r.col.gpuAvg", defaultValue: "GPU平均(%)"),
            String(localized: "stats.r.col.gpuMax", defaultValue: "GPU峰值(%)"),
            String(localized: "stats.r.col.gpuMem", defaultValue: "动态显存(MB)"),
            String(localized: "stats.r.col.memPct", defaultValue: "内存占用(%)"),
            String(localized: "stats.r.col.memUsed", defaultValue: "已用内存(MB)"),
            String(localized: "stats.r.col.memComp", defaultValue: "压缩内存(MB)"),
            String(localized: "stats.r.col.memSwap", defaultValue: "Swap交换(MB)"),
            String(localized: "stats.r.col.memPressure", defaultValue: "内存压力(%)"),
            String(localized: "stats.r.col.netDown", defaultValue: "网络下行(KB/s)"),
            String(localized: "stats.r.col.netUp", defaultValue: "网络上行(KB/s)"),
            String(localized: "stats.r.col.netDownPeak", defaultValue: "网络下行峰值(KB/s)"),
            String(localized: "stats.r.col.netUpPeak", defaultValue: "网络上行峰值(KB/s)"),
            String(localized: "stats.r.col.diskRead", defaultValue: "磁盘读取(KB/s)"),
            String(localized: "stats.r.col.diskWrite", defaultValue: "磁盘写入(KB/s)"),
            String(localized: "stats.r.col.diskReadPeak", defaultValue: "磁盘读峰值(KB/s)"),
            String(localized: "stats.r.col.diskWritePeak", defaultValue: "磁盘写峰值(KB/s)"),
            String(localized: "stats.r.col.powerAvg", defaultValue: "整机功耗(W)"),
            String(localized: "stats.r.col.powerMax", defaultValue: "最高瞬时功耗(W)"),
            String(localized: "stats.r.col.battLevel", defaultValue: "电池电量(%)"),
            String(localized: "stats.r.col.battTemp", defaultValue: "电池温度(°C)"),
            String(localized: "stats.r.col.acFrac", defaultValue: "交流供电占比(%)"),
            String(localized: "stats.r.col.fan", defaultValue: "风扇转速(RPM)"),
            String(localized: "stats.r.col.thermal", defaultValue: "系统热状态档位")
        ].map(escapeCSV)
        lines.append(headers.joined(separator: ","))

        let safeBucket = max(bucketSeconds, 1.0)
        for row in rows {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t)))
            let downRateKB = row.netDown.map { ($0 / safeBucket) / 1000.0 }
            let upRateKB = row.netUp.map { ($0 / safeBucket) / 1000.0 }
            let readRateKB = row.diskRead.map { ($0 / safeBucket) / 1000.0 }
            let writeRateKB = row.diskWrite.map { ($0 / safeBucket) / 1000.0 }

            let cols: [String] = [
                dateStr,
                "\(row.n)",
                fmtCSVDouble(row.cpuAvg, "%.1f"),
                fmtCSVDouble(row.cpuMax, "%.1f"),
                fmtCSVDouble(row.cpuUserAvg, "%.1f"),
                fmtCSVDouble(row.cpuSysAvg, "%.1f"),
                fmtCSVDouble(row.cpuPAvg, "%.1f"),
                fmtCSVDouble(row.cpuEAvg, "%.1f"),
                fmtCSVDouble(row.cpuTempAvg, "%.1f"),
                fmtCSVDouble(row.gpuAvg, "%.1f"),
                fmtCSVDouble(row.gpuMax, "%.1f"),
                fmtBytesMiB(row.gpuMemAvg),
                fmtCSVDouble(row.memPctAvg, "%.1f"),
                fmtBytesMiB(row.memUsedAvg),
                fmtBytesMiB(row.memCompAvg),
                fmtBytesMiB(row.memSwapAvg),
                fmtCSVDouble(row.memPressureAvg, "%.0f"),
                fmtCSVDouble(downRateKB, "%.1f"),
                fmtCSVDouble(upRateKB, "%.1f"),
                fmtDecimalRateKB(row.netDownPeak),
                fmtDecimalRateKB(row.netUpPeak),
                fmtCSVDouble(readRateKB, "%.1f"),
                fmtCSVDouble(writeRateKB, "%.1f"),
                fmtDecimalRateKB(row.diskReadPeak),
                fmtDecimalRateKB(row.diskWritePeak),
                fmtCSVDouble(row.powerAvg, "%.1f"),
                fmtCSVDouble(row.powerMax, "%.1f"),
                fmtCSVDouble(row.battLevelAvg, "%.0f"),
                fmtCSVDouble(row.battTempAvg, "%.1f"),
                row.acFrac.map { String(format: "%.0f", $0 * 100) } ?? "",
                fmtCSVDouble(row.fanAvg, "%.0f"),
                fmtThermal(row.cpuThermalAvg, emptyValue: "")
            ]
            lines.append(cols.map(escapeCSV).joined(separator: ","))
        }

        return bom + lines.joined(separator: "\r\n")
    }

    // MARK: - Markdown 导出

    static func generateMarkdown(rows: [StatisticsRow], bucketSeconds: Double, meta: String) -> String {
        let exportTime = dateFormatter.string(from: Date())
        let safeBucket = max(bucketSeconds, 1.0)
        var md = """
        # \(String(localized: "stats.r.exportMDTitle", defaultValue: "HagimiMonitor 采样原始数据导出"))

        - **\(String(localized: "report.export.md.exportedAt", defaultValue: "导出时间"))**: \(exportTime)
        - **\(String(localized: "report.export.md.rowCount", defaultValue: "记录总数"))**: \(rows.count)
        - **\(String(localized: "report.export.md.range", defaultValue: "时间跨度"))**: \(meta)

        | \(String(localized: "stats.r.tbl.time", defaultValue: "时间")) | \(String(localized: "stats.r.tbl.frames", defaultValue: "帧数")) | \(String(localized: "stats.r.tbl.cpuAvg", defaultValue: "CPU均值")) | \(String(localized: "stats.r.tbl.cpuMax", defaultValue: "CPU峰值")) | \(String(localized: "stats.r.tbl.gpuAvg", defaultValue: "GPU均值")) | \(String(localized: "stats.r.tbl.gpuMem", defaultValue: "显存已用")) | \(String(localized: "stats.r.tbl.memUsed", defaultValue: "内存已用")) | \(String(localized: "stats.r.tbl.memPressure", defaultValue: "内存压力")) | Swap | \(String(localized: "stats.r.tbl.netDown", defaultValue: "网络下行")) | \(String(localized: "stats.r.tbl.netUp", defaultValue: "网络上传")) | \(String(localized: "stats.r.tbl.diskRead", defaultValue: "磁盘读速")) | \(String(localized: "stats.r.tbl.diskWrite", defaultValue: "磁盘写速")) | \(String(localized: "stats.r.tbl.power", defaultValue: "整机功耗")) | \(String(localized: "stats.r.tbl.battery", defaultValue: "电池")) | \(String(localized: "stats.r.tbl.temp", defaultValue: "CPU温度")) | \(String(localized: "stats.r.tbl.fan", defaultValue: "风扇转速")) | \(String(localized: "stats.r.tbl.thermal", defaultValue: "热状态")) |
        | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :---: |

        """

        for row in rows {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t)))
            let downRate = (row.netDown ?? 0) / safeBucket
            let upRate = (row.netUp ?? 0) / safeBucket
            let readRate = (row.diskRead ?? 0) / safeBucket
            let writeRate = (row.diskWrite ?? 0) / safeBucket

            let battStr: String = {
                if let b = row.battLevelAvg {
                    return String(format: "%.0f%%", b)
                }
                if row.acFrac != nil {
                    return "AC"
                }
                return "—"
            }()

            let line = [
                dateStr,
                "\(row.n)",
                fmtDisplayDouble(row.cpuAvg, "%.1f%%"),
                fmtDisplayDouble(row.cpuMax, "%.1f%%"),
                fmtDisplayDouble(row.gpuAvg, "%.1f%%"),
                row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                row.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fmtDisplayDouble(row.memPressureAvg, "%.0f%%"),
                row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                row.netDown != nil ? ReportUIHelper.formatBytesRate(downRate) : "—",
                row.netUp != nil ? ReportUIHelper.formatBytesRate(upRate) : "—",
                row.diskRead != nil ? ReportUIHelper.formatBytesRate(readRate) : "—",
                row.diskWrite != nil ? ReportUIHelper.formatBytesRate(writeRate) : "—",
                fmtDisplayDouble(row.powerAvg, "%.1f W"),
                battStr,
                fmtDisplayDouble(row.cpuTempAvg, "%.1f°C"),
                row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—",
                fmtThermal(row.cpuThermalAvg)
            ].joined(separator: " | ")

            md += "| " + line + " |\n"
        }

        return md
    }

    // MARK: - JSON 导出

    static func generateJSON(rows: [StatisticsRow], bucketSeconds: Double, meta: String) throws -> Data {
        struct ExportRow: Encodable {
            let timestamp: Int64
            let date: String
            let frames: Int
            let cpuAvg: Double?
            let cpuMax: Double?
            let cpuUserAvg: Double?
            let cpuSysAvg: Double?
            let cpuPAvg: Double?
            let cpuEAvg: Double?
            let gpuAvg: Double?
            let gpuMax: Double?
            let gpuMemAvgBytes: Double?
            let memUsedAvgBytes: Double?
            let memPctAvg: Double?
            let memPressureAvg: Double?
            let memSwapAvgBytes: Double?
            let netDownBytesPerSec: Double?
            let netUpBytesPerSec: Double?
            let diskReadBytesPerSec: Double?
            let diskWriteBytesPerSec: Double?
            let powerAvgWatts: Double?
            let cpuTempAvgCelsius: Double?
            let cpuThermalLevel: Int?
            let fanAvgRPM: Double?
        }

        struct Envelope: Encodable {
            let exportedAt: String
            let range: String
            let bucketSeconds: Double
            let count: Int
            let rows: [ExportRow]
        }

        let safeBucket = max(bucketSeconds, 1.0)
        let mapped = rows.map { row in
            ExportRow(
                timestamp: row.t,
                date: dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t))),
                frames: row.n,
                cpuAvg: row.cpuAvg,
                cpuMax: row.cpuMax,
                cpuUserAvg: row.cpuUserAvg,
                cpuSysAvg: row.cpuSysAvg,
                cpuPAvg: row.cpuPAvg,
                cpuEAvg: row.cpuEAvg,
                gpuAvg: row.gpuAvg,
                gpuMax: row.gpuMax,
                gpuMemAvgBytes: row.gpuMemAvg,
                memUsedAvgBytes: row.memUsedAvg,
                memPctAvg: row.memPctAvg,
                memPressureAvg: row.memPressureAvg,
                memSwapAvgBytes: row.memSwapAvg,
                netDownBytesPerSec: row.netDown.map { $0 / safeBucket },
                netUpBytesPerSec: row.netUp.map { $0 / safeBucket },
                diskReadBytesPerSec: row.diskRead.map { $0 / safeBucket },
                diskWriteBytesPerSec: row.diskWrite.map { $0 / safeBucket },
                powerAvgWatts: row.powerAvg,
                cpuTempAvgCelsius: row.cpuTempAvg,
                cpuThermalLevel: StatisticsDisplayFormat.thermalLevelIndex(row.cpuThermalAvg),
                fanAvgRPM: row.fanAvg
            )
        }

        let envelope = Envelope(
            exportedAt: dateFormatter.string(from: Date()),
            range: meta,
            bucketSeconds: bucketSeconds,
            count: mapped.count,
            rows: mapped
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // MARK: - 导出对话框（后台生成，不阻塞主线程）

    @MainActor
    static func export(
        format: ReportExportFormat,
        rows: [StatisticsRow],
        bucketSeconds: Double,
        meta: String,
        window: NSWindow?
    ) {
        guard !rows.isEmpty else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.utType]
        let dateStr = fileDateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "HagimiMonitor_Samples_\(dateStr).\(format.fileExtension)"
        savePanel.title = String(localized: "stats.r.exportDialogTitle", defaultValue: "导出采样数据表格")
        savePanel.prompt = String(localized: "stats.r.exportBtn", defaultValue: "导出")

        let onComplete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let targetURL = savePanel.url else { return }
            Task { @MainActor in
                do {
                    let didStartAccess = targetURL.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess { targetURL.stopAccessingSecurityScopedResource() }
                    }
                    let data = try await Task.detached(priority: .userInitiated) {
                        switch format {
                        case .csv:
                            return Data(generateCSV(rows: rows, bucketSeconds: bucketSeconds).utf8)
                        case .markdown:
                            return Data(generateMarkdown(rows: rows, bucketSeconds: bucketSeconds, meta: meta).utf8)
                        case .json:
                            return try generateJSON(rows: rows, bucketSeconds: bucketSeconds, meta: meta)
                        }
                    }.value
                    try data.write(to: targetURL, options: .atomic)
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                } catch {
                    let alert = NSAlert(error: error)
                    if let window {
                        alert.beginSheetModal(for: window, completionHandler: nil)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        if let window {
            savePanel.beginSheetModal(for: window, completionHandler: onComplete)
        } else {
            let res = savePanel.runModal()
            onComplete(res)
        }
    }

    // MARK: - 格式化辅助

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func fmtCSVDouble(_ val: Double?, _ format: String) -> String {
        guard let val else { return "" }
        return String(format: format, val)
    }

    private static func fmtDisplayDouble(_ val: Double?, _ format: String) -> String {
        guard let val else { return "—" }
        return String(format: format, val)
    }

    private static func fmtBytesMiB(_ bytes: Double?) -> String {
        guard let bytes else { return "" }
        return String(format: "%.1f", bytes / 1_048_576.0)
    }

    private static func fmtDecimalRateKB(_ bytesPerSec: Double?) -> String {
        guard let bytesPerSec else { return "" }
        return String(format: "%.1f", bytesPerSec / 1_000.0)
    }

    static func fmtThermal(_ thermal: Double?, emptyValue: String = "—") -> String {
        guard let index = StatisticsDisplayFormat.thermalLevelIndex(thermal) else { return emptyValue }
        let label = StatisticsDisplayFormat.thermalStateLabel(thermal)
        return "\(label)(\(index))"
    }
}
