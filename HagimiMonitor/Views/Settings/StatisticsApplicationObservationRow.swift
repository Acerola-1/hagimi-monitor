import AppKit
import SwiftUI

/// 设置页顶部的实时高负载单行提示条，独立于下方的历史范围概览卡片之外。
/// 仅在存在未忽略的高占用应用时显示。
struct ActiveHighLoadBanner: View {
    let groups: [ProcessAppAlertGroup]
    let onIgnore: (ProcessAppAlertGroup) -> Void
    let onOpenApps: () -> Void

    @State private var icon: NSImage?

    private var leading: ProcessAppAlertGroup? { groups.first }

    private var primaryEpisode: ProcessAlertEpisode? {
        guard let leading else { return nil }
        return StatisticsApplicationObservationRow.primaryEpisode(in: leading)
    }

    var body: some View {
        if let leading {
            HStack(spacing: 10) {
                appIcon(for: leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText(for: leading))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(leading.name)

                    if let detail = detailText(for: leading) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if groups.count == 1 {
                        Button(String(localized: "stats.apps.banner.ignore")) {
                            onIgnore(leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                    }

                    Button(action: onOpenApps) {
                        HStack(spacing: 3) {
                            Text(String(localized: "stats.apps.banner.view"))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .onChange(of: leading.iconPNG, initial: true) { _, data in
                icon = data.flatMap(NSImage.init(data:))
            }
        }
    }

    private func headlineText(for leading: ProcessAppAlertGroup) -> String {
        if groups.count == 1 {
            return String(localized: "stats.apps.banner.single \(leading.name)")
        }
        return String(localized: "stats.apps.banner.multiple \(leading.name) \(groups.count)")
    }

    private func detailText(for leading: ProcessAppAlertGroup) -> String? {
        guard let primary = primaryEpisode else { return nil }
        let metricText = "\(metricLabel(primary.metric)) \(StatisticsApplicationObservationRow.value(primary.averageUsage, metric: primary.metric))"
        let durationText = StatisticsDisplayFormat.duration(primary.continuousHighSeconds)
        if leading.episodes.count > 1 {
            return String(localized: "stats.apps.banner.detail.multiMetric \(metricText) \(durationText) \(leading.episodes.count - 1)")
        }
        return String(localized: "stats.apps.banner.detail \(metricText) \(durationText)")
    }

    private func metricLabel(_ metric: ProcessAlertEpisode.Metric) -> String {
        switch metric {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: String(localized: "stats.metric.memory")
        case .network: String(localized: "stats.metric.network")
        }
    }

    private func appIcon(for group: ProcessAppAlertGroup) -> some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: group.name == "WindowServer" ? "display" : "terminal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// 应用高负载观测计算与展示辅助（供横幅与测试共用）。
enum StatisticsApplicationObservationRow {
    static func primaryEpisode(in group: ProcessAppAlertGroup) -> ProcessAlertEpisode? {
        group.episodes.max { lhs, rhs in
            relativeAttention(lhs) < relativeAttention(rhs)
        }
    }

    static func relativeAttention(_ episode: ProcessAlertEpisode) -> Double {
        let definition = Self.definition(for: episode.metric)
        guard let threshold = StatisticsMetricDefinition.attentionThreshold(
            for: definition,
            physicalMemoryBytes: episode.metric == .memory ? StatisticsMetricDefinition.physicalMemoryBytes() : nil,
            logicalCoreCount: episode.metric == .cpu ? StatisticsMetricDefinition.logicalCoreCount() : nil
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
                episodes: [episode(name, .memory, 5.8 * StatisticsMetricDefinition.gibibyte, 6.2 * StatisticsMetricDefinition.gibibyte), episode(name, .cpu, 185, 220)]),
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
