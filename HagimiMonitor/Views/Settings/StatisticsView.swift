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
        HStack(alignment: .center, spacing: 14) {
            rangePicker
            reportButton
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
            .compatibleButtonStyle()
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
        // 统计页面只读已入库数据（HourlySample / DailyAggregate），不含实时 pending。
        // 同一小时内反复切换范围，读到的数据完全一致，分数不会变化。
        healthScore = aggregator.queryHealthScore(range: range, pending: nil)
        summaries = Dictionary(uniqueKeysWithValues: Self.summaryKinds.map { kind in
            (kind, aggregator.query(kind: kind, range: range, pending: nil))
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
            VStack(alignment: .leading, spacing: 10) {
                dualMetricRow(dual.first)
                Divider()
                    .opacity(0.5)
                dualMetricRow(dual.second)
            }
            .padding(.top, 2)
        )
    }

    private func dualMetricRow(_ metric: DualMetric) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: metric.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(metric.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 56, alignment: .leading)

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.number)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
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
    @State private var showTips = false

    var body: some View {
        if #available(macOS 26, *) {
            CompatibleGlassContainer {
                healthContent
                    .compatibleGlassEffect(tint: healthGlassTint, cornerRadius: 14)
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
        Group {
            if healthScore.isDataAvailable {
                scoreContent
            } else {
                emptyContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var scoreContent: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 6) {
                HealthScoreRingView(score: healthScore)
                if healthScore.trend.count >= 2 {
                    HealthTrendSparkline(points: healthScore.trend)
                        .frame(width: 100, height: 22)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(String(localized: "health.title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Button {
                        showTips.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "health.tips.button"))
                    .popover(isPresented: $showTips, arrowEdge: .top) {
                        HealthTipsPopover()
                    }
                    Spacer(minLength: 0)
                }

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
    }

    private var emptyContent: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "health.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "health.no-data"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "health.no-data.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
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

// MARK: - Health Trend Sparkline

struct HealthTrendSparkline: View {
    let points: [HealthTrendPoint]

    var body: some View {
        GeometryReader { geo in
            if points.count >= 2 {
                Path { path in
                    let stepX = geo.size.width / CGFloat(points.count - 1)
                    for (i, p) in points.enumerated() {
                        let x = CGFloat(i) * stepX
                        let y = geo.size.height * (1 - CGFloat(min(max(p.score, 0), 100)) / 100)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [.green.opacity(0.8), .yellow.opacity(0.8), .red.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}

// MARK: - Health Tips Popover

struct HealthTipsPopover: View {
    private struct DimTip {
        let name: String
        let tip: String
    }

    private var tips: [DimTip] {
        [
            DimTip(name: String(localized: "health.dimension.cpu"), tip: String(localized: "health.tips.cpu")),
            DimTip(name: String(localized: "health.dimension.gpu"), tip: String(localized: "health.tips.gpu")),
            DimTip(name: String(localized: "health.dimension.disk"), tip: String(localized: "health.tips.disk")),
            DimTip(name: String(localized: "health.dimension.pressure"), tip: String(localized: "health.tips.pressure")),
            DimTip(name: String(localized: "health.dimension.thermal"), tip: String(localized: "health.tips.thermal")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "health.tips.title"))
                    .font(.headline)
                Text(String(localized: "health.tips.intro"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.name)
                            .font(.subheadline.weight(.semibold))
                        Text(tip.tip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                Text(String(localized: "health.tips.thermal"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 280)
        }
        .frame(maxHeight: 360)
    }
}

// MARK: - Dimension Score Row

struct DimensionScoreRow: View {
    let dimension: DimensionScore

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(dimension.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(dimension.rawText)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 6) {
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
                Text("\(Int(dimension.healthValue * 100))")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(levelColor)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }

    private var levelColor: Color {
        MonitorPalette(preference: .balanced, colorScheme: .light).healthTint(for: dimension.level)
    }
}
