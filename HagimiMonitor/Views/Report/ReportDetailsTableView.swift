import AppKit
import SwiftUI

/// 原始采样数据记录表视图：展示真实底层采样多维指标，具备多列排序、横向平滑滚动、单页定容分页与完整悬浮提示，并支持导出为 CSV、HTML 及 Markdown 表格。
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

    @State private var sortColumn: SortColumn = .date
    @State private var sortAscending: Bool = false
    @State private var currentPage: Int = 0
    @State private var pageSize: Int = 50

    private let pageSizeOptions = [50, 100, 200]

    private var bucketSeconds: Double {
        viewModel.rangeModel?.granularity.bucketSeconds ?? 60.0
    }

    private var allRows: [StatisticsRow] {
        viewModel.rangeModel?.rows ?? []
    }

    private var sortedRows: [StatisticsRow] {
        let bSec = bucketSeconds
        return allRows.sorted { (a: StatisticsRow, b: StatisticsRow) -> Bool in
            let res: Bool
            switch sortColumn {
            case .date:
                res = a.t < b.t
            case .frames:
                res = a.n < b.n
            case .cpuAvg:
                res = (a.cpuAvg ?? 0) < (b.cpuAvg ?? 0)
            case .cpuMax:
                res = (a.cpuMax ?? 0) < (b.cpuMax ?? 0)
            case .gpuAvg:
                res = (a.gpuAvg ?? 0) < (b.gpuAvg ?? 0)
            case .gpuMem:
                res = (a.gpuMemAvg ?? 0) < (b.gpuMemAvg ?? 0)
            case .memUsed:
                res = (a.memUsedAvg ?? 0) < (b.memUsedAvg ?? 0)
            case .memPressure:
                res = (a.memPressureAvg ?? 0) < (b.memPressureAvg ?? 0)
            case .memSwap:
                res = (a.memSwapAvg ?? 0) < (b.memSwapAvg ?? 0)
            case .netDown:
                res = (a.netDown ?? 0) < (b.netDown ?? 0)
            case .netUp:
                res = (a.netUp ?? 0) < (b.netUp ?? 0)
            case .diskRead:
                res = (a.diskRead ?? 0) < (b.diskRead ?? 0)
            case .diskWrite:
                res = (a.diskWrite ?? 0) < (b.diskWrite ?? 0)
            case .power:
                res = (a.powerAvg ?? 0) < (b.powerAvg ?? 0)
            case .temp:
                res = (a.cpuTempAvg ?? 0) < (b.cpuTempAvg ?? 0)
            case .fan:
                res = (a.fanAvg ?? 0) < (b.fanAvg ?? 0)
            case .thermal:
                res = (a.cpuThermalAvg ?? 0) < (b.cpuThermalAvg ?? 0)
            }
            return sortAscending ? res : !res
        }
    }

    private var totalPages: Int {
        max(1, (sortedRows.count + pageSize - 1) / pageSize)
    }

    private var pagedRows: [StatisticsRow] {
        let safePage = min(max(0, currentPage), totalPages - 1)
        let start = safePage * pageSize
        let end = min(start + pageSize, sortedRows.count)
        guard start < sortedRows.count else { return [] }
        return Array(sortedRows[start..<end])
    }

    var body: some View {
        tableCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 主卡片

    private var tableCard: some View {
        ReportCardView(
            title: String(localized: "stats.r.rawRecords", defaultValue: "原始数据"),
            icon: "tablecells"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // 1. 固定顶部操作栏（不随数据行滚动）
                topActionBar

                if allRows.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "所选范围内无历史记录"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 2. 表格主容器（内含吸顶表头与独立垂直滚动数据区）
                    tableView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .padding(.vertical, 2)

                    // 3. 固定底部翻页栏（绝对固定于底部，不随数据滚动）
                    paginationBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 顶部操作栏

    private var topActionBar: some View {
        HStack(spacing: 12) {
            Text(String(localized: "stats.r.rawTotalCount", defaultValue: "共 \(allRows.count) 条采样记录"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            if let granLabel = viewModel.rangeModel?.granularity.label {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(granLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 分页容量选择
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
                .onChange(of: pageSize) { _ in
                    currentPage = 0
                }
            }

            // 导出菜单
            Menu {
                Button {
                    exportData(format: .csv)
                } label: {
                    Label(ReportExportFormat.csv.label, systemImage: "doc.text")
                }

                Button {
                    exportData(format: .html)
                } label: {
                    Label(ReportExportFormat.html.label, systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    exportData(format: .markdown)
                } label: {
                    Label(ReportExportFormat.markdown.label, systemImage: "text.alignleft")
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
            .controlSize(.small)
            .disabled(allRows.isEmpty)
        }
    }

    // MARK: - 表格主视图（横向滚动内套吸顶表头与纵向滚动数据区）

    private var tableView: some View {
        ScrollView([.horizontal], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // 吸顶表头（随水平滚动同步，但在垂直方向严格置顶）
                tableHeaderRow
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Divider()
                    .padding(.vertical, 2)

                // 独立垂直滚动数据区域（表头与翻页栏不随之滚动）
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
            .frame(minWidth: 1540)
        }
    }

    // MARK: - 表头

    private var tableHeaderRow: some View {
        HStack(spacing: 8) {
            sortableHeader("时间", column: .date, width: 130, alignment: .leading)
            sortableHeader("帧数", column: .frames, width: 48, alignment: .trailing)
            sortableHeader("CPU均值", column: .cpuAvg, width: 62, alignment: .trailing)
            sortableHeader("CPU峰值", column: .cpuMax, width: 62, alignment: .trailing)
            plainHeader("P / E 核心", width: 100, alignment: .trailing)
            plainHeader("U / S 态", width: 95, alignment: .trailing)
            sortableHeader("GPU均值", column: .gpuAvg, width: 62, alignment: .trailing)
            sortableHeader("显存已用", column: .gpuMem, width: 75, alignment: .trailing)
            sortableHeader("内存已用", column: .memUsed, width: 80, alignment: .trailing)
            sortableHeader("内存压力", column: .memPressure, width: 62, alignment: .trailing)
            sortableHeader("Swap交换", column: .memSwap, width: 72, alignment: .trailing)
            sortableHeader("网络下行", column: .netDown, width: 80, alignment: .trailing)
            sortableHeader("网络上传", column: .netUp, width: 80, alignment: .trailing)
            sortableHeader("磁盘读速", column: .diskRead, width: 80, alignment: .trailing)
            sortableHeader("磁盘写速", column: .diskWrite, width: 80, alignment: .trailing)
            sortableHeader("整机功耗", column: .power, width: 66, alignment: .trailing)
            plainHeader("电池", width: 60, alignment: .trailing)
            sortableHeader("CPU温度", column: .temp, width: 62, alignment: .trailing)
            sortableHeader("风扇转速", column: .fan, width: 72, alignment: .trailing)
            sortableHeader("热状态", column: .thermal, width: 64, alignment: .center)
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

    // MARK: - 数据行与单元格（支持超出截断与悬停全量显示）

    private func tableDataRow(row: StatisticsRow, bucketSec: Double, isEven: Bool) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(row.t))
        let dateStr = ReportUIHelper.formatDateTime(date)
        let downRate = (row.netDown ?? 0) / max(bucketSec, 1.0)
        let upRate = (row.netUp ?? 0) / max(bucketSec, 1.0)
        let readRate = (row.diskRead ?? 0) / max(bucketSec, 1.0)
        let writeRate = (row.diskWrite ?? 0) / max(bucketSec, 1.0)

        // P/E 核心文本与完整提示
        let peText: String = {
            guard let p = row.cpuPAvg, let e = row.cpuEAvg else { return "—" }
            return String(format: "P %.0f%% · E %.0f%%", p, e)
        }()
        let peFull: String = {
            guard let p = row.cpuPAvg, let e = row.cpuEAvg else { return "无 P/E 核心细分数据" }
            return String(format: "性能核 (P): %.1f%%, 能效核 (E): %.1f%%", p, e)
        }()

        // 用户/系统态
        let usText: String = {
            guard let u = row.cpuUserAvg, let s = row.cpuSysAvg else { return "—" }
            return String(format: "U %.0f%% · S %.0f%%", u, s)
        }()
        let usFull: String = {
            guard let u = row.cpuUserAvg, let s = row.cpuSysAvg else { return "无 CPU 用户/系统态细分" }
            return String(format: "用户态 CPU: %.1f%%, 系统内核态: %.1f%%", u, s)
        }()

        // 电池电量与供电
        let battText: String = {
            if let b = row.battLevelAvg {
                return String(format: "%.0f%%", b)
            }
            if row.acFrac != nil {
                return "AC"
            }
            return "—"
        }()
        let battFull: String = {
            var s = ""
            if let b = row.battLevelAvg {
                s += String(format: "电池电量: %.0f%%", b)
            }
            if let ac = row.acFrac {
                s += (s.isEmpty ? "" : ", ") + String(format: "交流电源占比: %.0f%%", ac * 100)
            }
            if let t = row.battTempAvg {
                s += (s.isEmpty ? "" : ", ") + String(format: "电池包温度: %.1f°C", t)
            }
            return s.isEmpty ? "无电池或电源数据" : s
        }()

        // 热状态
        let thermalStr: String = {
            guard let th = row.cpuThermalAvg else { return "—" }
            if th < 0.05 { return "正常(0)" }
            if th < 0.35 { return "中度(1)" }
            if th < 0.75 { return "严重(2)" }
            return "紧急(3)"
        }()
        let thermalFull: String = {
            guard let th = row.cpuThermalAvg else { return "无系统热状态档位数据" }
            return String(format: "macOS 官方热状态: %@ (内部热应力值: %.2f)", thermalStr, th)
        }()

        return HStack(spacing: 8) {
            // 时间
            cell(
                text: dateStr,
                fullText: "采样时间: \(dateStr) (Unix: \(row.t))",
                width: 130,
                alignment: .leading
            )

            // 采样帧数
            cell(
                text: "\(row.n)",
                fullText: "时间桶内采集硬件帧数: \(row.n) 次",
                width: 48,
                alignment: .trailing,
                color: .secondary
            )

            // CPU 均值
            cell(
                text: row.cpuAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.cpuAvg.map { String(format: "CPU 平均使用率: %.2f%%", $0) } ?? "无 CPU 均值",
                width: 62,
                alignment: .trailing,
                color: (row.cpuAvg ?? 0) >= 80 ? Color(hex: 0xFF3B30) : .primary
            )

            // CPU 峰值
            cell(
                text: row.cpuMax.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.cpuMax.map { String(format: "CPU 瞬时最高峰值: %.2f%%", $0) } ?? "无 CPU 峰值",
                width: 62,
                alignment: .trailing,
                color: (row.cpuMax ?? 0) >= 90 ? Color(hex: 0xFF9500) : .secondary
            )

            // P / E 核心
            cell(
                text: peText,
                fullText: peFull,
                width: 100,
                alignment: .trailing
            )

            // 用户态 / 系统态
            cell(
                text: usText,
                fullText: usFull,
                width: 95,
                alignment: .trailing
            )

            // GPU 均值
            cell(
                text: row.gpuAvg.map { String(format: "%.1f%%", $0) } ?? "—",
                fullText: row.gpuAvg.map { String(format: "GPU 平均使用率: %.2f%% (峰值: %@)", $0, row.gpuMax.map { String(format: "%.1f%%", $0) } ?? "—") } ?? "无 GPU 采样",
                width: 62,
                alignment: .trailing
            )

            // 动态显存
            cell(
                text: row.gpuMemAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.gpuMemAvg.map { String(format: "统一架构动态显存: %@ (%.0f 字节)", ReportUIHelper.formatBytes($0), $0) } ?? "无显存分配记录",
                width: 75,
                alignment: .trailing
            )

            // 内存已用
            cell(
                text: row.memUsedAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.memUsedAvg.map { String(format: "物理内存已用: %@, 占用比例: %@", ReportUIHelper.formatBytes($0), row.memPctAvg.map { String(format: "%.1f%%", $0) } ?? "—") } ?? "无内存采样",
                width: 80,
                alignment: .trailing
            )

            // 内存压力
            cell(
                text: row.memPressureAvg.map { String(format: "%.0f%%", $0) } ?? "—",
                fullText: row.memPressureAvg.map { String(format: "macOS 内存压力: %.1f%%", $0) } ?? "无内存压力",
                width: 62,
                alignment: .trailing,
                color: (row.memPressureAvg ?? 0) >= 50 ? Color(hex: 0xFF3B30) : ((row.memPressureAvg ?? 0) >= 20 ? Color(hex: 0xFF9500) : .primary)
            )

            // Swap 交换
            cell(
                text: row.memSwapAvg.map { ReportUIHelper.formatBytes($0) } ?? "—",
                fullText: row.memSwapAvg.map { String(format: "磁盘交换分区 (Swap): %@", ReportUIHelper.formatBytes($0)) } ?? "无 Swap 记录",
                width: 72,
                alignment: .trailing,
                color: (row.memSwapAvg ?? 0) > 10 * 1024 * 1024 ? Color(hex: 0xFF9500) : .primary
            )

            // 网络下行速率
            cell(
                text: row.netDown != nil ? ReportUIHelper.formatBytesRate(downRate) : "—",
                fullText: row.netDown != nil ? String(format: "网络下行速率: %@ (区间累计: %@, 瞬时峰值: %@)", ReportUIHelper.formatBytesRate(downRate), ReportUIHelper.formatBytes(row.netDown ?? 0), row.netDownPeak.map { ReportUIHelper.formatBytesRate($0) } ?? "—") : "无下行网络流量",
                width: 80,
                alignment: .trailing
            )

            // 网络上传速率
            cell(
                text: row.netUp != nil ? ReportUIHelper.formatBytesRate(upRate) : "—",
                fullText: row.netUp != nil ? String(format: "网络上行速率: %@ (区间累计: %@, 瞬时峰值: %@)", ReportUIHelper.formatBytesRate(upRate), ReportUIHelper.formatBytes(row.netUp ?? 0), row.netUpPeak.map { ReportUIHelper.formatBytesRate($0) } ?? "—") : "无上行网络流量",
                width: 80,
                alignment: .trailing
            )

            // 磁盘读速
            cell(
                text: row.diskRead != nil ? ReportUIHelper.formatBytesRate(readRate) : "—",
                fullText: row.diskRead != nil ? String(format: "磁盘读取速率: %@ (区间累计: %@, 瞬时峰值: %@)", ReportUIHelper.formatBytesRate(readRate), ReportUIHelper.formatBytes(row.diskRead ?? 0), row.diskReadPeak.map { ReportUIHelper.formatBytesRate($0) } ?? "—") : "无磁盘读取活动",
                width: 80,
                alignment: .trailing
            )

            // 磁盘写速
            cell(
                text: row.diskWrite != nil ? ReportUIHelper.formatBytesRate(writeRate) : "—",
                fullText: row.diskWrite != nil ? String(format: "磁盘写入速率: %@ (区间累计: %@, 瞬时峰值: %@)", ReportUIHelper.formatBytesRate(writeRate), ReportUIHelper.formatBytes(row.diskWrite ?? 0), row.diskWritePeak.map { ReportUIHelper.formatBytesRate($0) } ?? "—") : "无磁盘写入活动",
                width: 80,
                alignment: .trailing
            )

            // 整机功耗
            cell(
                text: row.powerAvg.map { String(format: "%.1f W", $0) } ?? "—",
                fullText: row.powerAvg.map { String(format: "系统平均功耗: %.1f W (最高瞬时: %@)", $0, row.powerMax.map { String(format: "%.1f W", $0) } ?? "—") } ?? "无功耗采样",
                width: 66,
                alignment: .trailing
            )

            // 电池
            cell(
                text: battText,
                fullText: battFull,
                width: 60,
                alignment: .trailing
            )

            // CPU 温度
            cell(
                text: row.cpuTempAvg.map { String(format: "%.0f°C", $0) } ?? "—",
                fullText: row.cpuTempAvg.map { String(format: "CPU 封装传感器温度: %.1f°C", $0) } ?? "无芯片温度记录",
                width: 62,
                alignment: .trailing,
                color: (row.cpuTempAvg ?? 0) >= 85 ? Color(hex: 0xFF3B30) : ((row.cpuTempAvg ?? 0) >= 75 ? Color(hex: 0xFF9500) : .primary)
            )

            // 风扇转速
            cell(
                text: row.fanAvg.map { String(format: "%.0f RPM", $0) } ?? "—",
                fullText: row.fanAvg.map { String(format: "风扇转速均值: %.0f RPM (最高: %@)", $0, row.fanMax.map { String(format: "%.0f RPM", $0) } ?? "—") } ?? "无物理风扇或处于沙盒受限",
                width: 72,
                alignment: .trailing
            )

            // 热状态
            cell(
                text: thermalStr,
                fullText: thermalFull,
                width: 64,
                alignment: .center,
                color: (row.cpuThermalAvg ?? 0) > 0.35 ? Color(hex: 0xFF3B30) : .secondary
            )
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isEven ? Color.primary.opacity(0.02) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// 统一单元格：单行截断省略，鼠标悬浮即弹出原生完整信息浮窗
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
            Text("显示第 \(startIdx + 1) - \(endIdx) 条，共 \(total) 条采样")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            // 首页
            Button {
                currentPage = 0
            } label: {
                Image(systemName: "chevron.backward.2")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage == 0)

            // 上一页
            Button {
                if safePage > 0 { currentPage = safePage - 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage == 0)

            Text("第 \(safePage + 1) / \(totalPages) 页")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // 下一页
            Button {
                if safePage < totalPages - 1 { currentPage = safePage + 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .disabled(safePage >= totalPages - 1)

            // 末页
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
                return "\(df.string(from: m.from)) 至 \(df.string(from: m.to))"
            }
            return "当前筛选范围"
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
