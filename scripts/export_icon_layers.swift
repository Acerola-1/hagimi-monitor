// 按 MenuBarComputeRingIcon.swift 真实结构导出图标图层（1024 透明 PNG）
// 结构: 淡色全圆轨道 + 240°负载弧(顶部起顺时针) + 中心背板环 + 绿色核心点
// 用法: swift export_layers.swift <ring-dark|ring-light|backplate-dark|backplate-light|dot|composite-full> <output.png>
// composite-full: 满幅合成版(深色背景铺满方形,无边距无圆角),供关于页 AboutIcon 等靠 clipShape 切圆角的场景
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let kinds = ["ring-dark", "ring-light", "backplate-dark", "backplate-light", "dot", "composite-full"]
guard args.count == 3, kinds.contains(args[1]) else {
    fputs("usage: export_layers <\(kinds.joined(separator: "|"))> <output.png>\n", stderr)
    exit(1)
}

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)

// 几何规范：源码 18px 画布按比例放大到图标网格,环外缘顶到 Apple 圆形安全框(半径342)
// 源码: ring dia 13, arc lineWidth ~2.31(75%负载), track 1.35, core dia ~3.95, backplate +1.8
let ringRadius: CGFloat = 299     // 299 + 86/2 = 342 = 官方圆形网格框
let arcWidth: CGFloat = 86
let trackWidth: CGFloat = 52      // 1.35/2.31 × 86
let dotRadius: CGFloat = 84       // 中心保持不随环放大
let backplateRadius: CGFloat = 122

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

    // 2. 负载弧:源码从 90°(顶部)顺时针,扫角 240° → 下端点收在 8 点钟位置,缺口 8点⇒12点
    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius,
                   startAngle: rad(90), endAngle: rad(-150), clockwise: true)
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
    if args[1] == "composite-full" {
        // 满幅合成:背景铺满 + 四层结构几何与 icon.json 完全一致。
        // AboutIcon 和 .icon 同样是整张图被圆角裁切,不得额外缩放,
        // 否则与启动台/Dock 的真实图标比例不一致。
        // 背景:顶亮底暗深色渐变(近似 icon.json 的 automatic-gradient)
        let bg = CGGradient(colorsSpace: colorSpace, colors: [
            CGColor(srgbRed: 0.115, green: 0.120, blue: 0.132, alpha: 1),
            CGColor(srgbRed: 0.070, green: 0.074, blue: 0.082, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: center.x, y: canvas),
                               end: CGPoint(x: center.x, y: 0), options: [])
        // 轨道
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.34))
        ctx.setLineWidth(trackWidth)
        ctx.strokeEllipse(in: circle(ringRadius))
        // 负载弧
        let arcPath = CGMutablePath()
        arcPath.addArc(center: center, radius: ringRadius,
                       startAngle: rad(90), endAngle: rad(-150), clockwise: true)
        ctx.addPath(arcPath)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(arcWidth)
        ctx.setLineCap(.round)
        ctx.strokePath()
        // 背板 + 核心点
        ctx.setFillColor(CGColor(srgbRed: 0.04, green: 0.045, blue: 0.05, alpha: 1))
        ctx.fillEllipse(in: circle(backplateRadius))
        ctx.setFillColor(CGColor(srgbRed: 0.231, green: 0.925, blue: 0.392, alpha: 1))
        ctx.fillEllipse(in: circle(dotRadius))
    } else {
        // 核心点:#3BEC64,两种外观共用
        ctx.setFillColor(CGColor(srgbRed: 0.231, green: 0.925, blue: 0.392, alpha: 1))
        ctx.fillEllipse(in: circle(dotRadius))
    }
}

guard let outCG = ctx.makeImage() else { fputs("cannot render\n", stderr); exit(1) }
let rep = NSBitmapImageRep(cgImage: outCG)
rep.size = NSSize(width: canvas, height: canvas)
guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("cannot encode png\n", stderr); exit(1)
}
try! data.write(to: URL(fileURLWithPath: args[2]))
print("done: \(args[2])")
