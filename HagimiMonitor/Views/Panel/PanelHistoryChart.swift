import SwiftUI

/// 主行历史柱条使用固定纵轴与透明绘图区；只随正常采样重绘。
struct PanelHistoryChart: View {
    let samples: [Double]
    let tint: Color
    let theme: MonitorPanelTheme
    var scale = PanelChartScale()
    var referenceValue: Double? = nil

    var body: some View {
        Canvas { context, size in
            let inset = MonitorConstants.panelChartInset
            let plot = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            guard plot.width > 0, plot.height > 0 else { return }
            // 零线与上限短刻度提供范围参照，透明绘图区直接融入行材质。
            var guides = Path()
            guides.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            guides.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            guides.move(to: CGPoint(x: plot.minX, y: plot.minY))
            guides.addLine(to: CGPoint(x: plot.minX + 3, y: plot.minY))
            guides.move(to: CGPoint(x: plot.maxX - 3, y: plot.minY))
            guides.addLine(to: CGPoint(x: plot.maxX, y: plot.minY))
            context.stroke(guides, with: .color(tint.opacity(0.24)), lineWidth: 0.5)

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
            for (index, value) in values.enumerated() {
                guard let fraction = scale.fraction(value), fraction > 0 else { continue }
                let height = plot.height * fraction
                let rect = CGRect(x: start + CGFloat(index) * step + 0.4, y: plot.maxY - height,
                                  width: max(0.5, step - 0.8), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                             with: .color(tint.opacity(index == values.count - 1 ? 1 : 0.75)))
            }
        }
        .frame(width: MonitorConstants.panelChartWidth, height: MonitorConstants.panelChartHeight)
        .accessibilityHidden(true)
    }
}
