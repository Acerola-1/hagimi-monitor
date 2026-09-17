import AppKit
import Foundation
import UniformTypeIdentifiers

/// 报表数据导出格式
enum ReportExportFormat: String, CaseIterable, Identifiable {
    case csv
    case html
    case markdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return String(localized: "stats.r.exportCSV", defaultValue: "Excel / CSV 表格 (.csv)")
        case .html: return String(localized: "stats.r.exportHTML", defaultValue: "HTML 网页表格 (.html)")
        case .markdown: return String(localized: "stats.r.exportMarkdown", defaultValue: "Markdown 表格 (.md)")
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .html: return "html"
        case .markdown: return "md"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .html: return .html
        case .markdown: return .plainText
        }
    }
}

/// 报表原始数据导出生成器
enum ReportDataExporter {
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

    // MARK: - CSV 导出

    static func generateCSV(rows: [StatisticsRow], bucketSeconds: Double) -> String {
        var lines: [String] = []

        // UTF-8 BOM，使 Excel / Numbers 打开时识别中文字符编码
        let bom = "\u{FEFF}"

        // 表头
        let headers = [
            "时间",
            "采样帧数",
            "CPU平均(%)",
            "CPU峰值(%)",
            "CPU用户态(%)",
            "CPU系统态(%)",
            "性能核P(%)",
            "能效核E(%)",
            "CPU核心温度(°C)",
            "GPU平均(%)",
            "GPU峰值(%)",
            "动态显存(MB)",
            "内存占用(%)",
            "已用内存(MB)",
            "压缩内存(MB)",
            "Swap交换(MB)",
            "内存压力(%)",
            "网络下行(KB/s)",
            "网络上行(KB/s)",
            "网络下行峰值(KB/s)",
            "网络上行峰值(KB/s)",
            "磁盘读取(KB/s)",
            "磁盘写入(KB/s)",
            "磁盘读峰值(KB/s)",
            "磁盘写峰值(KB/s)",
            "整机功耗(W)",
            "最高瞬时功耗(W)",
            "电池电量(%)",
            "电池温度(°C)",
            "交流供电占比(%)",
            "风扇转速(RPM)",
            "系统热状态档位"
        ]
        lines.append(headers.joined(separator: ","))

        for row in rows {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t)))
            let downRate = (row.netDown ?? 0) / max(bucketSeconds, 1.0) / 1024.0
            let upRate = (row.netUp ?? 0) / max(bucketSeconds, 1.0) / 1024.0
            let readRate = (row.diskRead ?? 0) / max(bucketSeconds, 1.0) / 1024.0
            let writeRate = (row.diskWrite ?? 0) / max(bucketSeconds, 1.0) / 1024.0

            let cols: [String] = [
                dateStr,
                "\(row.n)",
                fmtD(row.cpuAvg, "%.1f"),
                fmtD(row.cpuMax, "%.1f"),
                fmtD(row.cpuUserAvg, "%.1f"),
                fmtD(row.cpuSysAvg, "%.1f"),
                fmtD(row.cpuPAvg, "%.1f"),
                fmtD(row.cpuEAvg, "%.1f"),
                fmtD(row.cpuTempAvg, "%.1f"),
                fmtD(row.gpuAvg, "%.1f"),
                fmtD(row.gpuMax, "%.1f"),
                fmtBytesMB(row.gpuMemAvg),
                fmtD(row.memPctAvg, "%.1f"),
                fmtBytesMB(row.memUsedAvg),
                fmtBytesMB(row.memCompAvg),
                fmtBytesMB(row.memSwapAvg),
                fmtD(row.memPressureAvg, "%.0f"),
                row.netDown != nil ? String(format: "%.1f", downRate) : "",
                row.netUp != nil ? String(format: "%.1f", upRate) : "",
                fmtRateKB(row.netDownPeak),
                fmtRateKB(row.netUpPeak),
                row.diskRead != nil ? String(format: "%.1f", readRate) : "",
                row.diskWrite != nil ? String(format: "%.1f", writeRate) : "",
                fmtRateKB(row.diskReadPeak),
                fmtRateKB(row.diskWritePeak),
                fmtD(row.powerAvg, "%.1f"),
                fmtD(row.powerMax, "%.1f"),
                fmtD(row.battLevelAvg, "%.0f"),
                fmtD(row.battTempAvg, "%.1f"),
                row.acFrac.map { String(format: "%.0f", $0 * 100) } ?? "",
                fmtD(row.fanAvg, "%.0f"),
                fmtThermal(row.cpuThermalAvg)
            ]
            lines.append(cols.joined(separator: ","))
        }

        return bom + lines.joined(separator: "\r\n")
    }

    // MARK: - HTML 导出

    static func generateHTML(rows: [StatisticsRow], bucketSeconds: Double, meta: String) -> String {
        let exportTime = dateFormatter.string(from: Date())
        var html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8">
          <title>HagimiMonitor 采样原始数据导出</title>
          <style>
            * { box-sizing: border-box; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
              margin: 24px;
              color: #1d1d1f;
              background: #fff;
            }
            header {
              margin-bottom: 20px;
              border-bottom: 1px solid #e5e5ea;
              padding-bottom: 12px;
            }
            h1 {
              font-size: 20px;
              margin: 0 0 6px 0;
              font-weight: 600;
            }
            .meta {
              font-size: 12px;
              color: #86868b;
            }
            .table-container {
              overflow-x: auto;
              border: 1px solid #d2d2d7;
              border-radius: 8px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 11px;
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            }
            th, td {
              border: 1px solid #e5e5ea;
              padding: 6px 10px;
              text-align: right;
              white-space: nowrap;
            }
            th {
              background: #f5f5f7;
              font-weight: 600;
              text-align: center;
              position: sticky;
              top: 0;
              z-index: 1;
            }
            th:first-child, td:first-child {
              text-align: left;
            }
            tr:nth-child(even) {
              background: #fafafa;
            }
            tr:hover {
              background: #eef4ff;
            }
          </style>
        </head>
        <body>
          <header>
            <h1>HagimiMonitor 采样原始数据</h1>
            <div class="meta">导出时间: \(exportTime) | 记录总数: \(rows.count) 条 | 时间跨度: \(meta)</div>
          </header>
          <div class="table-container">
            <table>
              <thead>
                <tr>
                  <th>时间</th>
                  <th>采样数</th>
                  <th>CPU均值</th>
                  <th>CPU峰值</th>
                  <th>P / E 核心</th>
                  <th>GPU均值</th>
                  <th>显存已用</th>
                  <th>内存已用</th>
                  <th>内存压力</th>
                  <th>Swap</th>
                  <th>网络下行</th>
                  <th>网络上传</th>
                  <th>磁盘读速</th>
                  <th>磁盘写速</th>
                  <th>整机功耗</th>
                  <th>电池</th>
                  <th>温度</th>
                  <th>风扇</th>
                  <th>热状态</th>
                </tr>
              </thead>
              <tbody>
        """

        for row in rows {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t)))
            let downRate = (row.netDown ?? 0) / max(bucketSeconds, 1.0)
            let upRate = (row.netUp ?? 0) / max(bucketSeconds, 1.0)
            let readRate = (row.diskRead ?? 0) / max(bucketSeconds, 1.0)
            let writeRate = (row.diskWrite ?? 0) / max(bucketSeconds, 1.0)

            let pEStr: String = {
                if let p = row.cpuPAvg, let e = row.cpuEAvg {
                    return String(format: "P:%.1f%% E:%.1f%%", p, e)
                }
                return "—"
            }()

            let battStr: String = {
                if let b = row.battLevelAvg {
                    return String(format: "%.0f%%", b)
                }
                if row.acFrac != nil {
                    return "交流供电"
                }
                return "—"
            }()

            html += """
                <tr>
                  <td>\(dateStr)</td>
                  <td>\(row.n)</td>
                  <td>\(fmtD(row.cpuAvg, "%.1f%%"))</td>
                  <td>\(fmtD(row.cpuMax, "%.1f%%"))</td>
                  <td>\(pEStr)</td>
                  <td>\(fmtD(row.gpuAvg, "%.1f%%"))</td>
                  <td>\(row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—")</td>
                  <td>\(row.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—")</td>
                  <td>\(fmtD(row.memPressureAvg, "%.0f%%"))</td>
                  <td>\(row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—")</td>
                  <td>\(row.netDown != nil ? ReportUIHelper.formatBytesRate(downRate) : "—")</td>
                  <td>\(row.netUp != nil ? ReportUIHelper.formatBytesRate(upRate) : "—")</td>
                  <td>\(row.diskRead != nil ? ReportUIHelper.formatBytesRate(readRate) : "—")</td>
                  <td>\(row.diskWrite != nil ? ReportUIHelper.formatBytesRate(writeRate) : "—")</td>
                  <td>\(fmtD(row.powerAvg, "%.1f W"))</td>
                  <td>\(battStr)</td>
                  <td>\(fmtD(row.cpuTempAvg, "%.1f°C"))</td>
                  <td>\(row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—")</td>
                  <td>\(fmtThermal(row.cpuThermalAvg))</td>
                </tr>
            """
        }

        html += """
              </tbody>
            </table>
          </div>
        </body>
        </html>
        """
        return html
    }

    // MARK: - Markdown 导出

    static func generateMarkdown(rows: [StatisticsRow], bucketSeconds: Double, meta: String) -> String {
        let exportTime = dateFormatter.string(from: Date())
        var md = """
        # HagimiMonitor 采样原始数据导出

        - **导出时间**: \(exportTime)
        - **记录总数**: \(rows.count) 条
        - **时间跨度**: \(meta)

        | 时间 | 采样帧 | CPU均值 | CPU峰值 | GPU均值 | 动态显存 | 内存已用 | 内存压力 | Swap | 下行速率 | 上行速率 | 磁盘读速 | 磁盘写速 | 整机功耗 | 电池 | CPU温度 | 风扇转速 | 热状态 |
        | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :---: |

        """

        for row in rows {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.t)))
            let downRate = (row.netDown ?? 0) / max(bucketSeconds, 1.0)
            let upRate = (row.netUp ?? 0) / max(bucketSeconds, 1.0)
            let readRate = (row.diskRead ?? 0) / max(bucketSeconds, 1.0)
            let writeRate = (row.diskWrite ?? 0) / max(bucketSeconds, 1.0)

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
                fmtD(row.cpuAvg, "%.1f%%"),
                fmtD(row.cpuMax, "%.1f%%"),
                fmtD(row.gpuAvg, "%.1f%%"),
                row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                row.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fmtD(row.memPressureAvg, "%.0f%%"),
                row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                row.netDown != nil ? ReportUIHelper.formatBytesRate(downRate) : "—",
                row.netUp != nil ? ReportUIHelper.formatBytesRate(upRate) : "—",
                row.diskRead != nil ? ReportUIHelper.formatBytesRate(readRate) : "—",
                row.diskWrite != nil ? ReportUIHelper.formatBytesRate(writeRate) : "—",
                fmtD(row.powerAvg, "%.1f W"),
                battStr,
                fmtD(row.cpuTempAvg, "%.1f°C"),
                row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—",
                fmtThermal(row.cpuThermalAvg)
            ].joined(separator: " | ")

            md += "| " + line + " |\n"
        }

        return md
    }

    // MARK: - 导出对话框

    static func export(
        format: ReportExportFormat,
        rows: [StatisticsRow],
        bucketSeconds: Double,
        meta: String,
        window: NSWindow?
    ) {
        guard !rows.isEmpty else { return }

        let content: String
        switch format {
        case .csv:
            content = generateCSV(rows: rows, bucketSeconds: bucketSeconds)
        case .html:
            content = generateHTML(rows: rows, bucketSeconds: bucketSeconds, meta: meta)
        case .markdown:
            content = generateMarkdown(rows: rows, bucketSeconds: bucketSeconds, meta: meta)
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.utType]
        let dateStr = fileDateFormatter.string(from: Date())
        savePanel.nameFieldStringValue = "HagimiMonitor_Samples_\(dateStr).\(format.fileExtension)"
        savePanel.title = String(localized: "stats.r.exportDialogTitle", defaultValue: "导出采样数据表格")
        savePanel.prompt = String(localized: "stats.r.exportBtn", defaultValue: "导出")

        let onComplete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let targetURL = savePanel.url else { return }
            do {
                try content.write(to: targetURL, atomically: true, encoding: .utf8)
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

        if let window {
            savePanel.beginSheetModal(for: window, completionHandler: onComplete)
        } else {
            let res = savePanel.runModal()
            onComplete(res)
        }
    }

    // MARK: - 格式化辅助

    private static func fmtD(_ val: Double?, _ format: String) -> String {
        guard let val else { return "—" }
        return String(format: format, val)
    }

    private static func fmtBytesMB(_ bytes: Double?) -> String {
        guard let bytes else { return "" }
        return String(format: "%.1f", bytes / (1024 * 1024))
    }

    private static func fmtRateKB(_ bytesPerSec: Double?) -> String {
        guard let bytesPerSec else { return "" }
        return String(format: "%.1f", bytesPerSec / 1024)
    }

    private static func fmtThermal(_ thermal: Double?) -> String {
        guard let thermal else { return "—" }
        if thermal < 0.05 { return "正常(0)" }
        if thermal < 0.35 { return "中度(1)" }
        if thermal < 0.75 { return "严重(2)" }
        return "紧急(3)"
    }
}
