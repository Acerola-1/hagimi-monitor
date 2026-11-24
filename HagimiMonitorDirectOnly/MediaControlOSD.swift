import AppKit
import SwiftUI

/// 媒体键反馈与菜单栏面板独立，仅在首次收到调节事件时创建窗口。
@MainActor
final class MediaControlOSD {
    private let state = MediaControlOSDState()
    private var panel: NSPanel?
    private var presentation: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var updateValue: ((Double, Bool) -> Bool)?
    private var isEditing = false
    private var pointerInside = false
    private(set) var displayID: CGDirectDisplayID?
    var control: MediaKeyKind? { displayID == nil ? nil : state.control }

    func show(
        control: MediaKeyKind,
        value: Double,
        displayID: CGDirectDisplayID,
        updateValue: @escaping (Double, Bool) -> Bool
    ) {
        // 首次建窗及后续刷新均移出事件 tap 回调，连续按键只保留最新反馈。
        presentation?.cancel()
        presentation = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.presentation = nil
            self.present(control: control, value: value, displayID: displayID, updateValue: updateValue)
        }
    }

    private func present(
        control: MediaKeyKind,
        value: Double,
        displayID: CGDirectDisplayID,
        updateValue: @escaping (Double, Bool) -> Bool
    ) {
        let screen = NSScreen.screens.first { screen in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }
        guard let screen else { return }
        let placement = AppDelegate.shared?.mediaOSDPlacement(on: screen)

        let sameScale = self.displayID == displayID && (state.control == .brightness) == (control == .brightness)
        let resetReadout = !sameScale
        if resetReadout {
            isEditing = false
        }
        self.displayID = displayID
        self.updateValue = updateValue
        state.control = control
        updateDisplayedValue(value, resetReadout: resetReadout, animated: sameScale && panel?.isVisible == true && !isEditing)

        let panel = self.panel ?? makePanel()
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let centerX = placement?.suppressed == true ? frame.midX : placement?.anchor?.midX ?? frame.midX
        let top = min(placement?.anchor?.minY ?? frame.maxY, frame.maxY) - 6
        let x = max(frame.minX + 6, min(centerX - size.width / 2, frame.maxX - size.width - 6))
        let origin = CGPoint(x: x, y: top - size.height)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        scheduleDismissal()
    }

    func hide() {
        presentation?.cancel()
        presentation = nil
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        displayID = nil
        updateValue = nil
        isEditing = false
        pointerInside = false
        state.isInteractive = false
        state.readout = nil
    }

    private func makePanel() -> NSPanel {
        let size: CGSize
        if #available(macOS 27.2, *) { size = CGSize(width: 307, height: 66) }
        else { size = CGSize(width: 304, height: 64) }
        let panel = MediaControlOSDPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = MediaControlOSDHost(rootView: MediaControlOSDView(
            state: state,
            changeValue: { [weak self] value in self?.changeValue(value, final: self?.isEditing != true) },
            edit: { [weak self] in self?.edit($0) }
        ))
        host.hover = { [weak self] in self?.hover($0) }
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = MediaControlGlassView(frame: host.frame)
            glass.updateMaterial()
            glass.cornerRadius = size.height / 2
            glass.contentView = host
            panel.contentView = glass
        } else {
            let backdrop = NSVisualEffectView(frame: host.frame)
            // 旧系统使用深色 HUD，内容继承同一外观。
            backdrop.appearance = NSAppearance(named: .darkAqua)
            backdrop.material = .hudWindow
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.wantsLayer = true
            backdrop.layer?.cornerRadius = size.height / 2
            backdrop.layer?.masksToBounds = true
            backdrop.addSubview(host)
            panel.contentView = backdrop
        }
        self.panel = panel
        return panel
    }

    private func changeValue(_ value: Double, final: Bool) {
        guard updateValue?(value, final) == true else { return }
        updateDisplayedValue(value)
        if state.control == .mute, value > 0 { state.control = .volume }
        scheduleDismissal()
    }

    private func updateDisplayedValue(_ value: Double, resetReadout: Bool = false, animated: Bool = false) {
        guard resetReadout || state.value != value else { return }
        state.readout = OSDReadout(percent: value)
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animate ? .smooth(duration: 0.20) : nil) { state.value = value }
    }

    private func edit(_ editing: Bool) {
        isEditing = editing
        state.isInteractive = pointerInside || editing
        if !editing { changeValue(state.value, final: true) }
        scheduleDismissal()
    }

    private func hover(_ hovering: Bool) {
        guard displayID != nil, pointerInside != hovering else { return }
        pointerInside = hovering
        state.isInteractive = hovering || isEditing
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = nil
        if let panel, panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
                panel.animator().alphaValue = 1
            }
        }
        guard displayID != nil, !state.isInteractive else { return }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1450))
            guard let self, let panel = self.panel, !Task.isCancelled else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.hide()
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: nil)
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }
}

/// 浮层不抢占前台焦点，但维持激活外观，避免液态玻璃退化为非激活态的重模糊。
private final class MediaControlOSDPanel: NSPanel {
    @objc var hasKeyAppearance: Bool { true }
    @objc var _hasActiveAppearance: Bool { true }
    @objc var _hasActiveControls: Bool { true }
}

@available(macOS 26, *)
private final class MediaControlGlassView: NSGlassEffectView {
    private static let systemBannerVariant = 9
    private static let variantSetter = NSSelectorFromString("set_variant:")

