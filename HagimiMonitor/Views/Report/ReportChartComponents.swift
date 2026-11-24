import AppKit
import Charts
import SwiftUI

/// 图表系列渲染描述。
struct ReportChartSeriesDescriptor: Identifiable {
    let id: String
    let title: String
    let series: ReportChartSeries
    let color: Color
    var lineWidth: CGFloat = 1.7
    var isDashed: Bool = false
    var showAreaFill: Bool = false
    var interpolation: InterpolationMethod = .monotone
}

/// 统一时间序列折线/面积图组件：
/// - 严格为 `LineMark` 与 `AreaMark` 绑定相同 `series:`，彻底杜绝跨睡眠缺口拉出填充色块
/// - 基于 `.onContinuousHover` + `ChartProxy` 实现无需点击即可响应的十字准星与跟随悬浮读数卡片
/// - 自动适配单日 (`HH:mm`) 与跨日 (`MM-dd`) X 轴及多维度 Y 轴格式
struct ReportTimeSeriesChart: View {
    enum YAxisFormat {
        case percent
        case binaryGiB
        case binaryMiB
        case decimalMBps
        case watts
        case celsius
        case rpm
        case thermalLevel
    }

    let descriptors: [ReportChartSeriesDescriptor]
    let isSingleDay: Bool
    let yAxisFormat: YAxisFormat
    var yDomain: ClosedRange<Double>? = nil
    var yAxisValues: [Double]? = nil
    var highlightWindows: [ReportChartHighlightWindow] = []
    var referenceLine: (value: Double, color: Color)? = nil
    var height: CGFloat = 220

    @State private var hoveredDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    private var hasAnyData: Bool {
        descriptors.contains { !$0.series.isEmpty }
    }

