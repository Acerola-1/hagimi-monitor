import AppKit
import SwiftUI

/// 异常事件报表视图：展示内存压力与热压力事件流，支持类型过滤与生命周期状态标记。
/// 本页是事件流的索引，每行可点击直达事件来源模块。
struct ReportEventsView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var filterKind: EventFilterKind = .all

    enum EventFilterKind: String, CaseIterable, Identifiable {
        case all
        case memory
        case thermal

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return String(localized: "stats.r.allEvents", defaultValue: "全部事件")
            case .memory: return String(localized: "stats.r.alertMem", defaultValue: "内存压力")
            case .thermal: return String(localized: "stats.r.alertThermal", defaultValue: "热压力")
            }
        }
    }

    var body: some View {
        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            eventsCard
        }
        .frame(maxWidth: .infinity)
    }

    private var eventsCard: some View {
        let events = filteredEvents

        return ReportCardView(
            title: String(localized: "stats.r.secEvents", defaultValue: "压力警告"),
            icon: "exclamationmark.triangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // 分类切换选择器：与应用排行完全一致，嵌入卡片内部使用 ReportNavigationPicker
                    ReportNavigationPicker(
                        title: "",
                        selection: $filterKind
                    ) {
                        ForEach(EventFilterKind.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .fixedSize()

                    Spacer()
                }

                // R04: 中性空态，不臆断“系统稳定/运行良好”
                if events.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyEventsNeutral", defaultValue: "所选时间范围内未检测到内存或热状态异常事件记录"))
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            ReportEventRow(event: event) {
                                navigateTo(event.kind == .memory ? .memory : .thermal)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredEvents: [ReportEventItem] {
        guard let all = viewModel.rangeModel?.events else { return [] }
        switch filterKind {
        case .all:
            return all
        case .memory:
            return all.filter { $0.kind == .memory }
        case .thermal:
            return all.filter { $0.kind == .thermal }
        }
    }

    private func navigateTo(_ module: ReportNavigationModule) {
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.selectedModule = module
        }
    }
}

/// 单条压力事件行：整行可点击。事件流只说明「哪一类何时出了什么事」，
/// 下一步入口必须在这一行上，否则用户得回侧栏自己再找一遍模块。
private struct ReportEventRow: View {
    let event: ReportEventItem
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                eventIcon(for: event.kind)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.kind.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        statusBadge(for: event.state)

                        Spacer()

                        // 时间信息
                        HStack(spacing: 4) {
                            Text(ReportUIHelper.formatDateTime(event.start))
                            Text("~")
                            Text(ReportUIHelper.formatTimeOnly(event.end))
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }

                    // 持续时间与峰值描述
                    HStack(spacing: 12) {
                        Text("\(String(localized: "stats.r.prefixDuration", defaultValue: "持续时长:")) \(ReportUIHelper.formatHours(event.pressureSeconds))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if !event.detailText.isEmpty {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(event.detailText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.7 : 0.4))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(event.kind.title))
        .accessibilityHint(Text(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细")))
        .help(String(localized: "stats.process.view-details.btn", defaultValue: "查看明细"))
    }

    private func eventIcon(for kind: ReportEventItem.Kind) -> some View {
        Group {
            switch kind {
            case .memory:
                Image(systemName: "memorychip")
                    .foregroundStyle(ReportUIHelper.memoryColor)
            case .thermal:
                Image(systemName: "flame.fill")
                    .foregroundStyle(ReportUIHelper.thermalColor)
            }
        }
        .font(.system(size: 16))
        .frame(width: 28, height: 28)
        .background(Color.primary.opacity(0.04))
        .clipShape(Circle())
    }

    private func statusBadge(for state: ReportEventItem.State) -> some View {
        let color: Color = {
            switch state {
            case .ongoing: return Color.red
            case .interrupted: return Color.orange
            case .recovered: return Color.green
            }
        }()

        return Text(state.label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
