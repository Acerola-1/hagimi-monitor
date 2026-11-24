import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// 完整统计报表导出格式（原生 PDF、Markdown、CSV 采样明细分列、JSON 结构化数据包）。
nonisolated enum ReportBundleExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case markdown
    case csv
    case json

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: return String(localized: "stats.report.export.format.pdf", defaultValue: "PDF 报表文档 (.pdf)")
        case .markdown: return String(localized: "stats.report.export.format.markdown", defaultValue: "Markdown 报告 (.md)")
        case .csv: return String(localized: "stats.report.export.format.csv", defaultValue: "CSV 原始采样 (.csv)")
        case .json: return String(localized: "stats.report.export.format.json", defaultValue: "JSON 数据包 (.json)")
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .markdown: return "md"
        case .csv: return "csv"
        case .json: return "json"
        }
    }

    var utType: UTType {
        switch self {
        case .pdf: return .pdf
        case .markdown: return .plainText
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}

/// 原生打印与多格式导出服务（纯 Swift/AppKit 实现，无 WebKit/HTML 依赖）。
enum ReportExportService {

    private nonisolated static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    nonisolated static func defaultFileName(for format: ReportBundleExportFormat, date: Date = Date()) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "HagimiMonitor-Report-\(df.string(from: date)).\(format.fileExtension)"
    }

    // MARK: - 原生打印与 PDF 矢量生成

    @MainActor
    static func makePrintOperation(
        model: ReportActiveRangeModel,
        meta: ReportMeta,
        hardware: HardwareInventory?
    ) -> NSPrintOperation? {
        let data = renderPDFData(model: model, meta: meta, hardware: hardware)
        guard let document = PDFDocument(data: data) else { return nil }
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        printInfo.topMargin = 28
        printInfo.bottomMargin = 28
        printInfo.leftMargin = 28
        printInfo.rightMargin = 28
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        guard let operation = document.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true)
        else { return nil }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation
    }

    @MainActor
    static func renderPDFData(
        model: ReportActiveRangeModel,
        meta: ReportMeta,
        hardware: HardwareInventory?
    ) -> Data {
        // 标准 A4 纸张尺寸（595.28 × 841.89 pt），固定页边距与页脚页码区域
        let pageWidth: CGFloat = 595.28
        let pageHeight: CGFloat = 841.89
        let margin: CGFloat = 28
        let footerHeight: CGFloat = 20
        let contentWidth: CGFloat = pageWidth - margin * 2
        let usableHeight: CGFloat = pageHeight - margin * 2 - footerHeight
        let blockSpacing: CGFloat = 8

        let blocks = ReportPrintableView.printableBlocks(model: model, meta: meta, hardware: hardware)

        struct MeasuredBlock {
            let keepWithNext: Bool
            let height: CGFloat
            let renderer: ImageRenderer<AnyView>
        }

        var measured: [MeasuredBlock] = []
        measured.reserveCapacity(blocks.count)
        for block in blocks {
            let framed = AnyView(
                block.view
                    .frame(width: contentWidth, alignment: .leading)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            let renderer = ImageRenderer(content: framed)
            renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
            var h: CGFloat = 0
            renderer.render { size, _ in
                h = max(1, size.height)
            }
            measured.append(MeasuredBlock(keepWithNext: block.keepWithNext, height: h, renderer: renderer))
        }

        struct PageSlice {
            let renderer: ImageRenderer<AnyView>
            let blockHeight: CGFloat
            let sliceTopOffset: CGFloat
            let sliceHeight: CGFloat
            let yFromTop: CGFloat
        }

        var pages: [[PageSlice]] = [[]]
        var cursorY: CGFloat = 0

        for (index, item) in measured.enumerated() {
            // 若章节标题与下一条加起来超页底，提前换页以免标题孤立留在页尾
            if item.keepWithNext,
               index + 1 < measured.count,
               cursorY > 0 {
                let nextH = measured[index + 1].height
                let pairHeight = item.height + blockSpacing + min(nextH, usableHeight * 0.35)
                if cursorY + pairHeight > usableHeight {
                    pages.append([])
                    cursorY = 0
                }
            }

            if item.height <= usableHeight {
                if cursorY > 0 && cursorY + item.height > usableHeight {
                    pages.append([])
                    cursorY = 0
                }
                pages[pages.count - 1].append(
                    PageSlice(
                        renderer: item.renderer,
                        blockHeight: item.height,
                        sliceTopOffset: 0,
                        sliceHeight: item.height,
                        yFromTop: cursorY
                    )
                )
                cursorY += item.height + blockSpacing
            } else {
                // 单个超大块按页高垂直切片，保证不丢失任何信息
                if cursorY > 0 {
                    pages.append([])
                    cursorY = 0
                }
                var offset: CGFloat = 0
                while offset < item.height {
                    let take = min(usableHeight, item.height - offset)
                    pages[pages.count - 1].append(
                        PageSlice(
                            renderer: item.renderer,
                            blockHeight: item.height,
                            sliceTopOffset: offset,
                            sliceHeight: take,
                            yFromTop: 0
                        )
                    )
                    offset += take
                    if offset < item.height {
                        pages.append([])
                    }
                }
                cursorY = pages.last?.last.map { $0.yFromTop + $0.sliceHeight + blockSpacing } ?? 0
            }
        }

        if pages.count > 1, pages.last?.isEmpty == true {
            pages.removeLast()
        }

        let mutableData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let totalPages = pages.count
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: NSColor(white: 0.42, alpha: 1.0)
        ]

        for (pageIndex, slices) in pages.enumerated() {
            pdfContext.beginPDFPage(nil)

            // 白底铺满整张 A4 页面
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(mediaBox)

            for slice in slices {
                let clipRect = CGRect(
                    x: margin,
                    y: pageHeight - margin - slice.yFromTop - slice.sliceHeight,
                    width: contentWidth,
                    height: slice.sliceHeight
                )
                pdfContext.saveGState()
                pdfContext.clip(to: clipRect)
                let blockOriginY = pageHeight - margin - slice.yFromTop - slice.blockHeight + slice.sliceTopOffset
                pdfContext.translateBy(x: margin, y: blockOriginY)
                slice.renderer.render { _, draw in
                    draw(pdfContext)
                }
                pdfContext.restoreGState()
            }

            // 绘制页码页脚
            let pageText = String(
                format: String(localized: "report.print.pageNumber", defaultValue: "第 %d / %d 页"),
                pageIndex + 1,
                totalPages
            )
            let nsString = NSAttributedString(string: pageText, attributes: footerAttrs)
            let textSize = nsString.size()
            let drawOrigin = CGPoint(
                x: pageWidth - margin - textSize.width,
                y: margin * 0.45
            )
            let nsCtx = NSGraphicsContext(cgContext: pdfContext, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            nsString.draw(at: drawOrigin)
            NSGraphicsContext.restoreGraphicsState()

            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return mutableData as Data
    }

    // MARK: - Markdown 完整报告导出

    nonisolated static func generateMarkdownReport(
        model: ReportActiveRangeModel,
        meta: ReportMeta,
        hardware: HardwareInventory? = nil
    ) -> String {
        let conclusion = ReportPeriodConclusion.summary(
            events: model.events,
            appAlertCount: model.apps.highLoadAlerts.count,
            coveredSeconds: model.coveredSeconds,
            quality: model.quality
        )

        var lines: [String] = []
        lines.append("# \(String(localized: "report.print.title", defaultValue: "HagimiMonitor 系统统计报表"))")
        lines.append("")
        lines.append("- **\(String(localized: "report.export.md.device", defaultValue: "设备"))**: \(meta.deviceName) (\(meta.modelName), \(meta.osVersion))")
        lines.append("- **\(String(localized: "report.export.md.range", defaultValue: "统计范围"))**: \(model.range.label) (\(dateFormatter.string(from: model.from)) – \(dateFormatter.string(from: model.to)))")
        lines.append("- **\(String(localized: "report.export.md.granularity", defaultValue: "数据粒度"))**: \(model.granularity.label)")
        if let cov = model.coveragePercent {
            lines.append("- **\(String(localized: "report.export.md.coverage", defaultValue: "数据完整度"))**: \(String(format: "%.1f%%", cov))")
        }
        if let updatedAt = model.updatedAt {
            lines.append("- **\(String(localized: "report.export.md.capturedAt", defaultValue: "快照时刻"))**: \(dateFormatter.string(from: updatedAt))")
        }
        lines.append("")

        lines.append("## \(String(localized: "report.export.md.conclusion", defaultValue: "时段结论与状态评分"))")
        lines.append("")
        lines.append("**\(conclusion.headline)**")
        if let detail = conclusion.detail {
            lines.append("")
            lines.append(detail)
        }
        if let score = model.healthScore {
            let display = StatisticsHealthScore.displayScore(score.score, hasPressureEvents: !model.events.isEmpty)
            lines.append("")
            lines.append("- **\(String(localized: "stats.r.healthScoreTitle", defaultValue: "运行状态评分"))**: \(display) \(String(localized: "stats.r.pts", defaultValue: "分")) (\(score.level.title))")
            for dim in score.dimensions {
                lines.append("  - \(dim.name): \(dim.rawText)")
            }
        } else if let reason = model.healthScoreNilReason {
            lines.append("")
            lines.append("- \(reason)")
        }
        lines.append("")

        lines.append("## \(String(localized: "report.print.coreMetrics", defaultValue: "核心指标汇总"))")
        lines.append("")
        lines.append("| \(String(localized: "report.export.md.metricCol", defaultValue: "指标")) | \(String(localized: "report.export.md.valueCol", defaultValue: "数值")) |")
        lines.append("| :--- | :--- |")
        lines.append("| CPU | \(model.cpu.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—") (Peak: \(model.cpu.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—")) |")
        lines.append("| GPU | \(model.gpu.avgUsage.map { String(format: "%.1f%%", $0) } ?? "—") (Peak: \(model.gpu.peakUsage.map { String(format: "%.1f%%", $0) } ?? "—")) |")
        lines.append("| \(String(localized: "stats.metrics.memoryUsage", defaultValue: "内存")) | \(model.memory.memPctAvg.map { String(format: "%.1f%%", $0) } ?? "—") (Pressure: \(model.memory.pressureAvgPercent.map { String(format: "%.0f%%", $0) } ?? "—")) |")
        lines.append("| \(String(localized: "stats.metrics.power", defaultValue: "功耗")) | \(model.power.avgPowerWatts.map { String(format: "%.1f W", $0) } ?? "—") (Peak: \(model.power.peakPowerWatts.map { String(format: "%.1f W", $0) } ?? "—")) |")
        lines.append("| \(String(localized: "overview.resources.network", defaultValue: "网络")) | ↓ \(model.network.totalDownBytes.map(ReportUIHelper.formatVolume) ?? "—") / ↑ \(model.network.totalUpBytes.map(ReportUIHelper.formatVolume) ?? "—") |")
        lines.append("| \(String(localized: "stats.metrics.disk", defaultValue: "磁盘")) | R \(model.disk.totalReadBytes.map(ReportUIHelper.formatVolume) ?? "—") / W \(model.disk.totalWriteBytes.map(ReportUIHelper.formatVolume) ?? "—") |")
        lines.append("| \(String(localized: "stats.r.secThermal", defaultValue: "热压力")) | \(StatisticsDisplayFormat.thermalStateLabel(model.thermal.cpuThermalAvg)) · \(model.thermal.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? "—") |")
        lines.append("")

        if !model.events.isEmpty {
            lines.append("## \(String(localized: "stats.r.secEvents", defaultValue: "压力警告"))")
            lines.append("")
            for event in model.events {
                lines.append("- **\(event.kind.title)** [\(event.state.label)] \(dateFormatter.string(from: event.start)) – \(dateFormatter.string(from: event.end)) · \(StatisticsDisplayFormat.duration(event.pressureSeconds))")
            }
            lines.append("")
        }

        if !model.insights.isEmpty {
            lines.append("## \(String(localized: "stats.r.secInsights", defaultValue: "智能洞察"))")
            lines.append("")
            for insight in model.insights {
                lines.append("- **\(insight.title)**: \(insight.detail)")
            }
            lines.append("")
        }

        if !model.apps.cpuList.isEmpty {
            lines.append("## \(String(localized: "stats.r.secAppsTitle", defaultValue: "应用排行")) (CPU Top 10)")
            lines.append("")
            for (idx, app) in model.apps.cpuList.prefix(10).enumerated() {
                lines.append("\(idx + 1). **\(app.name)** — \(app.valueText)\(app.tierHint.map { " (\($0))" } ?? "")")
            }
            lines.append("")
        }

        if let hardware,
           let facts = hardware.categories.first(where: { $0.id == "this-mac" })?.groups.first(where: { $0.id == "identity" })?.facts,
           !facts.isEmpty {
            lines.append("## \(String(localized: "stats.r.kThisMac", defaultValue: "本机规格"))")
            lines.append("")
            for fact in facts {
                lines.append("- **\(fact.label.resolve(hwText))**: \(fact.value ?? "—")")
            }
            lines.append("")
        }

        lines.append("> \(String(localized: "stats.export.scopeNote", defaultValue: "应用数值来自每分钟前列采样，属估算；含旧日汇总的时段无法还原到分钟。"))")
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON 结构化导出

    nonisolated static func generateJSONReport(
        model: ReportActiveRangeModel,
        meta: ReportMeta
    ) throws -> Data {
        struct Payload: Encodable {
            struct CommittedRange: Encodable {
                let label: String
                let granularity: String
                let from: TimeInterval
                let to: TimeInterval
            }
            struct Summary: Encodable {
                let healthScore: Int?
                let healthLevel: String?
                let coveragePercent: Double?
                let coveredSeconds: Double
                let cpuAvg: Double?
                let cpuPeak: Double?
                let gpuAvg: Double?
                let gpuPeak: Double?
                let memPctAvg: Double?
                let memPressureAvg: Double?
                let powerAvgWatts: Double?
                let powerPeakWatts: Double?
                let netDownTotalBytes: Double?
                let netUpTotalBytes: Double?
                let diskReadTotalBytes: Double?
                let diskWriteTotalBytes: Double?
                let cpuTempAvg: Double?
                let cpuThermalAvg: Double?
            }
            struct Event: Encodable {
                let kind: String
                let state: String
                let start: TimeInterval
                let end: TimeInterval
                let pressureSeconds: Double
                let worstLevel: Int
            }
            struct Insight: Encodable {
                let id: String
                let title: String
                let detail: String
                let severity: String
            }
            struct AppItem: Encodable {
                let appKey: String
                let name: String
                let value: Double
                let peakValue: Double
                let valueText: String
            }
            struct SampleRow: Encodable {
                let t: Int64
                let n: Int
                let cpuAvg: Double?
                let cpuMax: Double?
                let gpuAvg: Double?
                let gpuMemAvg: Double?
                let memUsedAvg: Double?
                let memPressureAvg: Double?
                let memSwapAvg: Double?
                let netDownBytes: Double?
                let netUpBytes: Double?
                let diskReadBytes: Double?
                let diskWriteBytes: Double?
                let powerAvg: Double?
                let cpuTempAvg: Double?
                let cpuThermalAvg: Double?
                let fanAvg: Double?
            }

            let generatedAt: TimeInterval
            let scopeNote: String
            let deviceName: String
            let modelName: String
            let osVersion: String
            let appVersion: String
            let committedRange: CommittedRange
            let summary: Summary
            let events: [Event]
            let insights: [Insight]
            let topCpuApps: [AppItem]
            let topMemoryApps: [AppItem]
            let rows: [SampleRow]
        }

        let payload = Payload(
            generatedAt: Date().timeIntervalSince1970,
            scopeNote: String(localized: "stats.export.scopeNote", defaultValue: "应用数值来自每分钟前列采样，属估算；含旧日汇总的时段无法还原到分钟。"),
            deviceName: meta.deviceName,
            modelName: meta.modelName,
            osVersion: meta.osVersion,
            appVersion: meta.appVersion,
            committedRange: Payload.CommittedRange(
                label: model.range.label,
                granularity: model.granularity.rawValue,
                from: model.from.timeIntervalSince1970,
                to: model.to.timeIntervalSince1970
            ),
            summary: Payload.Summary(
                healthScore: model.healthScore.map { StatisticsHealthScore.displayScore($0.score, hasPressureEvents: !model.events.isEmpty) },
                healthLevel: model.healthScore?.level.rawValue,
                coveragePercent: model.coveragePercent,
                coveredSeconds: model.coveredSeconds,
                cpuAvg: model.cpu.avgUsage,
                cpuPeak: model.cpu.peakUsage,
                gpuAvg: model.gpu.avgUsage,
                gpuPeak: model.gpu.peakUsage,
                memPctAvg: model.memory.memPctAvg,
                memPressureAvg: model.memory.pressureAvgPercent,
                powerAvgWatts: model.power.avgPowerWatts,
                powerPeakWatts: model.power.peakPowerWatts,
                netDownTotalBytes: model.network.totalDownBytes,
                netUpTotalBytes: model.network.totalUpBytes,
                diskReadTotalBytes: model.disk.totalReadBytes,
                diskWriteTotalBytes: model.disk.totalWriteBytes,
                cpuTempAvg: model.thermal.cpuTempAvg,
                cpuThermalAvg: model.thermal.cpuThermalAvg
            ),
            events: model.events.map {
                Payload.Event(
                    kind: $0.kind == .memory ? "memory" : "thermal",
                    state: String(describing: $0.state),
                    start: $0.start.timeIntervalSince1970,
                    end: $0.end.timeIntervalSince1970,
                    pressureSeconds: $0.pressureSeconds,
                    worstLevel: $0.worstLevel
                )
            },
            insights: model.insights.map {
                Payload.Insight(id: $0.id, title: $0.title, detail: $0.detail, severity: $0.severity.rawValue)
            },
            topCpuApps: model.apps.cpuList.prefix(20).map {
                Payload.AppItem(appKey: $0.appKey, name: $0.name, value: $0.value, peakValue: $0.peakValue, valueText: $0.valueText)
            },
            topMemoryApps: model.apps.memList.prefix(20).map {
                Payload.AppItem(appKey: $0.appKey, name: $0.name, value: $0.value, peakValue: $0.peakValue, valueText: $0.valueText)
            },
            rows: model.rows.map {
                Payload.SampleRow(
                    t: $0.t,
                    n: $0.n,
                    cpuAvg: $0.cpuAvg,
                    cpuMax: $0.cpuMax,
                    gpuAvg: $0.gpuAvg,
                    gpuMemAvg: $0.gpuMemAvg,
                    memUsedAvg: $0.memUsedAvg,
                    memPressureAvg: $0.memPressureAvg,
                    memSwapAvg: $0.memSwapAvg,
                    netDownBytes: $0.netDown,
                    netUpBytes: $0.netUp,
                    diskReadBytes: $0.diskRead,
                    diskWriteBytes: $0.diskWrite,
                    powerAvg: $0.powerAvg,
                    cpuTempAvg: $0.cpuTempAvg,
                    cpuThermalAvg: $0.cpuThermalAvg,
                    fanAvg: $0.fanAvg
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
}
