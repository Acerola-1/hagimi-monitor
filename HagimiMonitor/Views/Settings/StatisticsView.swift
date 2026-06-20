import AppKit
import SwiftUI

struct StatisticsView: View {
    /// 当前小时尚未落库的内存桶（key 为 MonitorKind.rawValue），用于整点前也能看到 24h 数据。
    var pendingProvider: (() -> [String: PendingBucket])?

    @State private var summaries: [MonitorKind: StatisticsSummary] = [:]
    @State private var healthScore: HealthScore?
    @State private var range: StatisticsTimeRange = .last24Hours
    @State private var errorMessage: String?

    private let aggregator = StatisticsAggregator()
    private let exporter = StatisticsReportExporter()
    private static let summaryKinds: [MonitorKind] = [.cpu, .gpu, .memory, .power, .network, .storage]

    private static let rangeOptions: [(range: StatisticsTimeRange, label: String)] = [
        (.last24Hours, String(localized: "stats.range.24h")),
        (.lastWeek, String(localized: "stats.range.week")),
        (.lastMonth, String(localized: "stats.range.month")),
        (.lastYear, String(localized: "stats.range.year")),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let healthScore {
                    HealthScoreSection(healthScore: healthScore)
                }
                summaryGrid
                EventTimelineSection(range: range)
                if let errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { refreshData() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "stats.summary.title"))
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "stats.summary.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                reportButton
            }

            rangePicker
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.rangeOptions.enumerated()), id: \.offset) { _, option in
                let isSelected = range == option.range
                Button {
                    range = option.range
                    refreshData()
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var reportButton: some View {
        if #available(macOS 26, *) {
            Button {
                openDetailedReport()
            } label: {
                Label(String(localized: "stats.report.open"), systemImage: "safari")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .fixedSize()
        } else {
            Button {
                openDetailedReport()
            } label: {
                Label(String(localized: "stats.report.open"), systemImage: "safari")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .fixedSize()
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Self.summaryKinds, id: \.self) { kind in
                SummaryCard(
                    kind: kind,
                    summary: summaries[kind],
                    accentColor: accentColor(for: kind)
                )
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func refreshData() {
        let pending = pendingProvider?() ?? [:]
        let pendingBucket = range == .last24Hours ? pending.first?.value : nil
        healthScore = aggregator.queryHealthScore(range: range, pending: pendingBucket)
        summaries = Dictionary(uniqueKeysWithValues: Self.summaryKinds.map { kind in
            let pendingForKind = range == .last24Hours ? pending[kind.rawValue] : nil
            return (kind, aggregator.query(kind: kind, range: range, pending: pendingForKind))
        })
    }

    private func openDetailedReport() {
        errorMessage = nil
        do {
            let url = try exporter.export(pending: pendingProvider?() ?? [:])
            if !NSWorkspace.shared.open(url) {
                errorMessage = String(localized: "stats.report.open.failed")
            }
        } catch {
            errorMessage = String(localized: "stats.report.open.failed")
        }
    }

    fileprivate static func splitValue(_ value: Double, unit: String) -> (number: String, unit: String) {
        (String(format: "%.1f", value), unit)
    }

    fileprivate static func splitBytes(_ bytes: Int64) -> (number: String, unit: String) {
        if bytes <= 0 { return ("--", "") }
        if bytes < 1024 { return ("\(bytes)", "B") }
        if bytes < 1_048_576 { return (String(format: "%.1f", Double(bytes) / 1024), "KB") }
        if bytes < 1_073_741_824 { return (String(format: "%.1f", Double(bytes) / 1_048_576), "MB") }
        return (String(format: "%.2f", Double(bytes) / 1_073_741_824), "GB")
    }

    private func accentColor(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu: return .red
        case .gpu: return .green
        case .memory: return .orange
        case .storage: return .blue
        case .network: return .cyan
        case .battery: return .mint
        case .power: return .purple
        default: return .accentColor
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let kind: MonitorKind
    let summary: StatisticsSummary?
    let accentColor: Color

    private var hasData: Bool {
        guard let s = summary else { return false }
        return s.avg > 0 || s.peak > 0 || (s.totalBytesIn ?? 0) > 0 || (s.totalBytesOut ?? 0) > 0
            || (s.totalBytesRead ?? 0) > 0 || (s.totalBytesWritten ?? 0) > 0
    }

    private var isDualMetric: Bool {
        kind == .network || kind == .storage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isDualMetric {
                dualMetricBody
            } else {
                singleMetricBody
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        let metrics = cardMetrics
        return HStack(spacing: 10) {
            iconBadge

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !isDualMetric {
                    Text(metrics.primaryCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - 单主指标（CPU/GPU/内存/功耗）

    private var singleMetricBody: some View {
        let metrics = cardMetrics
        return VStack(alignment: .leading, spacing: 14) {
            // 主数值
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(metrics.primaryNumber)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(hasData ? .primary : .tertiary)
                if !metrics.primaryUnit.isEmpty {
                    Text(metrics.primaryUnit)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
                Spacer(minLength: 0)
            }

            if !metrics.secondary.isEmpty {
                Divider()
                    .opacity(0.6)
                HStack(spacing: 0) {
                    ForEach(Array(metrics.secondary.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                                .frame(height: 22)
                                .opacity(0.5)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(row.number)
                                    .font(.callout.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(hasData ? .primary : .tertiary)
                                    .lineLimit(1)
                                if !row.unit.isEmpty {
                                    Text(row.unit)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, index > 0 ? 12 : 0)
                    }
                }
            }
        }
    }

    // MARK: - 双主指标（网络/存储）

    private var dualMetricBody: some View {
        guard let dual = dualMetrics else {
            return AnyView(EmptyView())
        }
        return AnyView(
            HStack(alignment: .top, spacing: 10) {
                dualMetricColumn(dual.first)
                Divider()
                    .opacity(0.5)
                dualMetricColumn(dual.second)
            }
            .padding(.top, 2)
        )
    }

    private func dualMetricColumn(_ metric: DualMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: metric.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(metric.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.number)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(hasData ? .primary : .tertiary)
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.95), accentColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .shadow(color: accentColor.opacity(0.25), radius: 4, x: 0, y: 1)
    }

    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.42))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - 值计算

    private struct MetricRow {
        let label: String
        let number: String
        let unit: String
    }

    private struct CardMetrics {
        let primaryNumber: String
        let primaryUnit: String
        let primaryCaption: String
        let secondary: [MetricRow]
    }

    private struct DualMetric {
        let symbol: String
        let label: String
        let number: String
        let unit: String
    }

    private struct DualMetrics {
        let first: DualMetric
        let second: DualMetric
    }

    private var dualMetrics: DualMetrics? {
        switch kind {
        case .network:
            let down = StatisticsView.splitBytes(summary?.totalBytesIn ?? 0)
            let up = StatisticsView.splitBytes(summary?.totalBytesOut ?? 0)
            return DualMetrics(
                first: DualMetric(
                    symbol: "arrow.down",
                    label: String(localized: "stats.net.down"),
                    number: hasData ? down.number : "--",
                    unit: hasData ? down.unit : ""
                ),
                second: DualMetric(
                    symbol: "arrow.up",
                    label: String(localized: "stats.net.up"),
                    number: hasData ? up.number : "--",
                    unit: hasData ? up.unit : ""
                )
            )
        case .storage:
            let read = StatisticsView.splitBytes(summary?.totalBytesRead ?? 0)
            let write = StatisticsView.splitBytes(summary?.totalBytesWritten ?? 0)
            return DualMetrics(
                first: DualMetric(
                    symbol: "arrow.down.to.line",
                    label: String(localized: "stats.disk.read"),
                    number: hasData ? read.number : "--",
                    unit: hasData ? read.unit : ""
                ),
                second: DualMetric(
                    symbol: "arrow.up.to.line",
                    label: String(localized: "stats.disk.write"),
                    number: hasData ? write.number : "--",
                    unit: hasData ? write.unit : ""
                )
            )
        default:
            return nil
        }
    }

    private var cardMetrics: CardMetrics {
        let avgCaption = String(localized: "stats.avg")

        guard let s = summary, hasData else {
            return CardMetrics(
                primaryNumber: "--", primaryUnit: "", primaryCaption: avgCaption,
                secondary: [
                    MetricRow(label: String(localized: "stats.peak"), number: "--", unit: ""),
                    MetricRow(label: String(localized: "stats.median"), number: "--", unit: ""),
                ]
            )
        }

        switch kind {
        case .power:
            let avg = StatisticsView.splitValue(s.avgPower ?? s.avg, unit: "W")
            let peak = StatisticsView.splitValue(s.peak, unit: "W")
            let median = StatisticsView.splitValue(s.median, unit: "W")
            return CardMetrics(
                primaryNumber: avg.number, primaryUnit: avg.unit, primaryCaption: avgCaption,
                secondary: [
                    MetricRow(label: String(localized: "stats.peak"), number: peak.number, unit: peak.unit),
                    MetricRow(label: String(localized: "stats.median"), number: median.number, unit: median.unit),
                ]
            )
        default:
            let avg = StatisticsView.splitValue(s.avg, unit: "%")
            let peak = StatisticsView.splitValue(s.peak, unit: "%")
            let median = StatisticsView.splitValue(s.median, unit: "%")
            return CardMetrics(
                primaryNumber: avg.number, primaryUnit: avg.unit, primaryCaption: avgCaption,
                secondary: [
                    MetricRow(label: String(localized: "stats.peak"), number: peak.number, unit: peak.unit),
                    MetricRow(label: String(localized: "stats.median"), number: median.number, unit: median.unit),
                ]
            )
        }
    }
}

// MARK: - Health Score Section

struct HealthScoreSection: View {
    let healthScore: HealthScore

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                healthContent
                    .glassEffect(.regular.tint(healthGlassTint), in: .rect(cornerRadius: 14, style: .continuous))
            }
        } else {
            healthContent
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary.opacity(0.42))
                )
        }
    }

    private var healthContent: some View {
        HStack(alignment: .center, spacing: 24) {
            HealthScoreRingView(score: healthScore)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "health.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if healthScore.thermalCapped {
                    Label(String(localized: "health.thermal-capped"), systemImage: "thermometer.high")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                ForEach(healthScore.dimensions.filter(\.isAvailable)) { dim in
                    DimensionScoreRow(dimension: dim)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var healthGlassTint: Color {
        MonitorPalette(preference: .balanced, colorScheme: .light).healthTint(for: healthScore.level).opacity(0.08)
    }
}

// MARK: - Health Score Ring

struct HealthScoreRingView: View {
    let score: HealthScore

    private static let ringSize: CGFloat = 100

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 10)

            Circle()
                .trim(from: 0, to: min(score.score / 100, 1.0))
                .stroke(
                    AngularGradient(
                        colors: [ringColor, ringColor.opacity(0.7)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(score.score))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ringColor)
                Text(score.level.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ringColor)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private var ringColor: Color {
        MonitorPalette(preference: .balanced, colorScheme: .light).healthTint(for: score.level)
    }
}

// MARK: - Dimension Score Row

struct DimensionScoreRow: View {
    let dimension: DimensionScore

    var body: some View {
        HStack(spacing: 8) {
            Text(dimension.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.08))
                    Capsule()
                        .fill(levelColor.opacity(0.7))
                        .frame(width: geo.size.width * min(max(dimension.healthValue, 0), 1))
                }
            }
            .frame(height: 6)

            Text("\(Int(dimension.healthValue * 100))%")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(levelColor)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var levelColor: Color {
        MonitorPalette(preference: .balanced, colorScheme: .light).healthTint(for: dimension.level)
    }
}