    var body: some View {
        if hasAnyData {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    ForEach(descriptors) { desc in
                        if !desc.series.isEmpty {
                            ReportLegendItem(title: desc.title, color: desc.color, isDashed: desc.isDashed)
                        }
                    }
                    Spacer()
                }

                chartCanvas
                    .frame(height: height)
            }
        }
    }

    private var chartCanvas: some View {
        let hoveredSnapshot = resolveHoveredSnapshot()

        return Chart {
            // 1. 高亮压力事件或聚焦时间窗背景带
            ForEach(highlightWindows) { window in
                RectangleMark(
                    xStart: .value("WinStart", window.start),
                    xEnd: .value("WinEnd", window.end)
                )
                .foregroundStyle(windowColor(window.tone))
            }

            // 2. 可选警戒参考线（例如内存压力 60%）
            if let referenceLine {
                RuleMark(y: .value("Ref", referenceLine.value))
                    .foregroundStyle(referenceLine.color.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // 3. 主曲线与分段填充（AreaMark 与 LineMark 同用 series 参数确保休眠断点断开）
            ForEach(descriptors) { desc in
                ForEach(Array(desc.series.segments.enumerated()), id: \.offset) { segIdx, segPoints in
                    let segSeriesKey = "\(desc.id)-\(segIdx)"
                    ForEach(segPoints) { pt in
                        if let val = pt.value {
                            if desc.showAreaFill && segPoints.count > 1 {
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", val),
                                    series: .value("Series", segSeriesKey)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [desc.color.opacity(0.26), desc.color.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(desc.interpolation)
                            }

                            if segPoints.count == 1 {
                                PointMark(x: .value("Time", pt.date), y: .value("Value", val))
                                    .foregroundStyle(desc.color)
                                    .symbolSize(16)
                            } else {
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", val),
                                    series: .value("Series", segSeriesKey)
                                )
                                .foregroundStyle(desc.color.opacity(desc.isDashed ? 0.85 : 1.0))
                                .lineStyle(
                                    desc.isDashed
                                        ? StrokeStyle(lineWidth: desc.lineWidth, dash: [4, 4])
                                        : StrokeStyle(lineWidth: desc.lineWidth)
                                )
                                .interpolationMethod(desc.interpolation)
                            }
                        }
                    }
                }
            }

            // 4. 悬浮十字准星与激活点位
            if let snapshot = hoveredSnapshot {
                RuleMark(x: .value("Hover", snapshot.date))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(snapshot.items, id: \.id) { item in
                    PointMark(
                        x: .value("Hover", snapshot.date),
                        y: .value("HoverVal", item.value)
                    )
                    .foregroundStyle(item.color)
                    .symbolSize(34)
                }
            }
        }
        .modifier(OptionalYDomainModifier(domain: yDomain))
        .chartYAxis {
            if let yAxisValues {
                AxisMarks(position: .leading, values: yAxisValues) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(formatAxisValue(num))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                AxisMarks(position: .leading) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.16))
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(formatAxisValue(num))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel {
                    if let date = val.as(Date.self) {
                        Text(isSingleDay ? ReportUIHelper.formatTimeOnly(date) : ReportUIHelper.formatDateShort(date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geo[plotFrame]
                                let x = location.x - frame.origin.x
                                guard x >= 0, x <= frame.size.width else {
                                    hoveredDate = nil
                                    return
                                }
                                if let date = proxy.value(atX: x, as: Date.self) {
                                    hoveredDate = date
                                }
                            case .ended:
                                hoveredDate = nil
                            }
                        }

                    if let snapshot = hoveredSnapshot,
                       let plotFrame = proxy.plotFrame,
                       let xPos = proxy.position(forX: snapshot.date) {
                        let frame = geo[plotFrame]
                        hoverCard(snapshot: snapshot)
                            .fixedSize()
                            .position(
                                x: clampedPopoverX(xPos + frame.origin.x, plotFrame: frame),
                                y: frame.origin.y + 34
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - 悬浮卡片与二分查找

    private struct HoverItem: Identifiable {
        let id: String
        let title: String
        let value: Double
        let formatted: String
        let color: Color
    }

    private struct HoverSnapshot {
        let date: Date
        let items: [HoverItem]
    }

    private func resolveHoveredSnapshot() -> HoverSnapshot? {
        guard let target = hoveredDate else { return nil }
        guard let resolved = ReportChartHoverResolver.resolve(
            target: target,
            series: descriptors.map { (id: $0.id, series: $0.series) }
        ) else {
            return nil
        }

        let items: [HoverItem] = descriptors.compactMap { desc in
            guard let val = resolved.values[desc.id] else { return nil }
            return HoverItem(
                id: desc.id,
                title: desc.title,
                value: val,
                formatted: formatReadoutValue(val),
                color: desc.color
            )
        }
        guard !items.isEmpty else { return nil }
        return HoverSnapshot(date: resolved.date, items: items)
    }

    private func clampedPopoverX(_ rawX: CGFloat, plotFrame: CGRect) -> CGFloat {
        let halfCard: CGFloat = 95
        let minX = plotFrame.minX + halfCard + 4
        let maxX = plotFrame.maxX - halfCard - 4
        guard minX <= maxX else { return plotFrame.midX }
        return min(max(rawX, minX), maxX)
    }

    private func hoverCard(snapshot: HoverSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReportUIHelper.formatDateTime(snapshot.date))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ForEach(snapshot.items) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)
                    Text(item.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(item.formatted)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.92 : 0.96))
                .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        }
    }

    // MARK: - 颜色与格式化

    private func windowColor(_ tone: ReportChartHighlightWindow.Tone) -> Color {
        switch tone {
        case .warning: return Color.orange.opacity(colorScheme == .dark ? 0.14 : 0.10)
        case .critical: return Color.red.opacity(colorScheme == .dark ? 0.16 : 0.11)
        case .focus: return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
        }
    }

    private func formatAxisValue(_ val: Double) -> String {
        switch yAxisFormat {
        case .percent:
            return "\(Int(val.rounded()))%"
        case .binaryGiB:
            return ReportUIHelper.formatBytes(val * 1_073_741_824.0)
        case .binaryMiB:
            return ReportUIHelper.formatBytes(val * 1_048_576.0)
        case .decimalMBps:
            return ReportUIHelper.formatBytesRate(val * 1_000_000.0)
        case .watts:
            return String(format: "%.0f W", val)
        case .celsius:
            return String(format: "%.0f°C", val)
        case .rpm:
            return String(format: "%.0f", val)
        case .thermalLevel:
            return StatisticsDisplayFormat.thermalStateLabel(val)
        }
    }

    private func formatReadoutValue(_ val: Double) -> String {
        switch yAxisFormat {
        case .percent:
            return String(format: "%.1f%%", val)
        case .binaryGiB:
            return ReportUIHelper.formatBytes(val * 1_073_741_824.0)
        case .binaryMiB:
            return ReportUIHelper.formatBytes(val * 1_048_576.0)
        case .decimalMBps:
            return ReportUIHelper.formatBytesRate(val * 1_000_000.0)
        case .watts:
            return String(format: "%.1f W", val)
        case .celsius:
            return String(format: "%.1f°C", val)
        case .rpm:
            return String(format: "%.0f RPM", val)
        case .thermalLevel:
            return ReportUIHelper.formatThermalLevel(val)
        }
    }
}

private struct OptionalYDomainModifier: ViewModifier {
    let domain: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let domain {
            content.chartYScale(domain: domain)
        } else {
            content
        }
    }
}

/// 统一并列柱状图组件（供网络与磁盘吞吐图表共用，带连续悬浮提示与十进制单位轴）。
struct ReportVolumeBarChart: View {
    struct BarItem: Identifiable {
        let id: String
        let label: String
        let primaryBytes: Double
        let secondaryBytes: Double
    }

    let items: [BarItem]
    let primaryLabel: String
    let secondaryLabel: String
    let primaryColor: Color
    let secondaryColor: Color
    var height: CGFloat = 180

    @State private var hoveredLabel: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ReportLegendItem(title: primaryLabel, color: primaryColor)
                ReportLegendItem(title: secondaryLabel, color: secondaryColor)
                Spacer()
                if let hoveredLabel, let item = items.first(where: { $0.label == hoveredLabel }) {
                    Text("\(item.label): \(primaryLabel) \(ReportUIHelper.formatVolume(item.primaryBytes)) · \(secondaryLabel) \(ReportUIHelper.formatVolume(item.secondaryBytes))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }

            Chart {
                ForEach(items) { item in
                    BarMark(
                        x: .value("Bucket", item.label),
                        y: .value("Volume", item.primaryBytes)
                    )
                    .foregroundStyle(primaryColor)
                    .position(by: .value("Series", primaryLabel))

                    BarMark(
                        x: .value("Bucket", item.label),
                        y: .value("Volume", item.secondaryBytes)
                    )
                    .foregroundStyle(secondaryColor)
                    .position(by: .value("Series", secondaryLabel))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let bytes = val.as(Double.self) {
                            Text(ReportUIHelper.formatVolume(bytes))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geo[plotFrame]
                                let x = location.x - frame.origin.x
                                guard x >= 0, x <= frame.size.width else {
                                    hoveredLabel = nil
                                    return
                                }
                                hoveredLabel = proxy.value(atX: x, as: String.self)
                            case .ended:
                                hoveredLabel = nil
                            }
                        }
                }
            }
            .frame(height: height)
        }
    }
}

