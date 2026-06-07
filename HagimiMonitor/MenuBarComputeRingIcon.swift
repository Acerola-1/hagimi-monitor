import AppKit
import Foundation

enum MenuBarComputeRingIcon {
    static func image(load: Double, frame: Int, darkMode: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 18, height: 18).fill()

        let style = MenuBarComputeRingImageStyle(load: load, frame: frame, darkMode: darkMode)
        drawRing(style: style)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawRing(style: MenuBarComputeRingImageStyle) {
        let center = NSPoint(x: 9, y: 9)
        let ringRect = NSRect(
            x: center.x - style.ringSize / 2,
            y: center.y - style.ringSize / 2,
            width: style.ringSize,
            height: style.ringSize
        )

        style.trackColor.setStroke()
        let trackInset = (18 - style.trackSize) / 2
        let track = NSBezierPath(ovalIn: NSRect(x: trackInset, y: trackInset, width: style.trackSize, height: style.trackSize))
        track.lineWidth = style.trackWidth
        track.stroke()

        drawArc(
            in: ringRect,
            progress: style.progress,
            lineWidth: style.lineWidth,
            color: style.glowColor
        )

        drawArc(
            in: ringRect,
            progress: style.progress,
            lineWidth: style.lineWidth,
            color: style.tint
        )

        style.coreColor.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - style.coreSize / 2,
                y: center.y - style.coreSize / 2,
                width: style.coreSize,
                height: style.coreSize
            )
        ).fill()
    }

    private static func drawArc(in rect: NSRect, progress: Double, lineWidth: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: 90,
            endAngle: 90 - CGFloat(progress * 360),
            clockwise: true
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

private struct MenuBarComputeRingImageStyle {
    let load: Double
    let frame: Int
    let darkMode: Bool

    private var normalizedLoad: Double {
        min(1, max(0, load / 100))
    }

    private var linearPulse: Double {
        let phase = Double(frame % 24) / 24
        return phase < 0.5 ? phase * 2 : (1 - phase) * 2
    }

    var progress: Double {
        min(0.98, max(0.08, 0.12 + normalizedLoad * 0.86))
    }

    var tint: NSColor {
        if darkMode {
            switch load {
            case ..<45:
                return NSColor(red: 0.34, green: 0.86, blue: 0.66, alpha: 1)
            case ..<75:
                return NSColor(red: 1.00, green: 0.72, blue: 0.34, alpha: 1)
            default:
                return NSColor(red: 1.00, green: 0.38, blue: 0.34, alpha: 1)
            }
        } else {
            switch load {
            case ..<45:
                return NSColor(red: 0.08, green: 0.50, blue: 0.34, alpha: 1)
            case ..<75:
                return NSColor(red: 0.76, green: 0.43, blue: 0.08, alpha: 1)
            default:
                return NSColor(red: 0.72, green: 0.14, blue: 0.12, alpha: 1)
            }
        }
    }

    var trackColor: NSColor {
        darkMode
            ? NSColor.white.withAlphaComponent(0.28)
            : NSColor.black.withAlphaComponent(0.20)
    }

    var glowColor: NSColor {
        tint.withAlphaComponent((darkMode ? 0.18 : 0.10) + normalizedLoad * 0.18 + linearPulse * normalizedLoad * 0.08)
    }

    var coreColor: NSColor {
        tint.withAlphaComponent((darkMode ? 0.58 : 0.68) + normalizedLoad * 0.18 + linearPulse * 0.05)
    }

    var lineWidth: CGFloat {
        CGFloat(1.8 + normalizedLoad * 0.75 + linearPulse * normalizedLoad * 0.10)
    }

    var ringSize: CGFloat {
        CGFloat(13.0 + linearPulse * (0.30 + normalizedLoad * 0.50))
    }

    var coreSize: CGFloat {
        CGFloat(2.1 + normalizedLoad * 2.0 + linearPulse * normalizedLoad * 0.25)
    }

    var trackSize: CGFloat {
        13.2
    }

    var trackWidth: CGFloat {
        darkMode ? 1.45 : 1.35
    }
}
