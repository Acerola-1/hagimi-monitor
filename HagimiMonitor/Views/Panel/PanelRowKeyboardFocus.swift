import SwiftUI

extension Notification.Name {
    /// 指针呼出或面板隐藏后，清掉常驻面板里残留的键盘焦点。
    static let hagimiPanelKeyboardFocusReset = Notification.Name("hagimi.panel.keyboardFocusReset")
    /// 面板内按下指针时只收起焦点轮廓，不改当前行的展开状态。
    static let hagimiPanelPointerInteraction = Notification.Name("hagimi.panel.pointerInteraction")
}

/// 行内焦点轮廓只跟着最近一次输入设备走。
/// 面板是常驻 NSPanel，成为 key window 时系统会把焦点落到第一个可聚焦行；
/// 那一次不是键盘导航，不能画出轮廓。
enum PanelKeyboardFocusRing {
    private(set) static var lastInputWasKeyboard = false

    static func noteKeyDown() {
        lastInputWasKeyboard = true
    }

    static func notePointer() {
        lastInputWasKeyboard = false
    }

    static func shouldShow(focused: Bool) -> Bool {
        focused && lastInputWasKeyboard
    }
}

private struct PanelRowKeyboardFocusModifier: ViewModifier {
    var canActivate: Bool
    var ring: Color
    var activate: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var showsRing = false

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled)
            .focusEffectDisabled()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                showsRing = PanelKeyboardFocusRing.shouldShow(focused: focused)
            }
            .onKeyPress(.space) { performActivation() }
            .onKeyPress(.return) { performActivation() }
            .onReceive(NotificationCenter.default.publisher(for: .hagimiPanelKeyboardFocusReset)) { _ in
                showsRing = false
                if isFocused { isFocused = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: .hagimiPanelPointerInteraction)) { _ in
                showsRing = false
            }
            .modifier(PanelRowActivationAction(enabled: canActivate, action: activate))
            .overlay {
                if isFocused && showsRing {
                    RoundedRectangle(cornerRadius: CGFloat(MonitorConstants.rowCornerRadius), style: .continuous)
                        .inset(by: 1)
                        .strokeBorder(ring, lineWidth: 1.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private func performActivation() -> KeyPress.Result {
        guard isEnabled, canActivate else { return .ignored }
        showsRing = true
        activate()
        return .handled
    }
}

/// 可展开的行才暴露默认激活动作。不可展开时不挂空动作，避免读屏把它当成按钮。
private struct PanelRowActivationAction: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction { action() }
        } else {
            content
        }
    }
}

extension View {
    /// 模块行头进入窗口的键盘焦点链。空格与回车只在行可以展开时触发。
    func panelRowKeyboardFocus(
        canActivate: Bool,
        ring: Color,
        activate: @escaping () -> Void
    ) -> some View {
        modifier(PanelRowKeyboardFocusModifier(canActivate: canActivate, ring: ring, activate: activate))
    }
}
