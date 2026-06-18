import AppKit
import Charts
import SwiftUI

struct StatisticsView: View {
    /// 当前小时尚未落库的内存桶（key 为 MonitorKind.rawValue），用于整点前也能看到 24h 数据。
    var pendingProvider: (() -> [String: PendingBucket])?

    @State private var summaries: [MonitorKind: StatisticsSummary] = [:]
    @State private var errorMessage: String?

    private let aggregator = StatisticsAggregator()
    private let exporter = StatisticsReportExporter()
    private static let summaryKinds: [MonitorKind] = [.cpu, .memory, .power, .network]

    var body: some View {
        SettingsPage {
            SettingsGroup {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryGrid
                    footerTip
                }
                .padding(14)
            }
        }
        .onAppear { refreshData() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "stats.summary.title"))
                    .font(.headline.weight(.semibold))
                Text(String(localized: "stats.summary.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                openDetailedReport()
            } label: {
                Label(String(localized: "stats.report.open"), systemImage: "arrow.up.forward.app")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Self.summaryKinds, id: \.self) { kind in
                SummaryCard(
                    kind: kind,
                    summary: summaries[kind],
                    valueText: primaryValueText(for: kind),
                    detailText: detailText(for: kind),
                    accentColor: accentColor(for: kind)
                )
            }
        }
    }

    @ViewBuilder
    private var footerTip: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Label(String(localized: "stats.summary.tip"), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func refreshData() {
        let pending = pendingProvider?() ?? [:]
        summaries = Dictionary(uniqueKeysWithValues: Self.summaryKinds.map { kind in
            (kind, aggregator.query(kind: kind, range: .last24Hours, pending: pending[kind.rawValue]))
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

    private func primaryValueText(for kind: MonitorKind) -> String {
        guard let summary = summaries[kind], !summary.points.isEmpty || hasByteTotals(summary) else { return "--" }
        switch kind {
        case .power: return formatValue(summary.avgPower ?? summary.avg, suffix: " W")
        case .network: return formatBytes(summary.totalBytesIn ?? 0)
        default: return formatValue(summary.avg, suffix: "%")
        }
    }

    private func detailText(for kind: MonitorKind) -> String {
        guard let summary = summaries[kind], !summary.points.isEmpty || hasByteTotals(summary) else { return String(localized: "stats.no-data") }
        switch kind {
        case .network: return "\(String(localized: "stats.net.up")) \(formatBytes(summary.totalBytesOut ?? 0))"
        case .power: return "\(String(localized: "stats.peak")) \(formatValue(summary.peak, suffix: " W"))"
        default: return "\(String(localized: "stats.peak")) \(formatValue(summary.peak, suffix: "%"))"
        }
    }

    private func hasByteTotals(_ summary: StatisticsSummary) -> Bool {
        (summary.totalBytesIn ?? 0) > 0 || (summary.totalBytesOut ?? 0) > 0
    }

    private func formatValue(_ value: Double, suffix: String) -> String {
        String(format: "%.1f%@", value, suffix)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "--" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    private func accentColor(for kind: MonitorKind) -> Color {
        switch kind {
        case .cpu: return .red
        case .memory: return .orange
        case .network: return .cyan
        case .power: return .indigo
        default: return .accentColor
        }
    }
}

private struct SummaryCard: View {
    let kind: MonitorKind
    let summary: StatisticsSummary?
    let valueText: String
    let detailText: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 16)
                Text(kind.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }

            Text(valueText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueText == "--" ? .secondary : accentColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            sparkline
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var sparkline: some View {
        if let points = summary?.points, !points.isEmpty {
            Chart(points) { point in
                LineMark(x: .value("date", point.date), y: .value("avg", point.avg))
                    .foregroundStyle(accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 28)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .frame(height: 28)
                .overlay { Text("--").font(.caption2).foregroundStyle(.tertiary) }
        }
    }
}