/// 跨模块时间聚焦横幅（展示在目标模块顶部，可一键清除聚焦）。
struct ReportFocusedWindowBanner: View {
    let window: ReportFocusedTimeWindow
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(window.title)
                .font(.callout.weight(.medium))
            Text("\(ReportUIHelper.formatDateTime(window.start)) – \(ReportUIHelper.formatDateTime(window.end))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "stats.report.focus.clear", defaultValue: "清除时段高亮")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.75)
        )
    }
}

/// 趋势图悬浮准星解析器：禁止跨越采样缺口吸附到远端数据点，并严格校验同一准星下的各序列数值必须来自同一统计桶。
nonisolated enum ReportChartHoverResolver {
    static func resolve(
        target: Date,
        series: [(id: String, series: ReportChartSeries)]
    ) -> (date: Date, values: [String: Double])? {
        let targetTime = target.timeIntervalSince1970

        var matchedDate: Date?
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for entry in series {
            let edgeSnapTolerance = entry.series.bucketSeconds * 0.5
            for seg in entry.series.segments where !seg.isEmpty {
                guard let firstTime = seg.first?.date.timeIntervalSince1970,
                      let lastTime = seg.last?.date.timeIntervalSince1970 else { continue }
                let insideSegment = targetTime >= firstTime && targetTime <= lastTime
                guard let pt = closestPoint(toTime: targetTime, inSegment: seg), pt.value != nil else { continue }
                let dist = abs(pt.date.timeIntervalSince1970 - targetTime)
                // 落在缺口内（在连续分段起止之外且超过边缘容差）禁止吸附到远端采样点
                guard insideSegment || dist <= edgeSnapTolerance else { continue }
                if dist < bestDistance {
                    bestDistance = dist
                    matchedDate = pt.date
                }
            }
        }

        guard let anchorDate = matchedDate else { return nil }
        let anchorTime = anchorDate.timeIntervalSince1970

        var values: [String: Double] = [:]
        for entry in series {
            if let pt = closestPoint(toTime: anchorTime, in: entry.series.segments),
               let val = pt.value,
               pt.date == anchorDate {
                values[entry.id] = val
            }
        }

        guard !values.isEmpty else { return nil }
        return (anchorDate, values)
    }

    private static func closestPoint(toTime targetTime: TimeInterval, in segments: [[ReportTimeSeriesPoint]]) -> ReportTimeSeriesPoint? {
        var best: ReportTimeSeriesPoint?
        var bestDiff = TimeInterval.greatestFiniteMagnitude
        for seg in segments where !seg.isEmpty {
            if let pt = closestPoint(toTime: targetTime, inSegment: seg) {
                let diff = abs(pt.date.timeIntervalSince1970 - targetTime)
                if diff < bestDiff {
                    bestDiff = diff
                    best = pt
                }
            }
        }
        return best
    }

    private static func closestPoint(toTime targetTime: TimeInterval, inSegment seg: [ReportTimeSeriesPoint]) -> ReportTimeSeriesPoint? {
        guard !seg.isEmpty else { return nil }
        var low = 0
        var high = seg.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midTime = seg[mid].date.timeIntervalSince1970
            if midTime == targetTime {
                return seg[mid]
            } else if midTime < targetTime {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        var best: ReportTimeSeriesPoint?
        var bestDiff = TimeInterval.greatestFiniteMagnitude
        for idx in [low, high] where idx >= 0 && idx < seg.count {
            let diff = abs(seg[idx].date.timeIntervalSince1970 - targetTime)
            if diff < bestDiff {
                bestDiff = diff
                best = seg[idx]
            }
        }
        return best
    }
}
