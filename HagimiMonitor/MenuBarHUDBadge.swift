import AppKit

/// 菜单栏角标语义：压力告警占右上角红圆，Game HUD 占右下角紫菱，两者位置与形态均不同，可同时独立展示。
nonisolated struct MenuBarBadgePresentation: Equatable, Sendable {
    let showsAlert: Bool
    let showsHUDBadge: Bool

    var drawsAlert: Bool { showsAlert }
    var drawsHUD: Bool { showsHUDBadge }
    var needsOverlay: Bool { drawsAlert || drawsHUD }
}

/// 菜单栏图标右下角的 Game HUD 徽章：HUD 显示中时出现，紫色（与工具区
/// Game HUD 磁贴点亮色同源）且采用 45° 旋转菱形，与右上角红色圆点告警在
/// 位置、形状与色彩三重维度区分，既避免仅靠颜色辨识也支持两者共存。
enum MenuBarHUDBadge {
    private static let halfDiagonal: CGFloat = 1.9
    private static let haloHalfDiagonal: CGFloat = 2.55
    private static let inset: CGFloat = 2.7

    static func draw(in rect: NSRect, darkMode: Bool) {
        let center = NSPoint(x: rect.maxX - inset, y: rect.minY + inset)
        let halo = diamondPath(center: center, halfDiagonal: haloHalfDiagonal)
        (darkMode ? NSColor.black : NSColor.white).setFill()
        halo.fill()

        let diamond = diamondPath(center: center, halfDiagonal: halfDiagonal)
        dotColor.setFill()
        diamond.fill()
    }

    private static func diamondPath(center: NSPoint, halfDiagonal: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y + halfDiagonal))
        path.line(to: NSPoint(x: center.x + halfDiagonal, y: center.y))
        path.line(to: NSPoint(x: center.x, y: center.y - halfDiagonal))
        path.line(to: NSPoint(x: center.x - halfDiagonal, y: center.y))
        path.close()
        return path
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
