import SwiftUI

/// 迷你折线图。用 Canvas 替代 Swift Charts,省去重框架每帧重建的开销。
/// 支持自定义 Y 轴范围:CPU/GPU 等百分比数据用默认 0~100,
/// 风扇 RPM 等绝对值数据用 minValue~maxValue 归一化以放大细节。
struct SparklineChart: View {
    let samples: [Double]
    let tint: Color
    /// Y 轴下限。默认 0(百分比场景);风扇场景传 F{id}Mn(如 2317)。
    var minValue: Double = 0
    /// Y 轴上限。默认 100(百分比场景);风扇场景传 F{id}Mx(如 6550)。
    var maxValue: Double = 100

    var body: some View {
        Canvas { context, size in
            let points = Array(samples.suffix(24))
            guard points.count > 1 else { return }

            let stepX = size.width / CGFloat(points.count - 1)
            let height = size.height
            // 有效归一化范围:若 max<=min 则退化为 0~1 避免除零。
            let effectiveRange = maxValue > minValue ? (maxValue - minValue) : 1

            // 坐标轴参照系:底部 X 轴(0%) + 左侧 Y 轴组成 L 形轴框。
            // 没有它时,持续低/持续高的平稳曲线都只是一条悬空的线,
            // 无法判断其在 0-100% 中的位置;有轴框后,贴轴即低、离轴即高。
            var basePath = Path()
            basePath.move(to: CGPoint(x: 0, y: height - 0.5))
            basePath.addLine(to: CGPoint(x: size.width, y: height - 0.5))
            context.stroke(basePath, with: .color(tint.opacity(0.28)), lineWidth: 1)

            // Y 轴从转角处向上渐隐:等宽实线悬在卡片里像渲染 bug,
            // 渐隐后它像从 X 轴自然生长出来,既给出高度参照又不突兀。
            var yAxisPath = Path()
            yAxisPath.move(to: CGPoint(x: 0.5, y: height - 0.5))
            yAxisPath.addLine(to: CGPoint(x: 0.5, y: 0))
            context.stroke(
                yAxisPath,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: height),
                    endPoint: .zero
                ),
                lineWidth: 1
            )

            var linePath = Path()
            for (i, v) in points.enumerated() {
                let x = stepX * CGFloat(i)
                // 归一化:(value - min) / (max - min),钳到 0~1。
                let normalized = (v - minValue) / effectiveRange
                let clamped = min(1, max(0, CGFloat(normalized)))
                let y = height * (1 - clamped)
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var areaPath = linePath
            areaPath.addLine(to: CGPoint(x: size.width, y: height))
            areaPath.addLine(to: CGPoint(x: 0, y: height))
            areaPath.closeSubpath()

            let gradient = Gradient(colors: [tint.opacity(0.60), tint.opacity(0.08)])
            context.fill(
                areaPath,
                with: .linearGradient(
                    gradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: height)
                )
            )
            context.stroke(linePath, with: .color(tint), lineWidth: 1.2)
        }
    }
}
