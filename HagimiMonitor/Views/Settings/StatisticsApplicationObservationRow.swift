import AppKit
import SwiftUI

/// 应用高负载观测项视图，展示应用名称、图标、主指标及展开明细。
struct StatisticsApplicationObservationRow: View {
    let group: ProcessAppAlertGroup
    let palette: MonitorPalette
    /// 打开该应用详情的动作；由设置页注入，携带范围与应用/指标上下文。
    let openDetail: (String, ProcessAlertEpisode.Metric) -> Void
    @State private var isExpanded = false
    @State private var icon: NSImage?

    private var episodes: [ProcessAlertEpisode] {
        group.episodes.sorted {
            if $0.metric == $1.metric { return $0.startedAt < $1.startedAt }
            return Self.metricOrder($0.metric) < Self.metricOrder($1.metric)
        }
    }

    /// 主指标：按超出门槛的相对程度选取最高者展示。
    private var primaryEpisode: ProcessAlertEpisode? {
        episodes.max { lhs, rhs in
            Self.relativeAttention(lhs) < Self.relativeAttention(rhs)
        }
    }

    static func relativeAttention(_ episode: ProcessAlertEpisode) -> Double {
        let definition = Self.definition(for: episode.metric)
        guard let threshold = StatisticsMetricDefinition.attentionThreshold(
            for: definition,
            physicalMemoryBytes: episode.metric == .memory ? StatisticsMetricDefinition.physicalMemoryBytes() : nil
        ), threshold.value > 0 else {
            return 0
        }
        return episode.averageUsage / threshold.value
    }

