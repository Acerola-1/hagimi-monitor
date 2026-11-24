import AppKit
import SwiftUI

/// 原始采样数据记录表视图：支持异常快捷筛选、多列空值安全排序、全英文/中文国际化、行复制与 CSV/Markdown/JSON 导出。
struct ReportDetailsTableView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    enum SortColumn {
        case date
        case frames
        case cpuAvg
        case cpuMax
        case gpuAvg
        case gpuMem
        case memUsed
        case memPressure
        case memSwap
        case netDown
        case netUp
        case diskRead
        case diskWrite
        case power
        case temp
        case fan
        case thermal
    }

    enum QuickFilter: String, CaseIterable, Identifiable {
        case all
        case highCpu
        case memPressure
        case thermalAnomaly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return String(localized: "stats.r.filter.all", defaultValue: "全部")
            case .highCpu: return String(localized: "stats.r.filter.highCpu", defaultValue: "高 CPU ≥85%")
            case .memPressure: return String(localized: "stats.r.filter.memPressure", defaultValue: "内存压力")
            case .thermalAnomaly: return String(localized: "stats.r.filter.thermal", defaultValue: "热压力异常")
            }
        }
    }

    @State private var sortColumn: SortColumn = .date
    @State private var sortAscending: Bool = false
    @State private var quickFilter: QuickFilter = .all
    @State private var currentPage: Int = 0
    @State private var pageSize: Int = 50
    @State private var hoveredRowID: Int64?

    private let pageSizeOptions = [50, 100, 200]

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    private var bucketSeconds: Double {
        viewModel.rangeModel?.granularity.bucketSeconds ?? 60.0
    }

    private var allRows: [StatisticsRow] {
        viewModel.rangeModel?.rows ?? []
    }

    private var filteredRows: [StatisticsRow] {
        switch quickFilter {
        case .all:
            return allRows
        case .highCpu:
            return allRows.filter { ($0.cpuAvg ?? 0) >= 85 || ($0.cpuMax ?? 0) >= 90 }
        case .memPressure:
            return allRows.filter { ($0.memWarnS ?? 0) > 0 || ($0.memCritS ?? 0) > 0 || ($0.memPressureAvg ?? 0) >= 50 }
        case .thermalAnomaly:
            return allRows.filter {
                (StatisticsDisplayFormat.thermalLevelIndex($0.cpuThermalAvg) ?? 0) >= 1
                    || ($0.thSeriousS ?? 0) > 0 || ($0.thCritS ?? 0) > 0
            }
        }
    }

    private var sortedRows: [StatisticsRow] {
        func compareOptional(_ lhs: Double?, _ rhs: Double?) -> Bool {
            switch (lhs, rhs) {
            case let (l?, r?):
                return sortAscending ? (l < r) : (l > r)
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return false
            }
        }

        return filteredRows.sorted { a, b in
            switch sortColumn {
            case .date:
                return sortAscending ? (a.t < b.t) : (a.t > b.t)
            case .frames:
                return sortAscending ? (a.n < b.n) : (a.n > b.n)
            case .cpuAvg: return compareOptional(a.cpuAvg, b.cpuAvg)
            case .cpuMax: return compareOptional(a.cpuMax, b.cpuMax)
            case .gpuAvg: return compareOptional(a.gpuAvg, b.gpuAvg)
            case .gpuMem: return compareOptional(a.gpuMemAvg, b.gpuMemAvg)
            case .memUsed: return compareOptional(a.memUsedAvg, b.memUsedAvg)
            case .memPressure: return compareOptional(a.memPressureAvg, b.memPressureAvg)
            case .memSwap: return compareOptional(a.memSwapAvg, b.memSwapAvg)
            case .netDown: return compareOptional(a.netDown, b.netDown)
            case .netUp: return compareOptional(a.netUp, b.netUp)
            case .diskRead: return compareOptional(a.diskRead, b.diskRead)
            case .diskWrite: return compareOptional(a.diskWrite, b.diskWrite)
            case .power: return compareOptional(a.powerAvg, b.powerAvg)
            case .temp: return compareOptional(a.cpuTempAvg, b.cpuTempAvg)
            case .fan: return compareOptional(a.fanAvg, b.fanAvg)
            case .thermal: return compareOptional(a.cpuThermalAvg, b.cpuThermalAvg)
            }
        }
    }

    private var totalPages: Int {
        max(1, (sortedRows.count + pageSize - 1) / pageSize)
    }

    private var pagedRows: [StatisticsRow] {
        let rows = sortedRows
        let safePage = min(max(0, currentPage), max(0, (rows.count + pageSize - 1) / pageSize - 1))
        let start = safePage * pageSize
        let end = min(start + pageSize, rows.count)
        guard start < rows.count else { return [] }
        return Array(rows[start..<end])
    }

    var body: some View {
        tableCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: viewModel.rangeModel?.from) { _, _ in currentPage = 0 }
            .onChange(of: viewModel.rangeModel?.to) { _, _ in currentPage = 0 }
            .onChange(of: quickFilter) { _, _ in currentPage = 0 }
    }

    // MARK: - 主卡片

    private var tableCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.rawRecords", defaultValue: "原始数据"),
            icon: "tablecells"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                topActionBar

                if allRows.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无历史记录"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredRows.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.filterEmpty", defaultValue: "当前筛选条件下无匹配采样记录"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    tableView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .padding(.vertical, 2)

                    paginationBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 顶部操作栏

    private var topActionBar: some View {
        HStack(spacing: 12) {
            Text(String(format: String(localized: "stats.r.rawCountSummary", defaultValue: "共 %d 条采样"), filteredRows.count))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let granLabel = viewModel.rangeModel?.granularity.label {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(granLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // 快捷异常筛选胶囊
            HStack(spacing: 6) {
                ForEach(QuickFilter.allCases) { filter in
                    let isSelected = quickFilter == filter
                    Button {
                        quickFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(isSelected ? Color.accentColor : palette.insetFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 6)

            Spacer()

            HStack(spacing: 4) {
                Text(String(localized: "stats.r.pageSize", defaultValue: "每页"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Picker("", selection: $pageSize) {
                    ForEach(pageSizeOptions, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 70)
                .onChange(of: pageSize) { _, _ in
                    currentPage = 0
                }
            }

            Menu {
                ForEach(ReportExportFormat.allCases) { format in
                    Button {
                        exportData(format: format)
                    } label: {
                        Label(format.label, systemImage: exportIcon(for: format))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                    Text(String(localized: "stats.r.exportTableBtn", defaultValue: "导出表格..."))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .menuStyle(.borderedButton)
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .disabled(sortedRows.isEmpty)
        }
    }

    private func exportIcon(for format: ReportExportFormat) -> String {
        switch format {
        case .csv: return "doc.text"
        case .markdown: return "text.alignleft"
        case .json: return "curlybraces"
        }
    }

    // MARK: - 表格主视图

    private var tableView: some View {
        ScrollView([.horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                tableHeaderRow
                    .background(palette.insetFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Divider()
                    .padding(.vertical, 2)

                ScrollView(.vertical, showsIndicators: true) {
                    let bSec = bucketSeconds
                    let rows = pagedRows
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            tableDataRow(row: row, bucketSec: bSec, isEven: index.isMultiple(of: 2))
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 1560)
        }
    }

    // MARK: - 表头

    private var tableHeaderRow: some View {
        HStack(spacing: 8) {
            sortableHeader(String(localized: "stats.r.tbl.time", defaultValue: "时间"), column: .date, width: 130, alignment: .leading)
            sortableHeader(String(localized: "stats.r.tbl.frames", defaultValue: "帧数"), column: .frames, width: 48, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.cpuAvg", defaultValue: "CPU均值"), column: .cpuAvg, width: 64, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.cpuMax", defaultValue: "CPU峰值"), column: .cpuMax, width: 64, alignment: .trailing)
            plainHeader(String(localized: "stats.r.tbl.peCore", defaultValue: "P / E 核心"), width: 100, alignment: .trailing)
            plainHeader(String(localized: "stats.r.tbl.usMode", defaultValue: "U / S 态"), width: 95, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.gpuAvg", defaultValue: "GPU均值"), column: .gpuAvg, width: 64, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.gpuMem", defaultValue: "显存已用"), column: .gpuMem, width: 75, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.memUsed", defaultValue: "内存已用"), column: .memUsed, width: 80, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.memPressure", defaultValue: "内存压力"), column: .memPressure, width: 64, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.swap", defaultValue: "Swap交换"), column: .memSwap, width: 72, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.netDown", defaultValue: "网络下行"), column: .netDown, width: 80, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.netUp", defaultValue: "网络上传"), column: .netUp, width: 80, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.diskRead", defaultValue: "磁盘读速"), column: .diskRead, width: 80, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.diskWrite", defaultValue: "磁盘写速"), column: .diskWrite, width: 80, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.power", defaultValue: "整机功耗"), column: .power, width: 66, alignment: .trailing)
            plainHeader(String(localized: "stats.r.tbl.battery", defaultValue: "电池"), width: 60, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.temp", defaultValue: "CPU温度"), column: .temp, width: 62, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.fan", defaultValue: "风扇转速"), column: .fan, width: 72, alignment: .trailing)
            sortableHeader(String(localized: "stats.r.tbl.thermal", defaultValue: "热状态"), column: .thermal, width: 68, alignment: .center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    private func sortableHeader(_ title: String, column: SortColumn, width: CGFloat, alignment: Alignment) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = (column == .date) ? false : true
            }
            currentPage = 0
        } label: {
            HStack(spacing: 3) {
                if alignment == .trailing && sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(title)
                    .font(.system(size: 11, weight: sortColumn == column ? .bold : .semibold))
                    .foregroundStyle(sortColumn == column ? Color.accentColor : .primary)

                if alignment != .trailing && sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func plainHeader(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: width, alignment: alignment)
    }

    // MARK: - 数据行与单元格

    private func tableDataRow(row: StatisticsRow, bucketSec: Double, isEven: Bool) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(row.t))
        let dateStr = ReportUIHelper.formatDateTime(date)
        let downRate = (row.netDown ?? 0) / max(bucketSec, 1.0)
        let upRate = (row.netUp ?? 0) / max(bucketSec, 1.0)
        let readRate = (row.diskRead ?? 0) / max(bucketSec, 1.0)
        let writeRate = (row.diskWrite ?? 0) / max(bucketSec, 1.0)

        let peText: String = {
            guard let p = row.cpuPAvg, let e = row.cpuEAvg else { return "—" }
            return String(format: "P %.0f%% · E %.0f%%", p, e)
        }()

        let usText: String = {
            guard let u = row.cpuUserAvg, let s = row.cpuSysAvg else { return "—" }
            return String(format: "U %.0f%% · S %.0f%%", u, s)
        }()

        let battText: String = {
            if let b = row.battLevelAvg {
                return String(format: "%.0f%%", b)
            }
            if row.acFrac != nil {
                return "AC"
            }
            return "—"
        }()

        // 热状态严格使用 0~3 档位单源定义（修复原 < 0.05/0.35/0.75 误判为紧急 Bug）
        let thermalIdx = StatisticsDisplayFormat.thermalLevelIndex(row.cpuThermalAvg)
        let thermalStr = ReportDataExporter.fmtThermal(row.cpuThermalAvg)
        let thermalColor: Color = {
            guard let thermalIdx else { return .secondary }
            return thermalIdx == 0 ? .secondary : palette.thermalLevelTint(thermalIdx)
        }()

        let isHovered = hoveredRowID == row.id

        return HStack(spacing: 8) {
            cell(text: dateStr, fullText: "\(dateStr) (Unix: \(row.t))", width: 130, alignment: .leading)
            cell(text: "\(row.n)", fullText: "\(row.n)", width: 48, alignment: .trailing, color: .secondary)
            cell(
                text: row.cpuAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.cpuAvg.map { String(format: "CPU Avg: %.2f%%", $0) } ?? "—",
                width: 64,
                alignment: .trailing,
                color: (row.cpuAvg ?? 0) >= 85 ? palette.base.severityTint(for: .warning) : .primary
            )
            cell(
                text: row.cpuMax.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.cpuMax.map { String(format: "CPU Peak: %.2f%%", $0) } ?? "—",
                width: 64,
                alignment: .trailing,
                color: (row.cpuMax ?? 0) >= 90 ? palette.cpuPeak : .secondary
            )
            cell(text: peText, fullText: peText, width: 100, alignment: .trailing)
            cell(text: usText, fullText: usText, width: 95, alignment: .trailing)
            cell(
                text: row.gpuAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.gpuAvg.map { String(format: "GPU: %.2f%% (Peak: %@)", $0, row.gpuMax.map { String(format: "%.1f%%", $0) } ?? "—") } ?? "—",
                width: 64,
                alignment: .trailing
            )
            cell(
                text: row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                width: 75,
                alignment: .trailing
            )
            cell(
                text: row.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.memUsedAvg.map { "\(ReportUIHelper.formatBytes($0)) (\(row.memPctAvg.map { String(format: "%.1f%%", $0) } ?? "—"))" } ?? "—",
                width: 80,
                alignment: .trailing
            )
            cell(
                text: row.memPressureAvg.map { String(format: "%.0f%%", $0) } ?? "—",
                fullText: row.memPressureAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                width: 64,
                alignment: .trailing,
                color: (row.memPressureAvg ?? 0) >= 60 ? palette.base.severityTint(for: .critical) : ((row.memPressureAvg ?? 0) >= 35 ? palette.base.severityTint(for: .warning) : .primary)
            )
            cell(
                text: row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                width: 72,
                alignment: .trailing,
                color: (row.memSwapAvg ?? 0) > 512 * 1024 * 1024 ? palette.base.severityTint(for: .warning) : .primary
            )
            cell(
                text: row.netDown != nil ? ReportUIHelper.formatBytesRate(downRate) : "—",
                fullText: row.netDown != nil ? "\(ReportUIHelper.formatBytesRate(downRate)) (Σ \(ReportUIHelper.formatVolume(row.netDown ?? 0)))" : "—",
                width: 80,
                alignment: .trailing
            )
            cell(
                text: row.netUp != nil ? ReportUIHelper.formatBytesRate(upRate) : "—",
                fullText: row.netUp != nil ? "\(ReportUIHelper.formatBytesRate(upRate)) (Σ \(ReportUIHelper.formatVolume(row.netUp ?? 0)))" : "—",
                width: 80,
                alignment: .trailing
            )
            cell(
                text: row.diskRead != nil ? ReportUIHelper.formatBytesRate(readRate) : "—",
                fullText: row.diskRead != nil ? "\(ReportUIHelper.formatBytesRate(readRate)) (Σ \(ReportUIHelper.formatVolume(row.diskRead ?? 0)))" : "—",
                width: 80,
                alignment: .trailing
            )
            cell(
                text: row.diskWrite != nil ? ReportUIHelper.formatBytesRate(writeRate) : "—",
                fullText: row.diskWrite != nil ? "\(ReportUIHelper.formatBytesRate(writeRate)) (Σ \(ReportUIHelper.formatVolume(row.diskWrite ?? 0)))" : "—",
                width: 80,
                alignment: .trailing
            )
            cell(
                text: row.powerAvg.map { String(format: "%.1f W", $0) } ?? "—",
                fullText: row.powerAvg.map { String(format: "%.1f W (Peak: %@)", $0, row.powerMax.map { String(format: "%.1f W", $0) } ?? "—") } ?? "—",
                width: 66,
                alignment: .trailing
            )
            cell(text: battText, fullText: battText, width: 60, alignment: .trailing)
            cell(
                text: row.cpuTempAvg.map { String(format: "%.0f°C", $0) } ?? "—",
                fullText: row.cpuTempAvg.map { String(format: "%.1f°C", $0) } ?? "—",
                width: 62,
                alignment: .trailing,
                color: (row.cpuTempAvg ?? 0) >= 85 ? palette.base.severityTint(for: .critical) : ((row.cpuTempAvg ?? 0) >= 75 ? palette.base.severityTint(for: .warning) : .primary)
            )
            cell(
                text: row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—",
                fullText: row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—",
                width: 72,
                alignment: .trailing
            )
            cell(
                text: thermalStr,
                fullText: ReportUIHelper.formatThermalLevel(row.cpuThermalAvg),
                width: 68,
                alignment: .center,
                color: thermalColor
            )
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.08) : (isEven ? Color.primary.opacity(0.025) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { hovering in
            hoveredRowID = hovering ? row.id : (hoveredRowID == row.id ? nil : hoveredRowID)
        }
        .contextMenu {
            Button {
                let summary = ReportDataExporter.generateCSV(rows: [row], bucketSeconds: bucketSec)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary, forType: .string)
            } label: {
                Label(String(localized: "stats.r.copyRow", defaultValue: "复制该行数据"), systemImage: "doc.on.doc")
            }
        }
    }

    private func cell(
        text: String,
        fullText: String,
        width: CGFloat,
        alignment: Alignment,
        color: Color = .primary
    ) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .help(fullText)
    }

    // MARK: - 分页控制栏

    private var paginationBar: some View {
        let total = sortedRows.count
        let safePage = min(max(0, currentPage), totalPages - 1)
        let startIdx = safePage * pageSize
        let endIdx = min(startIdx + pageSize, total)

        return HStack {
            Text(String(format: String(localized: "stats.r.paginationRange", defaultValue: "显示第 %d - %d 条，共 %d 条"), startIdx + 1, endIdx, total))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                currentPage = 0
            } label: {
                Image(systemName: "chevron.backward.2")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage == 0)

            Button {
                if safePage > 0 { currentPage = safePage - 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage == 0)

            Text(String(format: String(localized: "stats.r.paginationPage", defaultValue: "第 %d / %d 页"), safePage + 1, totalPages))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            Button {
                if safePage < totalPages - 1 { currentPage = safePage + 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage >= totalPages - 1)

            Button {
                currentPage = totalPages - 1
            } label: {
                Image(systemName: "chevron.forward.2")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage >= totalPages - 1)
        }
        .padding(.top, 4)
    }

    // MARK: - 导出方法

    private func exportData(format: ReportExportFormat) {
        let rows = sortedRows
        guard !rows.isEmpty else { return }
        let timeRangeDesc: String = {
            if let m = viewModel.rangeModel {
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                return "\(df.string(from: m.from)) - \(df.string(from: m.to))"
            }
            return "Filtered"
        }()

        let window = NSApp.keyWindow ?? NSApp.mainWindow
        ReportDataExporter.export(
            format: format,
            rows: rows,
            bucketSeconds: bucketSeconds,
            meta: timeRangeDesc,
            window: window
        )
    }
}
