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
        let phase = Double(frame % 48) / 48
        return phase < 0.5 ? phase * 2 : (1 - phase) * 2
    }

    var progress: Double {
        min(0.98, max(0.08, 0.12 + normalizedLoad * 0.86))
    }

    var tint: NSColor {
        let alpha = 0.72 + normalizedLoad * 0.24
        return ink.withAlphaComponent(alpha)
    }

    var trackColor: NSColor {
        ink.withAlphaComponent(darkMode ? 0.28 : 0.22)
    }

    var glowColor: NSColor {
        ink.withAlphaComponent((darkMode ? 0.16 : 0.08) + normalizedLoad * 0.14 + linearPulse * normalizedLoad * 0.06)
    }

    var coreColor: NSColor {
        loadLevel.coreColor(darkMode: darkMode)
            .withAlphaComponent((darkMode ? 0.68 : 0.82) + normalizedLoad * 0.12 + linearPulse * 0.04)
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

    private var ink: NSColor {
        darkMode ? .white : .black
    }

    private var loadLevel: MenuBarComputeLoadLevel {
        switch load {
        case ..<35:
            return .idle
        case ..<65:
            return .working
        case ..<85:
            return .busy
        default:
            return .stressed
        }
    }
}

private enum MenuBarComputeLoadLevel {
    case idle
    case working
    case busy
    case stressed

    func coreColor(darkMode: Bool) -> NSColor {
        switch self {
        case .idle:
            return darkMode
                ? NSColor.white.withAlphaComponent(0.72)
                : NSColor.black.withAlphaComponent(0.62)
        case .working:
            return darkMode
                ? NSColor(red: 0.32, green: 0.88, blue: 0.72, alpha: 1)
                : NSColor(red: 0.00, green: 0.55, blue: 0.42, alpha: 1)
        case .busy:
            return darkMode
                ? NSColor(red: 1.00, green: 0.74, blue: 0.32, alpha: 1)
                : NSColor(red: 0.80, green: 0.44, blue: 0.06, alpha: 1)
        case .stressed:
            return darkMode
                ? NSColor(red: 1.00, green: 0.38, blue: 0.34, alpha: 1)
                : NSColor(red: 0.78, green: 0.12, blue: 0.10, alpha: 1)
        }
    }
}
