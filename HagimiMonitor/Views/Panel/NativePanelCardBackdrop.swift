import AppKit
import SwiftUI

/// 静态行材质直接由 AppKit 承载，避免为每张卡片保留另一棵 SwiftUI 视图树。
/// 层次与内容侧一致：窗口内材质、主题填充、白色提亮、0.5pt 细描边；轮廓仍由外层共享轨迹裁剪。
final class NativePanelCardBackdropView: NSVisualEffectView {
    private let tint = CAGradientLayer()
    private let brighten = CALayer()
    private let borderLayer = CAShapeLayer()
    private var preference: MonitorColorSchemePreference?
    private var scheme: ColorScheme?
    private var kind: MonitorKind?
    private var fadeEnd: CGFloat = CGFloat(MonitorConstants.rowTintFadeEnd)
    private var isUniformFill = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = MonitorConstants.rowCornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        tint.startPoint = CGPoint(x: 0.5, y: 0)
        tint.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(tint)
        layer?.addSublayer(brighten)
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 0.5
        layer?.addSublayer(borderLayer)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(kind: MonitorKind?, palette: MonitorPalette) {
        guard preference != palette.preference || scheme != palette.colorScheme || self.kind != kind else { return }
        preference = palette.preference
        scheme = palette.colorScheme
        self.kind = kind
        appearance = NSAppearance(named: palette.colorScheme == .dark ? .darkAqua : .aqua)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let spec = palette.rowGlassSpec(for: kind)
        isUniformFill = spec.isUniform
        fadeEnd = CGFloat(spec.fadeEnd)
        if spec.isUniform {
            let color = NSColor(spec.color).cgColor
            tint.colors = [color, color]
        } else {
            let full = NSColor(spec.color.opacity(spec.fullOpacity)).cgColor
            let faint = NSColor(spec.color.opacity(spec.faintOpacity)).cgColor
            tint.colors = [full, full, faint]
        }
        brighten.backgroundColor = NSColor.white.withAlphaComponent(palette.cardBrightenOpacity).cgColor
        borderLayer.strokeColor = NSColor(palette.cardBorderColor).cgColor
        updateLayerFrames()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateLayerFrames()
        CATransaction.commit()
    }

    private func updateLayerFrames() {
        tint.frame = bounds
        brighten.frame = bounds
        borderLayer.frame = bounds
        if bounds.width > 0.5 && bounds.height > 0.5 {
            let insetRect = bounds.insetBy(dx: 0.25, dy: 0.25)
            let radius = max(0, CGFloat(MonitorConstants.rowCornerRadius) - 0.25)
            borderLayer.path = CGPath(roundedRect: insetRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        } else {
            borderLayer.path = nil
        }
        let height = max(1, bounds.height)
        tint.locations = isUniformFill
            ? [0, 1]
            : [0, NSNumber(value: Double(min(MonitorConstants.rowTintPlateau / height, 1))),
               NSNumber(value: Double(min(fadeEnd / height, 1)))]
    }
}
