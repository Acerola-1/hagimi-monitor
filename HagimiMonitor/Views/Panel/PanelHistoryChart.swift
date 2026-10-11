import SwiftUI

/// 主行历史图共用固定纵轴、时间槽与透明绘图区；只随正常采样重绘。
struct PanelHistoryChart: View {
    let samples: [Double]
    let tint: Color
    let theme: MonitorPanelTheme
    var scale = PanelChartScale()
    var referenceValue: Double? = nil
    var style: PanelHistoryChartStyle = .bars

    var body: some View {
        Canvas { context, size in
            let inset = MonitorConstants.panelChartInset
            let plot = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            guard plot.width > 0, plot.height > 0 else { return }
            // 左侧竖线表达完整值域，底部零线保留固定时间范围。
            var guides = Path()
            guides.move(to: CGPoint(x: plot.minX, y: plot.minY))
            guides.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            guides.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(guides, with: .color(theme.secondaryText.opacity(0.42)), lineWidth: 0.75)

            if let referenceValue, let fraction = scale.fraction(referenceValue) {
                let y = plot.maxY - plot.height * fraction
                var reference = Path()
                reference.move(to: CGPoint(x: plot.minX, y: y))
                reference.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(reference, with: .color(theme.secondaryText.opacity(0.24)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }

            let values = Array(samples.suffix(MonitorConstants.sparklineMaxPoints))
            let step = plot.width / CGFloat(MonitorConstants.sparklineMaxPoints)
            let start = plot.maxX - step * CGFloat(values.count)
            if style == .line {
                let segments = PanelChartReadings.lineSegments(samples, scale: scale)
                for segment in segments {
                    let points = segment.map {
                        CGPoint(x: plot.minX + (CGFloat($0.slot) + 0.5) * step,
                                y: plot.maxY - plot.height * $0.fraction)
                    }
                    guard let first = points.first else { continue }
                    if points.count == 1 {
                        context.fill(Path(ellipseIn: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)),
                                     with: .color(tint))
                    } else {
                        var line = Path()
                        line.move(to: first)
                        for point in points.dropFirst() { line.addLine(to: point) }
                        context.stroke(line, with: .color(tint),
                                       style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                    }
                }
                if let last = segments.last?.last, last.slot == MonitorConstants.sparklineMaxPoints - 1 {
                    let point = CGPoint(x: plot.minX + (CGFloat(last.slot) + 0.5) * step,
                                        y: plot.maxY - plot.height * last.fraction)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.25, y: point.y - 1.25, width: 2.5, height: 2.5)),
                                 with: .color(tint))
                }
                return
            }
            for (index, value) in values.enumerated() {
                guard let fraction = scale.fraction(value) else { continue }
                let x = start + CGFloat(index) * step + 0.4
                let width = max(0.5, step - 0.8)
                if value == scale.lower {
                    // 短横位于零线上，不用虚构柱高表示已经采样到的零值。
                    var zero = Path()
                    zero.move(to: CGPoint(x: x, y: plot.maxY))
                    zero.addLine(to: CGPoint(x: x + width, y: plot.maxY))
                    context.stroke(zero, with: .color(tint.opacity(0.9)), lineWidth: 1.25)
                    continue
                }
                guard fraction > 0 else { continue }
                let height = plot.height * fraction
                let rect = CGRect(x: x, y: plot.maxY - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                             with: .color(tint.opacity(index == values.count - 1 ? 1 : 0.75)))
            }
        }
        .frame(width: MonitorConstants.panelChartWidth, height: MonitorConstants.panelChartHeight)
        .accessibilityHidden(true)
    }
}
