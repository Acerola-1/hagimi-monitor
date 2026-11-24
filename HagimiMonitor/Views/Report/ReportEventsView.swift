import AppKit
import SwiftUI

/// 异常事件报表视图：展示内存压力与热压力事件流，支持类型过滤、严重度分级与点击跳转到事件时间点。
struct ReportEventsView: View {
    @ObservedObject var viewModel: NativeReportViewModel

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
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
                    ReportNavigationPicker(
                        title: "",
                        selection: $viewModel.eventFilterKind,
                        options: ReportEventFilterKind.allCases.map { ReportSegmentOption(value: $0, label: $0.label) }
                    )
                    .fixedSize()

                    Spacer()
                }

                if events.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyEventsNeutral", defaultValue: "所选时间范围内未检测到内存或热状态异常事件记录"))
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            ReportEventRow(event: event, palette: palette) {
                                viewModel.focusOnEvent(event)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredEvents: [ReportEventItem] {
        guard let all = viewModel.rangeModel?.events else { return [] }
        switch viewModel.eventFilterKind {
        case .all:
            return all
        case .memory:
            return all.filter { $0.kind == .memory }
        case .thermal:
            return all.filter { $0.kind == .thermal }
        }
    }
}

/// 单条压力事件行：整行可点击并跳转锚定对应模块图表的时间窗。
private struct ReportEventRow: View {
    let event: ReportEventItem
    let palette: ReportPalette
    let onOpen: () -> Void

    @State private var isHovered = false

    private var isSameCalendarDay: Bool {
        Calendar.current.isDate(event.start, inSameDayAs: event.end)
    }

    private var severityText: String {
        switch event.kind {
        case .memory:
            return event.worstLevel >= 2
                ? String(localized: "stats.r.severityCritical", defaultValue: "紧急")
                : String(localized: "stats.r.severityWarning", defaultValue: "警告")
        case .thermal:
            return StatisticsDisplayFormat.thermalStateLabel(Double(event.worstLevel))
        }
    }

    private var severityTint: Color {
        switch event.kind {
        case .memory:
            return event.worstLevel >= 2 ? palette.base.severityTint(for: .critical) : palette.base.severityTint(for: .warning)
        case .thermal:
            return event.worstLevel >= 3 ? palette.base.severityTint(for: .critical) : palette.base.severityTint(for: .warning)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                eventIcon(for: event.kind)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.kind.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        badge(text: severityText, tint: severityTint)
                        badge(text: event.state.label, tint: palette.eventStateTint(for: event.state))

                        Spacer()

                        HStack(spacing: 4) {
                            Text(ReportUIHelper.formatDateTime(event.start))
                            Text("~")
                            Text(isSameCalendarDay
                                 ? ReportUIHelper.formatTimeOnly(event.end)
                                 : ReportUIHelper.formatDateTime(event.end))
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Text("\(String(localized: "stats.r.prefixDuration", defaultValue: "持续时长:")) \(StatisticsDisplayFormat.duration(event.pressureSeconds))")
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
                    .fill(isHovered ? palette.cardHoverFill : palette.insetFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.35) : palette.cardBorder, lineWidth: 0.75)
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(event.kind.title))
        .accessibilityHint(Text(String(localized: "stats.r.insight.actionInspectWindow", defaultValue: "定位压力时段")))
        .help(String(localized: "stats.r.insight.actionInspectWindow", defaultValue: "定位压力时段"))
    }

    private func eventIcon(for kind: ReportEventItem.Kind) -> some View {
        Group {
            switch kind {
            case .memory:
                Image(systemName: "memorychip")
                    .foregroundStyle(palette.memory)
            case .thermal:
                Image(systemName: "flame.fill")
                    .foregroundStyle(palette.thermal)
            }
        }
        .font(.system(size: 16))
        .frame(width: 28, height: 28)
        .background(Color.primary.opacity(0.04))
        .clipShape(Circle())
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
