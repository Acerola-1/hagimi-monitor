import AppKit
import Foundation

enum MenuBarCatIcon {
    static func image(for module: MonitorModule, frame: Int, darkMode: Bool) -> NSImage {
        if let assetFrame = runCatAssetFrame(frame: frame, darkMode: darkMode) {
            return assetFrame
        }

        let image = NSImage(size: NSSize(width: 28, height: 18))
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 28, height: 18).fill()

        drawRunningSilhouette(frame: frame, darkMode: darkMode)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func runCatAssetFrame(frame: Int, darkMode: Bool) -> NSImage? {
        guard let source = NSImage(named: "cat_page\(frame % 5)") else {
            return nil
        }

        let image = NSImage(size: NSSize(width: 28, height: 18))
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 28, height: 18).fill()

        source.draw(
            in: NSRect(x: 0, y: 0, width: 28, height: 18),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        if darkMode {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 28, height: 18).fill(using: .sourceAtop)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawRunningSilhouette(frame: Int, darkMode: Bool) {
        let ink = darkMode ? NSColor.white : NSColor.black
        let eye = darkMode ? NSColor.black : NSColor.white
        let phase = frame % RunFrame.frames.count
        let runFrame = RunFrame.frames[phase]

        ink.setFill()
        ink.setStroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 8.2, y: 10.0 + runFrame.bounce))
        tail.curve(
            to: NSPoint(x: 1.8, y: 12.9 + runFrame.bounce + runFrame.tailLift),
            controlPoint1: NSPoint(x: 6.0, y: 12.4 + runFrame.bounce),
            controlPoint2: NSPoint(x: 3.6, y: 13.7 + runFrame.bounce + runFrame.tailLift)
        )
        tail.lineWidth = 2.1
        tail.lineCapStyle = .round
        tail.stroke()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 6.7, y: 9.4 + runFrame.bounce))
        body.curve(
            to: NSPoint(x: 14.2 + runFrame.stretch, y: 12.9 + runFrame.bounce),
            controlPoint1: NSPoint(x: 8.2, y: 13.0 + runFrame.bounce),
            controlPoint2: NSPoint(x: 12.1 + runFrame.stretch, y: 13.4 + runFrame.bounce)
        )
        body.curve(
            to: NSPoint(x: 20.1 + runFrame.stretch, y: 10.6 + runFrame.bounce),
            controlPoint1: NSPoint(x: 16.7 + runFrame.stretch, y: 12.5 + runFrame.bounce),
            controlPoint2: NSPoint(x: 19.1 + runFrame.stretch, y: 11.9 + runFrame.bounce)
        )
        body.curve(
            to: NSPoint(x: 14.9 + runFrame.stretch, y: 6.9 + runFrame.bounce),
            controlPoint1: NSPoint(x: 19.3 + runFrame.stretch, y: 7.5 + runFrame.bounce),
            controlPoint2: NSPoint(x: 17.1 + runFrame.stretch, y: 6.7 + runFrame.bounce)
        )
        body.curve(
            to: NSPoint(x: 6.7, y: 9.4 + runFrame.bounce),
            controlPoint1: NSPoint(x: 11.2, y: 6.6 + runFrame.bounce),
            controlPoint2: NSPoint(x: 8.2, y: 7.2 + runFrame.bounce)
        )
        body.close()
        body.fill()

        NSBezierPath(ovalIn: NSRect(x: 18.5 + runFrame.stretch, y: 9.5 + runFrame.bounce, width: 5.1, height: 4.2)).fill()

        fillTriangle(points: [
            NSPoint(x: 19.2 + runFrame.stretch, y: 12.3 + runFrame.bounce),
            NSPoint(x: 19.8 + runFrame.stretch, y: 15.6 + runFrame.bounce),
            NSPoint(x: 21.3 + runFrame.stretch, y: 12.6 + runFrame.bounce)
        ])
        fillTriangle(points: [
            NSPoint(x: 21.0 + runFrame.stretch, y: 12.2 + runFrame.bounce),
            NSPoint(x: 22.0 + runFrame.stretch, y: 15.1 + runFrame.bounce),
            NSPoint(x: 23.1 + runFrame.stretch, y: 12.0 + runFrame.bounce)
        ])

        for leg in runFrame.legs {
            drawLeg(
                from: NSPoint(x: leg.start.x + runFrame.stretch * 0.45, y: leg.start.y + runFrame.bounce),
                to: NSPoint(x: leg.end.x + runFrame.stretch * 0.45, y: leg.end.y + runFrame.bounce)
            )
        }

        eye.setFill()
        NSBezierPath(ovalIn: NSRect(x: 22.0 + runFrame.stretch, y: 11.4 + runFrame.bounce, width: 0.85, height: 0.85)).fill()
    }

    private static func drawLeg(from start: NSPoint, to end: NSPoint) {
        let leg = NSBezierPath()
        leg.move(to: start)
        leg.line(to: end)
        leg.lineWidth = 1.75
        leg.lineCapStyle = .round
        leg.stroke()
    }

    private static func fillTriangle(points: [NSPoint]) {
        let triangle = NSBezierPath()
        triangle.move(to: points[0])
        triangle.line(to: points[1])
        triangle.line(to: points[2])
        triangle.close()
        triangle.fill()
    }
}

