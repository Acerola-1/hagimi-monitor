import AppKit

/// 菜单栏图标右上角的告警红点:环模式画进环形图画布(21pt,环本体 18pt),
/// 指标模式叠加在 ImageRenderer 快照上。红点带一圈反差描边(浅色菜单栏用白、
/// 深色用黑),保证两种菜单栏底色都清晰可辨;位置上与负载环留出可见间隙。
enum MenuBarAlertBadge {
    /// 红点半径(直径约 3.6pt):小尺寸避免抢负载环本身的注意力。
    private static let radius: CGFloat = 1.8
    /// 反差描边宽。
    private static let haloWidth: CGFloat = 0.7
    /// 圆心距图标右上角的内缩:与环保持肉眼可辨的间隙,不贴住环线。
    private static let inset: CGFloat = 2.4

    static func draw(in rect: NSRect, darkMode: Bool) {
        let center = NSPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        let haloRadius = radius + haloWidth / 2
        let halo = NSBezierPath(ovalIn: NSRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        ))
        (darkMode ? NSColor.black : NSColor.white).setFill()
        halo.fill()

        let dot = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        dotColor.setFill()
        dot.fill()
    }

    /// 与 `MonitorPalette.severityTint(for: .critical)` 同值:AppKit 绘制路径
    /// 用不了 SwiftUI Color,数值从同一常量取。
    private static var dotColor: NSColor {
        let hex = MonitorPalette.criticalTintHex
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
