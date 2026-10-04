import AppKit
import SwiftUI

/// 静态行材质直接由 AppKit 承载，避免为每张卡片保留另一棵 SwiftUI 视图树。
/// 层次与内容侧一致：窗口内材质、主题填充、白色提亮；轮廓仍由外层共享轨迹裁剪。
final class NativePanelCardBackdropView: NSVisualEffectView {
    private let tint = CAGradientLayer()
    private let brighten = CALayer()
    private var preference: MonitorColorSchemePreference?
    private var scheme: ColorScheme?
    private var kind: MonitorKind?

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
        if palette.preference == .balanced {
            let color = NSColor(palette.neutralGlassTint).cgColor
            tint.colors = [color, color]
        } else {
            let color = kind.map { palette.moduleTint(for: $0) } ?? palette.displayTint
            let full = NSColor(color.opacity(palette.vibrantGlassOpacity)).cgColor
            tint.colors = [full, full, NSColor(color.opacity(MonitorConstants.rowTintFaintOpacity)).cgColor]
        }
        brighten.backgroundColor = NSColor.white.withAlphaComponent(palette.cardBrightenOpacity).cgColor
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
        let height = max(1, bounds.height)
        tint.locations = preference == .vibrant
            ? [0, NSNumber(value: Double(min(MonitorConstants.rowTintPlateau / height, 1))),
               NSNumber(value: Double(min(MonitorConstants.rowTintFadeEnd / height, 1)))]
            : [0, 1]
    }
}
