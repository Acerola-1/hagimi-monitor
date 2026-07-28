// 按 MenuBarComputeRingIcon.swift 真实结构导出图标图层（1024 透明 PNG）
// 结构: 淡色全圆轨道 + 270°负载弧(顶部起顺时针) + 中心背板环 + 绿色核心点
// 用法: swift export_layers.swift <ring-dark|ring-light|backplate-dark|backplate-light|dot> <output.png>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let kinds = ["ring-dark", "ring-light", "backplate-dark", "backplate-light", "dot"]
guard args.count == 3, kinds.contains(args[1]) else {
    fputs("usage: export_layers <\(kinds.joined(separator: "|"))> <output.png>\n", stderr)
    exit(1)
}

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)

// 几何规范：源码 18px 画布按比例放大到图标网格（环半径维持 241 适配 824 内容区）
// 源码: ring dia 13, arc lineWidth ~2.17(中载), track 1.35, core dia ~3.95, backplate +1.8
let ringRadius: CGFloat = 241
let arcWidth: CGFloat = 76        // 2.17/13 × 482 ≈ 80,微调至 76 保持弧线优雅
let trackWidth: CGFloat = 47      // 1.35/2.17 × 76
let dotRadius: CGFloat = 73       // 3.95/13 × 241
let backplateRadius: CGFloat = 106 // 5.75/13 × 241

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                          bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fputs("cannot create context\n", stderr); exit(1)
}

func rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func circle(_ r: CGFloat) -> CGRect {
    CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
}

switch args[1] {
case "ring-dark", "ring-light":
    // 深色模式 ink = 白,浅色模式 ink = 黑(源码 ink 定义)
    let isDark = args[1] == "ring-dark"
    let ink = isDark
        ? CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        : CGColor(srgbRed: 0.10, green: 0.11, blue: 0.12, alpha: 1)

    // 1. 淡色全圆轨道(trackColor: ink α 0.34/0.28)
    ctx.setStrokeColor(ink.copy(alpha: isDark ? 0.34 : 0.28)!)
    ctx.setLineWidth(trackWidth)
    ctx.strokeEllipse(in: circle(ringRadius))

    // 2. 负载弧:源码从 90°(顶部)顺时针,取 75% 负载 → 270°,缺口=左上象限
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius,
                   startAngle: rad(90), endAngle: rad(-180), clockwise: true)
    ctx.addPath(arcPath)
    ctx.setStrokeColor(ink.copy(alpha: 0.95)!)
    ctx.setLineWidth(arcWidth)
    ctx.setLineCap(.round)
    ctx.strokePath()

case "backplate-dark", "backplate-light":
    // 中心点外的背板环(coreBackplateColor: 深色=黑 / 浅色=白)
    let color = args[1] == "backplate-dark"
        ? CGColor(srgbRed: 0.04, green: 0.045, blue: 0.05, alpha: 1)
        : CGColor(srgbRed: 0.97, green: 0.975, blue: 0.98, alpha: 1)
    ctx.setFillColor(color)
    ctx.fillEllipse(in: circle(backplateRadius))

default:
    // 核心点:用户指定 #2D9578,两种外观共用
    ctx.setFillColor(CGColor(srgbRed: 0.176, green: 0.584, blue: 0.471, alpha: 1))
    ctx.fillEllipse(in: circle(dotRadius))
}

guard let outCG = ctx.makeImage() else { fputs("cannot render\n", stderr); exit(1) }
let rep = NSBitmapImageRep(cgImage: outCG)
rep.size = NSSize(width: canvas, height: canvas)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("cannot encode png\n", stderr); exit(1)
}
try! data.write(to: URL(fileURLWithPath: args[2]))
print("done: \(args[2])")
