import SwiftUI
import SwiftData

// MARK: - Event Timeline Section

/// 事件时间线区域，插入 StatisticsView 的 summaryGrid 之后
struct EventTimelineSection: View {
    let range: StatisticsTimeRange
    @State private var events: [SystemEvent] = []
    @State private var totalCount: Int = 0
    @State private var displayLimit: Int = 20

    private let aggregator = StatisticsAggregator()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                EmptyView()
            } else {
                if #available(macOS 26, *) {
                    timelineContent
                        .compatibleGlassEffect(cornerRadius: 16)
                } else {
                    timelineContent
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .onAppear { loadEvents() }
        .onChange(of: range) { _, _ in
            displayLimit = 20
            loadEvents()
        }
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "event.title"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(totalCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Grouped by day
            let grouped = groupByDay(events)
            ForEach(grouped.indices, id: \.self) { index in
                EventTimelineDay(dayLabel: grouped[index].label, events: grouped[index].events)
            }

            // Show more button
            if totalCount > displayLimit {
                HStack {
                    Spacer()
                    Button {
                        displayLimit += 20
                        loadEvents()
                    } label: {
                        Text(String(localized: "event.show-more"))
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Spacer()
                }
            }
        }
        .padding(16)
    }

    private func loadEvents() {
        events = aggregator.queryEvents(range: range, limit: displayLimit)
        totalCount = aggregator.countEvents(range: range)
    }

    private func groupByDay(_ events: [SystemEvent]) -> [(label: String, events: [SystemEvent])] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!

        var groups: [(label: String, events: [SystemEvent])] = []
        var currentDay: Date?
        var currentLabel = ""
        var currentEvents: [SystemEvent] = []

        for event in events {
            let dayStart = calendar.startOfDay(for: event.timestamp)
            let label: String
            if dayStart >= todayStart {
                label = String(localized: "event.today")
            } else if dayStart >= yesterdayStart {
                label = String(localized: "event.yesterday")
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                label = formatter.string(from: event.timestamp)
            }

            if dayStart != currentDay {
                if let _ = currentDay {
                    groups.append((label: currentLabel, events: currentEvents))
                }
                currentDay = dayStart
                currentLabel = label
                currentEvents = [event]
            } else {
                currentEvents.append(event)
            }
        }
        if !currentEvents.isEmpty {
            groups.append((label: currentLabel, events: currentEvents))
        }

        return groups
    }
}

// MARK: - Event Timeline Day

/// 按天分组的事件列表
struct EventTimelineDay: View {
    let dayLabel: String
    let events: [SystemEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Timeline with vertical line
            VStack(alignment: .leading, spacing: 0) {
                ForEach(events, id: \.id) { event in
                    EventTimelineRow(event: event)
                }
            }
            .overlay(alignment: .leading) {
                // Vertical line - aligned to the center of the icon column
                GeometryReader { geo in
                    let lineHeight = geo.size.height - 16
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2, height: max(0, lineHeight))
                        .offset(x: 5, y: 8)
                }
                .frame(width: 12)
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Event Timeline Row

/// 单个事件行
struct EventTimelineRow: View {
    let event: SystemEvent

    private var severity: EventSeverity {
        EventSeverity(rawValue: event.severity) ?? .info
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: event.timestamp)
    }

    private var localizedTitle: String {
        guard let type = SystemEventType(rawValue: event.eventType) else {
            return event.title
        }
        return type.title
    }

    private var localizedDetail: String {
        guard let type = SystemEventType(rawValue: event.eventType) else {
            return event.detail
        }
        // detail 包含动态数值，无法完全重新本地化，但保留原始 detail
        return event.detail
    }

    private var topProcessesList: [String] {
        guard let json = event.topProcesses,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 12)
            .padding(.top, 4)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: severityIcon)
                        .font(.caption)
                        .foregroundStyle(severityColor)
                    Text(localizedTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(timeString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !topProcessesList.isEmpty {
                    HStack(spacing: 4) {
                        Text(String(localized: "event.top-processes") + ":")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(topProcessesList.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let duration = event.duration, duration > 0 {
                    Text(String(localized: "event.duration").replacingOccurrences(of: "{value}", with: formatDuration(duration)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var severityIcon: String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var severityColor: Color {
        switch severity {
        case .critical: return .red
        case .warning: return .yellow
        case .info: return .gray
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            return String(format: "%.0fmin", seconds / 60)
        } else {
            return String(format: "%.1fh", seconds / 3600)
        }
    }
}
