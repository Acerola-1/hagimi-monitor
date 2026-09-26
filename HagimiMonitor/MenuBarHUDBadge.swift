import AppKit

/// 菜单栏图标右上角的 Game HUD 徽章:HUD 显示中时出现,紫色(与工具区
/// Game HUD 磁贴点亮色同源)。几何与 `MenuBarAlertBadge` 完全一致,仅
/// 颜色不同;两者互斥绘制(告警红点优先),避免两枚叠在同一位。
enum MenuBarHUDBadge {
    private static let radius: CGFloat = 1.8
    private static let haloWidth: CGFloat = 0.7
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

    /// 与 `MonitorPalette.quickToolTint` 同源:AppKit 绘制路径取同一常量。
    private static var dotColor: NSColor {
        let hex = MonitorPalette.quickToolTintHex
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
