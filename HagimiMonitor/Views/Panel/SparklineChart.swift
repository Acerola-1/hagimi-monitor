import SwiftUI
import Charts

struct SparklineChart: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(samples.suffix(24).enumerated()), id: \.offset) { i, v in
            AreaMark(
                x: .value("t", i),
                y: .value("v", v / 100)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                .linearGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("t", i),
                y: .value("v", v / 100)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(.init(lineWidth: 1.2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartPlotStyle { $0.background(.clear) }
    }
}
