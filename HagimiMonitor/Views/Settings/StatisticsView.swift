import SwiftUI
import Charts
import SwiftData

struct StatisticsView: View {
    @State private var selectedRange: StatisticsTimeRange = .lastWeek
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customTo = Date()
    @State private var summaries: [MonitorKind: StatisticsSummary] = [:]

    private let aggregator: StatisticsAggregator

    init() {
        let schema = Schema([HourlySample.self, DailyAggregate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.aggregator = StatisticsAggregator(container: container)
    }

    var body: some View {
        SettingsPage {
            timePickerRow
            summaryCardsRow
            chartsGrid
        }
        .onAppear { refreshData() }
        .onChange(of: selectedRange) { refreshData() }
    }

    // MARK: - Time Picker

    private var timePickerRow: some View {
        HStack(spacing: 6) {
            rangeButton(.last24Hours)
            rangeButton(.lastWeek)
            rangeButton(.lastMonth)
            rangeButton(.lastYear)

            Divider().frame(height: 14)

            DatePicker("", selection: $customFrom, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: customFrom) { selectedRange = .custom(from: customFrom, to: customTo); refreshData() }

            Text(String(localized: "stats.date.to"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            DatePicker("", selection: $customTo, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: customTo) { selectedRange = .custom(from: customFrom, to: customTo); refreshData() }
        }
    }

    private func rangeButton(_ range: StatisticsTimeRange) -> some View {
        Button(action: {
            selectedRange = range
            refreshData()
        }) {
            Text(range.title)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(selectedRange == range ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(selectedRange == range ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Cards

    private var summaryCardsRow: some View {
        HStack(spacing: 8) {
            summaryCard(kind: .cpu, color: .red)
            summaryCard(kind: .gpu, color: .green)
            summaryCard(kind: .memory, color: .yellow)
            summaryCard(kind: .power, color: .indigo, format: .watts)
        }
    }

    private enum SummaryFormat { case percent, watts, bytes }

    private func summaryCard(kind: MonitorKind, color: Color, format: SummaryFormat = .percent) -> some View {
        let summary = summaries[kind]
        return VStack(alignment: .leading, spacing: 2) {
            Text(kind.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatValue(summary?.avg ?? 0, format: format))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(formatPeak(summary?.peak ?? 0, format: format))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 2)
        }
    }

    // MARK: - Charts Grid

    private var chartsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            chartCard(kind: .cpu, color: .red)
            chartCard(kind: .gpu, color: .green)
            chartCard(kind: .memory, color: .yellow)
            chartCard(kind: .power, color: .indigo, format: .watts)
            networkChartCard
            diskChartCard
        }
    }

    private func chartCard(kind: MonitorKind, color: Color, format: SummaryFormat = .percent) -> some View {
        let summary = summaries[kind]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatValue(summary?.avg ?? 0, format: format))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            if let points = summary?.points, !points.isEmpty {
                Chart(points) { point in
                    LineMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(color)
                    AreaMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(color.opacity(0.15))
                }
                .chartXAxis { AxisMarks(values: .stride(by: strideComponent, count: strideCount)) }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 32)
            } else {
                emptyChartPlaceholder
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var networkChartCard: some View {
        let summary = summaries[.network]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(MonitorKind.network.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    if let up = summary?.totalBytesOut {
                        Text("\u{2191} \(formatBytes(up))")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }
                    if let down = summary?.totalBytesIn {
                        Text("\u{2193} \(formatBytes(down))")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    }
                }
            }
            if let points = summary?.points, !points.isEmpty {
                Chart(points) { point in
                    LineMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(.cyan)
                    AreaMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(.cyan.opacity(0.15))
                }
                .chartXAxis { AxisMarks(values: .stride(by: strideComponent, count: strideCount)) }
                .frame(height: 24)
            } else {
                emptyChartPlaceholder
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var diskChartCard: some View {
        let summary = summaries[.storage]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(MonitorKind.storage.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    if let r = summary?.totalBytesRead {
                        Text("\(String(localized: "stats.disk.read")) \(formatBytes(r))")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    if let w = summary?.totalBytesWritten {
                        Text("\(String(localized: "stats.disk.write")) \(formatBytes(w))")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }
            }
            if let points = summary?.points, !points.isEmpty {
                Chart(points) { point in
                    LineMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(.purple)
                    AreaMark(x: .value("date", point.date), y: .value("avg", point.avg))
                        .foregroundStyle(.purple.opacity(0.15))
                }
                .chartXAxis { AxisMarks(values: .stride(by: strideComponent, count: strideCount)) }
                .frame(height: 24)
            } else {
                emptyChartPlaceholder
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var emptyChartPlaceholder: some View {
        Text(String(localized: "stats.no-data"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 32)
    }

    // MARK: - Data Loading

    private func refreshData() {
        let range = selectedRange
        summaries = [:]
        for kind in MonitorKind.allCases {
            summaries[kind] = aggregator.query(kind: kind, range: range)
        }
    }

    // MARK: - Formatting

    private var strideComponent: Calendar.Component {
        switch selectedRange {
        case .last24Hours: return .hour
        case .lastWeek: return .day
        case .lastMonth: return .weekOfYear
        case .lastYear: return .month
        case .custom(let from, let to):
            let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 1
            if days <= 14 { return .day }
            if days <= 90 { return .weekOfYear }
            return .month
        }
    }

    private var strideCount: Int {
        switch selectedRange {
        case .last24Hours: return 6
        case .lastWeek: return 1
        case .lastMonth: return 1
        case .lastYear: return 3
        case .custom(let from, let to):
            let days = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 1
            if days <= 14 { return 1 }
            if days <= 90 { return 2 }
            return 3
        }
    }

    private func formatValue(_ value: Double, format: SummaryFormat) -> String {
        switch format {
        case .percent: return String(format: "%.1f%%", value)
        case .watts: return String(format: "%.1f W", value)
        case .bytes: return formatBytes(Int64(value))
        }
    }

    private func formatPeak(_ value: Double, format: SummaryFormat) -> String {
        switch format {
        case .percent: return String(format: "%@ %.1f%%", String(localized: "stats.peak"), value)
        case .watts: return String(format: "%@ %.1f W", String(localized: "stats.peak"), value)
        case .bytes: return formatBytes(Int64(value))
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