private struct RunFrame {
    struct Leg {
        let start: NSPoint
        let end: NSPoint
    }

    let bounce: CGFloat
    let stretch: CGFloat
    let tailLift: CGFloat
    let legs: [Leg]

    static let frames: [RunFrame] = [
        RunFrame(
            bounce: 0.4,
            stretch: 0.0,
            tailLift: 0.3,
            legs: [
                Leg(start: NSPoint(x: 8.8, y: 7.7), end: NSPoint(x: 5.4, y: 4.2)),
                Leg(start: NSPoint(x: 11.6, y: 7.2), end: NSPoint(x: 13.2, y: 3.6)),
                Leg(start: NSPoint(x: 15.1, y: 7.3), end: NSPoint(x: 12.0, y: 3.8)),
                Leg(start: NSPoint(x: 17.8, y: 8.1), end: NSPoint(x: 21.0, y: 5.0))
            ]
        ),
        RunFrame(
            bounce: 0.0,
            stretch: 0.5,
            tailLift: -0.2,
            legs: [
                Leg(start: NSPoint(x: 8.8, y: 7.5), end: NSPoint(x: 10.6, y: 3.5)),
                Leg(start: NSPoint(x: 11.5, y: 7.2), end: NSPoint(x: 6.2, y: 5.3)),
                Leg(start: NSPoint(x: 15.2, y: 7.4), end: NSPoint(x: 19.7, y: 3.8)),
                Leg(start: NSPoint(x: 17.7, y: 8.0), end: NSPoint(x: 15.4, y: 5.2))
            ]
        ),
        RunFrame(
            bounce: 0.8,
            stretch: 0.9,
            tailLift: 0.1,
            legs: [
                Leg(start: NSPoint(x: 8.9, y: 7.7), end: NSPoint(x: 6.2, y: 5.2)),
                Leg(start: NSPoint(x: 11.8, y: 7.4), end: NSPoint(x: 14.3, y: 5.1)),
                Leg(start: NSPoint(x: 15.3, y: 7.5), end: NSPoint(x: 12.2, y: 5.0)),
                Leg(start: NSPoint(x: 17.9, y: 8.2), end: NSPoint(x: 21.0, y: 5.3))
            ]
        ),
        RunFrame(
            bounce: 0.0,
            stretch: 0.5,
            tailLift: 0.4,
            legs: [
                Leg(start: NSPoint(x: 8.9, y: 7.5), end: NSPoint(x: 11.1, y: 5.2)),
                Leg(start: NSPoint(x: 11.6, y: 7.1), end: NSPoint(x: 6.0, y: 3.9)),
                Leg(start: NSPoint(x: 15.1, y: 7.3), end: NSPoint(x: 19.4, y: 5.2)),
                Leg(start: NSPoint(x: 17.8, y: 8.0), end: NSPoint(x: 15.5, y: 3.8))
            ]
        ),
        RunFrame(
            bounce: 0.45,
            stretch: 0.0,
            tailLift: -0.1,
            legs: [
                Leg(start: NSPoint(x: 8.8, y: 7.6), end: NSPoint(x: 5.7, y: 5.0)),
                Leg(start: NSPoint(x: 11.7, y: 7.2), end: NSPoint(x: 13.8, y: 3.7)),
                Leg(start: NSPoint(x: 15.2, y: 7.4), end: NSPoint(x: 11.7, y: 3.9)),
                Leg(start: NSPoint(x: 17.8, y: 8.1), end: NSPoint(x: 20.6, y: 4.4))
            ]
        )
    ]
}