    static func definition(for metric: ProcessAlertEpisode.Metric) -> StatisticsMetricDefinition.Metric {
        switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(episodes) { episode in
                    episodeDetails(episode)
                }
                Text(String(localized: "stats.apps.observation-limit-v2"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    let metric = primaryEpisode?.metric ?? episodes.first?.metric ?? .cpu
                    openDetail(group.appKey, metric)
                } label: {
                    Label(String(localized: "stats.apps.open-detail"), systemImage: "arrow.up.forward")
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .padding(.leading, 32)
            .padding(.top, 8)
            .padding(.bottom, 6)
        } label: {
            HStack(spacing: 10) {
                appIcon
                Text(group.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .help(group.name)
                Spacer(minLength: 8)
                if let primary = primaryEpisode {
                    HStack(spacing: 6) {
                        Text(metricLabel(primary.metric))
                            .foregroundStyle(.secondary)
                        Text(Self.value(primary.averageUsage, metric: primary.metric))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .fixedSize()
                }
                if episodes.count > 1 {
                    Text(String(localized: "stats.apps.other-metrics \(episodes.count - 1)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .padding(.vertical, 7)
        }
        .tint(.secondary)
        .onChange(of: group.iconPNG, initial: true) { _, data in
            icon = data.flatMap(NSImage.init(data:))
        }
    }

    private var appIcon: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: group.name == "WindowServer" ? "display" : "terminal")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private func episodeDetails(_ episode: ProcessAlertEpisode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metricLabel(episode.metric))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(metricColor(episode.metric))
                Spacer(minLength: 8)
                Text(String(localized: "stats.apps.average \(Self.value(episode.averageUsage, metric: episode.metric))"))
                    .font(.callout)
                    .monospacedDigit()
            }
            (peakText(episode) + Text(" · ") + observationCount(episode))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            durationText(episode)
            Text(String(localized: "stats.apps.observed-between \(StatisticsDisplayFormat.timeOfDay(episode.startedAt)) \(StatisticsDisplayFormat.timeOfDay(episode.lastSeenAt))"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(episode))
    }

    private func peakText(_ episode: ProcessAlertEpisode) -> Text {
        Text(String(localized: "stats.apps.sample-peak \(Self.value(episode.peakUsage, metric: episode.metric))"))
    }

    private func observationCount(_ episode: ProcessAlertEpisode) -> Text {
        Text(String(localized: "stats.apps.samples \(episode.observationCount)"))
    }

    /// 汇总事件的主要指标、均值、峰值、时长与状态，供辅助功能读屏。
    private func accessibilitySummary(_ episode: ProcessAlertEpisode) -> String {
        var parts = [
            metricLabel(episode.metric),
            String(localized: "stats.apps.a11y.average \(Self.value(episode.averageUsage, metric: episode.metric))"),
            String(localized: "stats.apps.a11y.peak \(Self.value(episode.peakUsage, metric: episode.metric))"),
            String(localized: "stats.apps.a11y.duration \(StatisticsDisplayFormat.duration(episode.continuousHighSeconds))"),
        ]
        switch episode.state {
        case .ongoing:
            parts.append(String(localized: "stats.apps.state.ongoing"))
        case .recovered:
            parts.append(String(localized: "stats.apps.state.recovered"))
        case .interrupted:
            parts.append(String(localized: "stats.apps.state.interrupted \(endReasonText(episode.endReason))"))
        }
        return parts.joined(separator: "，")
    }

    private func durationText(_ episode: ProcessAlertEpisode) -> Text {
        var parts: [Text] = [
            Text(String(localized: "stats.apps.high-duration \(StatisticsDisplayFormat.duration(episode.continuousHighSeconds))"))
        ]
        switch episode.state {
        case .ongoing:
            break
        case .recovered:
            parts.append(Text(String(localized: "stats.apps.state.recovered")))
        case .interrupted:
            parts.append(Text(String(localized: "stats.apps.state.interrupted \(endReasonText(episode.endReason))")))
        }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(" · ") + $1 }
    }

    private func endReasonText(_ reason: ProcessAlertEpisode.EndReason?) -> String {
        switch reason {
        case .recovered: return String(localized: "stats.apps.reason.recovered")
        case .observationGap: return String(localized: "stats.apps.reason.gap")
        case .notObserved: return String(localized: "stats.apps.reason.notObserved")
        case .sourceFailure: return String(localized: "stats.apps.reason.sourceFailure")
        case .processExited: return String(localized: "stats.apps.reason.exited")
        case .suspended: return String(localized: "stats.apps.reason.suspended")
        case .replaced: return String(localized: "stats.apps.reason.replaced")
        case nil: return String(localized: "stats.apps.reason.unknown")
        }
    }

    private func metricLabel(_ metric: ProcessAlertEpisode.Metric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: String(localized: "stats.metric.memory")
        case .network: String(localized: "stats.metric.network")
        }
    }

    private func metricColor(_ metric: ProcessAlertEpisode.Metric) -> Color {
        let kind: MonitorKind = switch metric {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .network: .network
        }
        return palette.moduleTint(for: kind)
    }

    private static func metricOrder(_ metric: ProcessAlertEpisode.Metric) -> Int {
        switch metric {
        case .memory: 0
        case .cpu: 1
        case .gpu: 2
        case .network: 3
        }
    }

    static func value(_ raw: Double, metric: ProcessAlertEpisode.Metric) -> String {
        StatisticsDisplayFormat.applicationObservationValue(raw, metric: metric)
    }

}

#if DEBUG
/// 仅用于调试与预览的模拟应用告警数据。
enum StatisticsApplicationFixture {
    private static let configuredGroups: [ProcessAppAlertGroup]? = {
        guard let scenario = ProcessInfo.processInfo.environment["HAGIMI_STATS_APPLICATION_FIXTURE"] else { return nil }
        return make(scenario: scenario, at: Date())
    }()

    static func fromEnvironment() -> [ProcessAppAlertGroup]? { configuredGroups }

    static func make(scenario: String, at now: Date) -> [ProcessAppAlertGroup] {
        if scenario == "empty" { return [] }
        func episode(_ app: String, _ metric: ProcessAlertEpisode.Metric, _ average: Double, _ peak: Double) -> ProcessAlertEpisode {
            ProcessAlertEpisode(
                appKey: app, name: app, metric: metric,
                startedAt: now.addingTimeInterval(-5 * 60), lastSeenAt: now,
                peakUsage: peak, averageUsage: average,
                continuousHighSeconds: 5 * 60, eventSpanSeconds: 5 * 60, observationCount: 5
            )
        }
        let name = scenario == "long" ? "Safari · 一个用于核对完整名称的浏览器应用" : "Safari"
        var groups = [
            ProcessAppAlertGroup(appKey: "fixture-safari", name: name,
                iconPNG: ProcessIconCache.fullSizePNG(forBundleIdentifier: "com.apple.Safari", sidePixels: 128),
                episodes: [episode(name, .memory, 5.8 * StatisticsMetricDefinition.gibibyte, 6.2 * StatisticsMetricDefinition.gibibyte), episode(name, .cpu, 74.5, 81.2)]),
            ProcessAppAlertGroup(appKey: "fixture-windowserver", name: "WindowServer", iconPNG: nil,
                episodes: [episode("WindowServer", .gpu, 46, 47.6)])
        ]
        if scenario == "multi" {
            groups.append(ProcessAppAlertGroup(appKey: "fixture-third", name: "Xcode", iconPNG: nil,
                episodes: [episode("Xcode", .cpu, 150, 280)]))
        }
        return groups
    }
}
#endif
