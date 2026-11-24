import AppKit
import SwiftUI

/// 报表窗口顶部工具条：包含动态机型信息、时间范围与前后步进、自定义日历浮窗、粒度指示与导出/打印操作。
struct ReportTopBarView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @ObservedObject private var reportCommands = ReportWindowPresenter.commandState
    let onReload: () -> Void
    let onPrint: () -> Void
    let onExport: (ReportBundleExportFormat) -> Void

    @State private var showCalendarPopover: Bool = false
    @State private var copiedHardwareSheet: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 14) {
            // 左侧：自适应形态图标、设备与系统版本信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.deviceFormFactor.symbolName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(viewModel.snapshot?.meta.deviceName ?? "Mac")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let meta = viewModel.snapshot?.meta {
                    Text("\(meta.modelName) · \(meta.osVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            if viewModel.selectedModule == .machine {
                // 本机规格档案属于静态硬件快照，不随时间范围变化
                staticHardwareControls
            } else {
                timeRangeControls
            }

            // 右侧操作按钮组
            HStack(spacing: 6) {
                ReportToolbarCircleButton(
                    systemImage: "arrow.clockwise",
                    tooltip: String(localized: "stats.report.toolbar.reload.tooltip", defaultValue: "重新载入报表"),
                    isDisabled: false,
                    action: onReload
                )

                ReportToolbarCircleButton(
                    systemImage: "printer",
                    tooltip: String(localized: "stats.report.toolbar.print.tooltip", defaultValue: "打印或保存为 PDF"),
                    isDisabled: !reportCommands.isAvailable,
                    action: onPrint
                )

                exportMenuButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            palette.topBarFill
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    // MARK: - 时间范围控件组

    private var timeRangeOptions: [ReportSegmentOption<TimeRangeTab>] {
        [
            ReportSegmentOption(value: .today, label: ReportTimeRange.today.label),
            ReportSegmentOption(value: .week, label: ReportTimeRange.week.label),
            ReportSegmentOption(value: .month, label: ReportTimeRange.month.label),
            ReportSegmentOption(value: .year, label: ReportTimeRange.year.label),
            ReportSegmentOption(value: .custom, label: String(localized: "stats.range.custom", defaultValue: "自定义")),
        ]
    }

    private var timeRangeControls: some View {
        HStack(spacing: 8) {
            // 放在最左侧（紧贴 Spacer），出现/隐藏或日期长度变化时只向左延伸，
            // 绝不推动右侧的 `<`、时间分段栏、`>` 和粒度标签产生水平跳动。
            customRangeBadge

            ReportToolbarCircleButton(
                systemImage: "chevron.left",
                tooltip: String(localized: "stats.report.range.prev", defaultValue: "上一时段"),
                isDisabled: viewModel.isLoading || viewModel.isAggregating,
                size: 24,
                action: { viewModel.stepRange(by: -1) }
            )

            ReportNavigationPicker(
                title: String(localized: "report.ui.timeRange"),
                selection: Binding(
                    get: { selectedTab },
                    set: { selectTab($0) }
                ),
                options: timeRangeOptions,
                onReselect: { tab in
                    if tab == .custom {
                        showCalendarPopover = true
                    }
                }
            )
            .fixedSize()
            .popover(isPresented: $showCalendarPopover) {
                ReportCustomRangePicker(
                    selectedRange: viewModel.selectedRange,
                    isPresented: $showCalendarPopover,
                    recordedDayKeys: viewModel.recordedDayKeys,
                    onApply: { from, to in
                        viewModel.applyCustomRange(from: from, to: to)
                    }
                )
            }

            ReportToolbarCircleButton(
                systemImage: "chevron.right",
                tooltip: String(localized: "stats.report.range.next", defaultValue: "下一时段"),
                isDisabled: viewModel.isLoading || viewModel.isAggregating || !viewModel.canStepForward,
                size: 24,
                action: { viewModel.stepRange(by: 1) }
            )

            granularityBadge
        }
    }

    /// 锁定三档粒度标签中的最大固有宽度，避免在「分钟粒度 / 小时粒度 / 日粒度」之间切换导致顶栏水平偏移。
    private var granularityBadge: some View {
        let current = viewModel.rangeModel?.granularity
        return ZStack {
            ForEach([ReportSourceGranularity.minutes, .hours, .days], id: \.rawValue) { g in
                Text(g.label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
            }
            if let current {
                Text(current.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(Color.primary.opacity(current == nil ? 0 : 0.06))
        }
    }

    // MARK: - 静态硬件档案工具条

    private var staticHardwareControls: some View {
        HStack(spacing: 10) {
            Text(String(localized: "stats.report.machine.staticBadge", defaultValue: "静态硬件档案"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

            if let hardware = viewModel.snapshot?.hardware, !hardware.categories.isEmpty {
                Button {
                    copyFullHardwareSpec(hardware)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedHardwareSheet ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copiedHardwareSheet
                             ? String(localized: "stats.report.copied", defaultValue: "已复制")
                             : String(localized: "stats.report.machine.copyAll", defaultValue: "复制配置单"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func copyFullHardwareSpec(_ hardware: HardwareInventory) {
        var sections: [String] = []
        for category in hardware.categories {
            let catTitle = category.id == "this-mac" ? String(localized: "report.ui.device") : hwText(category.nameKey)
            var lines: [String] = ["[\(catTitle)]"]
            for group in category.groups {
                lines.append("  \(group.name.resolve(hwText))")
                for fact in group.facts {
                    lines.append("    \(fact.label.resolve(hwText)): \(fact.value ?? "—")")
                }
            }
            sections.append(lines.joined(separator: "\n"))
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
        copiedHardwareSheet = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedHardwareSheet = false
        }
    }

    // MARK: - 多格式导出菜单

    private var exportMenuButton: some View {
        Menu {
            ForEach(ReportBundleExportFormat.allCases) { format in
                Button {
                    onExport(format)
                } label: {
                    Label(format.label, systemImage: iconName(for: format))
                }
            }
        } label: {
            Group {
                if reportCommands.isExporting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!reportCommands.isAvailable)
        .help(String(localized: "stats.report.toolbar.export.tooltip", defaultValue: "导出统计报表"))
        .accessibilityLabel(Text(String(localized: "stats.report.toolbar.export.tooltip")))
    }

    private func iconName(for format: ReportBundleExportFormat) -> String {
        switch format {
        case .pdf: return "doc.richtext"
        case .markdown: return "text.alignleft"
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        }
    }

    // MARK: - 内部辅助方法与状态映射

    private enum TimeRangeTab: Hashable {
        case today
        case week
        case month
        case year
        case custom
    }

    private var selectedTab: TimeRangeTab {
        switch viewModel.selectedRange {
        case .today: return .today
        case .week: return .week
        case .month: return .month
        case .year: return .year
        case .custom: return .custom
        }
    }

    private func selectTab(_ tab: TimeRangeTab) {
        switch tab {
        case .today:
            showCalendarPopover = false
            viewModel.selectRange(.today)
        case .week:
            showCalendarPopover = false
            viewModel.selectRange(.week)
        case .month:
            showCalendarPopover = false
            viewModel.selectRange(.month)
        case .year:
            showCalendarPopover = false
            viewModel.selectRange(.year)
        case .custom:
            showCalendarPopover = true
        }
    }

    @ViewBuilder
    private var customRangeBadge: some View {
        if case .custom(let from, let to) = viewModel.selectedRange {
            Button {
                showCalendarPopover = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(customRangeSummary(from: from, to: to))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .buttonStyle(.plain)
            .help(String(localized: "stats.r.selectRange"))
        }
    }

    private func customRangeSummary(from: Date, to: Date) -> String {
        let calendar = Calendar.current
        let inclusiveTo = calendar.date(byAdding: .day, value: -1, to: to) ?? to
        if calendar.isDate(from, inSameDayAs: inclusiveTo) {
            return from.formatted(.dateTime.month().day())
        }
        return "\(from.formatted(.dateTime.month().day())) – \(inclusiveTo.formatted(.dateTime.month().day()))"
    }
}

private struct ReportToolbarCircleButton: View {
    let systemImage: String
    let tooltip: String
    let isDisabled: Bool
    var size: CGFloat = 26
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size <= 24 ? 10 : 12, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(Color.primary.opacity(isHovered && !isDisabled ? 0.12 : 0.06))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1.0)
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(Text(tooltip))
    }
}
