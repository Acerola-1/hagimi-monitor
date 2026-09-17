import AppKit
import SwiftUI

/// 报表窗口顶部工具条：包含机型信息、时间范围选择器、自定义日历浮窗、粒度指示与操作按钮。
struct ReportTopBarView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    let onReload: () -> Void
    let onPrint: () -> Void
    let onExport: () -> Void

    @State private var showCalendarPopover: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            // 左侧：设备与系统版本信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "macbook.gen2")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(viewModel.snapshot?.meta.deviceName ?? "Mac")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                if let meta = viewModel.snapshot?.meta {
                    Text("\(meta.modelName) · \(meta.osVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 时间范围一体化导航栏（方案 B：永久固定 5 个项，不动态增删格子）
            ReportNavigationPicker(
                title: String(localized: "report.ui.timeRange"),
                selection: Binding(
                    get: { selectedTab },
                    set: { selectTab($0) }
                )
            ) {
                Text(ReportTimeRange.today.label).tag(TimeRangeTab.today)
                Text(ReportTimeRange.week.label).tag(TimeRangeTab.week)
                Text(ReportTimeRange.month.label).tag(TimeRangeTab.month)
                Text(ReportTimeRange.year.label).tag(TimeRangeTab.year)
                Text(String(localized: "stats.range.custom", defaultValue: "自定义")).tag(TimeRangeTab.custom)
            }
            .fixedSize()
            .simultaneousGesture(
                TapGesture().onEnded {
                    if selectedTab == .custom {
                        showCalendarPopover = true
                    }
                }
            )
            .popover(isPresented: $showCalendarPopover) {
                ReportCustomRangePicker(
                    selectedRange: viewModel.selectedRange,
                    isPresented: $showCalendarPopover,
                    onApply: { from, to in
                        viewModel.applyCustomRange(from: from, to: to)
                    }
                )
            }

            // 自定义范围激活时展示的具体起止日期徽章，点击可重新打开日历修改
            customRangeBadge

            // 当前数据粒度指示徽章
            if let granularity = viewModel.rangeModel?.granularity {
                Text(granularity.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    }
            }

            // 右侧操作按钮组
            HStack(spacing: 6) {
                Button(action: onReload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(String(localized: "stats.report.toolbar.reload.tooltip", defaultValue: "重新载入报表"))
                .accessibilityLabel(Text(String(localized: "stats.report.toolbar.reload.tooltip")))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.06)))

                Button(action: onPrint) {
                    Image(systemName: "printer")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(String(localized: "stats.report.toolbar.print.tooltip", defaultValue: "打印或保存为 PDF"))
                .accessibilityLabel(Text(String(localized: "stats.report.toolbar.print.tooltip")))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.06)))

                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help(String(localized: "stats.report.toolbar.export.tooltip", defaultValue: "另存为 HTML 文件"))
                .accessibilityLabel(Text(String(localized: "stats.report.toolbar.export.tooltip")))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.06)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.5)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
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
        return "\(from.formatted(.dateTime.month().day())) – \(inclusiveTo.formatted(.dateTime.month().day()))"
    }
}
