import AppKit

@MainActor
final class PanelReorderHoverHint {
    private let delay: TimeInterval = 2
    private let pointerTolerance: CGFloat = 4
    private var anchor: (rowID: String, point: NSPoint)?
    private var timer: Timer?
    private var hint: NSView?

    func track(rowID: String, at point: NSPoint,
               reveal: @escaping @MainActor @Sendable (String, NSPoint) -> NSView?) {
        if let anchor, anchor.rowID == rowID, isNear(point, anchor.point) { return }

        hideHint()
        anchor = (rowID, point)
        if let timer {
            timer.fireDate = Date(timeIntervalSinceNow: delay)
            return
        }

        // 同一次悬浮只保留一个定时器，小幅抖动不会重置等待时间。
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer = nil
                let pointer = NSEvent.mouseLocation
                guard let anchor = self.anchor, self.isNear(pointer, anchor.point),
                      let hint = reveal(anchor.rowID, pointer)
                else {
                    self.cancel()
                    return
                }
                self.hint = hint
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        anchor = nil
        timer?.invalidate()
        timer = nil
        hideHint()
    }

    private func isNear(_ point: NSPoint, _ anchor: NSPoint) -> Bool {
        hypot(point.x - anchor.x, point.y - anchor.y) <= pointerTolerance
    }

    private func hideHint() {
        hint?.removeFromSuperview()
        hint = nil
    }
}

final class PanelReorderHoverHintView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(pointer: NSPoint, within bounds: CGRect, appearance: NSAppearance?) {
        let title = String(localized: "panel.reorder.long-press-hint")
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.setAccessibilityElement(false)
        label.sizeToFit()

        let size = NSSize(width: ceil(label.frame.width) + 16, height: ceil(label.frame.height) + 10)
        let inner = bounds.insetBy(dx: 8, dy: 8)
        let below = pointer.y + 18
        let origin = NSPoint(x: max(inner.minX, min(pointer.x + 12, inner.maxX - size.width)),
                             y: below + size.height <= inner.maxY ? below : max(inner.minY, pointer.y - 12 - size.height))
        super.init(frame: NSRect(origin: origin, size: size))
        self.appearance = appearance
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.helpTag)
        setAccessibilityLabel(title)
        label.setFrameOrigin(NSPoint(x: 8, y: 5))
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = MonitorConstants.rowCornerRadius / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
    }
}
