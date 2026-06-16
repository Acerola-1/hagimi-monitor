import SwiftUI

/// CPU/GPU 迷你折线图。用 Canvas 替代 Swift Charts,省去重框架每帧重建的开销。
struct SparklineChart: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let points = Array(samples.suffix(24))
            guard points.count > 1 else { return }

            let stepX = size.width / CGFloat(points.count - 1)
            let height = size.height

            // 折线路径:值域 0–100 满高度映射(顶=100,底=0)。
            var linePath = Path()
            for (i, v) in points.enumerated() {
                let x = stepX * CGFloat(i)
                let clamped = min(1, max(0, CGFloat(v / 100)))
                let y = height * (1 - clamped)
                if i == 0 {
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // 填充区域:复制折线,闭合到底边,用从顶到底的线性渐变。
            var areaPath = linePath
            areaPath.addLine(to: CGPoint(x: size.width, y: height))
            areaPath.addLine(to: CGPoint(x: 0, y: height))
            areaPath.closeSubpath()

            let gradient = Gradient(colors: [tint.opacity(0.45), tint.opacity(0)])
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