    // 使用系统横幅液态玻璃预设，浅色背景保持足够压暗以保证白色图标与滑条可读，同时保留边缘折射；
    // 若系统移除私有预设接口则回退为深色 tint 的 .clear，辅助功能高对比度或降低透明度时切为深色 .regular。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self, name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if window != nil {
            center.addObserver(self, selector: #selector(updateMaterial),
                               name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            updateMaterial()
        }
    }

    @objc func updateMaterial() {
        let workspace = NSWorkspace.shared
        let highLegibility = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
        if highLegibility {
            style = .regular
            tintColor = nil
            appearance = NSAppearance(named: .darkAqua)
        } else {
            appearance = nil
            style = .clear
            if responds(to: Self.variantSetter) {
                tintColor = nil
                setValue(Self.systemBannerVariant, forKey: "_variant")
            } else {
                tintColor = NSColor.black.withAlphaComponent(0.18)
            }
        }
    }
}

private final class MediaControlOSDHost: NSHostingView<MediaControlOSDView> {
    var hover: ((Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    // 指针实际移动后才切换滑条，浮层出现于静止光标下时仍可自动收起。
    override func mouseMoved(with event: NSEvent) { hover?(true) }
    override func mouseExited(with event: NSEvent) { hover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct OSDReadout {
    let percent: Double

    var text: String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

@Observable
private final class MediaControlOSDState {
    var control: MediaKeyKind = .brightness
    var value: Double = 0
    var readout: OSDReadout?
    var isInteractive = false
}

private struct MediaControlOSDView: View {
    let state: MediaControlOSDState
    let changeValue: @MainActor @Sendable (Double) -> Void
    let edit: @MainActor @Sendable (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: symbol)
                .frame(width: 28)
                .accessibilityHidden(true)
            GeometryReader { geometry in
                let travel = max(1, geometry.size.width)
                OSDLevelTrack(fraction: state.value / 100, readout: state.readout)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { point in
                            if !dragging { dragging = true; edit(true) }
                            changeValue(Double(min(travel, max(0, point.location.x)) / travel) * 100)
                        }
                        .onEnded { _ in dragging = false; edit(false) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(label))
                    .accessibilityValue(Text(verbatim: (state.readout ?? OSDReadout(percent: state.value)).text))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: changeValue(min(100, state.value + 6.25))
                        case .decrement: changeValue(max(0, state.value - 6.25))
                        @unknown default: break
                        }
                    }
            }
            .frame(height: 30)
        }
        .padding(.leading, 22)
        .padding(.trailing, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if #unavailable(macOS 26) {
                Capsule().fill(Color(white: 0.36).opacity(0.23))
            }
        }
    }

    private var label: LocalizedStringKey {
        switch state.control {
        case .brightness: "display.control.brightness"
        case .volume: "display.control.volume"
        case .mute: "display.control.muted"
        }
    }

    private var symbol: String {
        switch state.control {
        case .brightness: "sun.max.fill"
        case .volume: state.value < 34 ? "speaker.wave.1.fill" : state.value < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .mute: "speaker.slash.fill"
        }
    }
}

/// 轨道和气泡位置随进度插值，文字只显示已发布的读数。
private struct OSDLevelTrack: View, Animatable {
    var fraction: Double
    let readout: OSDReadout?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    nonisolated var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let progress = min(1, max(0, fraction))
            let endpoint = geometry.size.width * progress
            let bubbleColor = Color.white.opacity(reduceTransparency ? 1 : 0.84)
            let capsule = Capsule()
            ZStack {
                capsule.fill(Color.white.opacity(contrast == .increased ? 0.42 : 0.23))
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white).frame(width: endpoint)
                    }
                    .clipShape(capsule)
                    .mask {
                        HStack(spacing: 1) {
                            ForEach(0..<16) { _ in Rectangle() }
                        }
                    }
                    .frame(height: 4)

                OSDCalloutLayout(endpoint: endpoint) {
                    Text(verbatim: readout?.text ?? "")
                        .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                        .contentTransition(.identity)
                        .foregroundStyle(.black.opacity(contrast == .increased ? 0.9 : 0.70))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(bubbleColor, in: Capsule())
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 6, y: 0))
                        path.addLine(to: CGPoint(x: 3, y: 3.5))
                        path.closeSubpath()
                    }
                    .fill(bubbleColor)
                    .frame(width: 6, height: 3.5)
                }
                .opacity(readout == nil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // 每一帧直接使用插值的位置，子视图无需再次启动位置动画。
            .transaction { $0.animation = nil }
        }
    }
}

private struct OSDCalloutLayout: Layout {
    let endpoint: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let label = subviews[0], tip = subviews[1]
        let labelSize = label.sizeThatFits(.unspecified)
        let tipSize = tip.sizeThatFits(.unspecified)
        let x = bounds.minX + endpoint
        let tipBottom = bounds.midY - 6
        // 允许气泡伸入轨道两侧留白。靠近胶囊端部时只移动文字，尖角仍跟随填充末端。
        let left = min(max(x - labelSize.width / 2, bounds.minX - 19), bounds.maxX + 15 - labelSize.width)
        label.place(at: CGPoint(x: left, y: tipBottom - tipSize.height), anchor: .bottomLeading, proposal: .unspecified)
        tip.place(at: CGPoint(x: x, y: tipBottom), anchor: .bottom, proposal: .unspecified)
    }
}
