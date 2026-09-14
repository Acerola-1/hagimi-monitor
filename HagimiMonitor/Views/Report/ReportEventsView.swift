import AppKit
import SwiftUI

/// 异常事件报表视图：展示内存压力与热压力事件流，支持类型过滤与生命周期状态标记。
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
            title: String(localized: "stats.r.secEvents", defaultValue: "系统压力与异常事件"),
            icon: "exclamationmark.triangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // 筛选过滤器
                Picker("", selection: $filterKind) {
                    ForEach(EventFilterKind.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                // R04: 中性空态，不臆断“系统稳定/运行良好”
                if events.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyEventsNeutral", defaultValue: "所选时间范围内未检测到内存或热状态异常事件记录"))
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            eventCard(event: event)
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

    private func eventCard(event: ReportEventItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 事件类型图标
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
                    Text("持续时长: \(ReportUIHelper.formatHours(event.pressureSeconds))")
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
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
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
