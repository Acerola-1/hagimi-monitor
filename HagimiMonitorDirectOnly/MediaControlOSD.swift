import AppKit
import SwiftUI

/// 媒体键反馈与菜单栏面板独立，仅在首次收到调节事件时创建窗口。
@MainActor
final class MediaControlOSD {
    private let state = MediaControlOSDState()
    private var panel: NSPanel?
    private var presentation: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var luminanceRead: Task<Void, Never>?
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
        } ?? NSScreen.main
        guard let screen else { return }
        let placement = AppDelegate.shared?.mediaOSDPlacement(on: screen)
        guard placement?.suppressed != true else { hide(); return }

        if self.displayID != displayID || state.control != control { hide() }
        self.displayID = displayID
        self.updateValue = updateValue
        state.control = control
        updateDisplayedValue(value)

        let panel = self.panel ?? makePanel()
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let centerX = placement?.anchor?.midX ?? frame.midX
        let top = min(placement?.anchor?.minY ?? frame.maxY, frame.maxY) - 6
        let x = max(frame.minX + 6, min(centerX - size.width / 2, frame.maxX - size.width - 6))
        let origin = CGPoint(x: x, y: top - size.height)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        scheduleDismissal()
    }

    func hide() {
        presentation?.cancel()
        presentation = nil
        dismissal?.cancel()
        dismissal = nil
        luminanceRead?.cancel()
        luminanceRead = nil
        panel?.orderOut(nil)
        displayID = nil
        updateValue = nil
        isEditing = false
        pointerInside = false
        state.isInteractive = false
        state.luminance = nil
    }

    func refreshLuminance(on displayID: CGDirectDisplayID, percent: Double) {
        guard self.displayID == displayID, state.control == .brightness, state.value == percent else { return }
        luminanceRead?.cancel()
        luminanceRead = Task { [weak self] in
            let nits = await NativeDisplayLuminanceReader.read(displayID: displayID, expectedPercent: percent)
            guard !Task.isCancelled else { return }
            self?.state.luminance = nits
        }
    }

    private func makePanel() -> NSPanel {
        let size = CGSize(width: 276, height: 52)
        let panel = NSPanel(
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

        let backdrop = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = CGFloat(MonitorConstants.panelCornerRadius)
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        let host = MediaControlOSDHost(rootView: MediaControlOSDView(
            state: state,
            changeValue: { [weak self] value in self?.changeValue(value, final: self?.isEditing != true) },
            edit: { [weak self] in self?.edit($0) }
        ))
        host.hover = { [weak self] in self?.hover($0) }
        host.frame = backdrop.bounds
        host.autoresizingMask = [.width, .height]
        backdrop.addSubview(host)
        panel.contentView = backdrop
        self.panel = panel
        return panel
    }

    private func changeValue(_ value: Double, final: Bool) {
        guard updateValue?(value, final) == true else { return }
        updateDisplayedValue(value)
        if state.control == .mute, value > 0 { state.control = .volume }
        scheduleDismissal()
    }

    private func updateDisplayedValue(_ value: Double) {
        guard state.value != value else { return }
        luminanceRead?.cancel()
        state.luminance = nil
        state.value = value
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
        if let panel, panel.alphaValue < 1 { panel.alphaValue = 1 }
        guard displayID != nil, !state.isInteractive else { return }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1450))
            guard let self, let panel = self.panel, !Task.isCancelled else { return }
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

@Observable
private final class MediaControlOSDState {
    var control: MediaKeyKind = .brightness
    var value: Double = 0
    var luminance: Double?
    var isInteractive = false
}

private struct MediaControlOSDView: View {
    let state: MediaControlOSDState
    let changeValue: @MainActor @Sendable (Double) -> Void
    let edit: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            if state.isInteractive {
                Slider(value: Binding(get: { state.value }, set: changeValue), in: 0...100, step: 1) {
                    Text(label)
                } onEditingChanged: { editing in
                    edit(editing)
                }
                .labelsHidden()
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<16) { index in
                        let fill = min(1, max(0, state.value / 100 * 16 - Double(index)))
                        UnevenRoundedRectangle(cornerRadii: .init(
                            topLeading: index == 0 ? 3 : 1,
                            bottomLeading: index == 0 ? 3 : 1,
                            bottomTrailing: index == 15 ? 3 : 1,
                            topTrailing: index == 15 ? 3 : 1
                        ))
                        .fill(.primary.opacity(0.14 + 0.71 * fill))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(percentageText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                if let luminanceText {
                    Text(luminanceText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 61, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(verbatim: [percentageText, luminanceText].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHidden(state.isInteractive)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var percentageText: String { (state.value / 100).formatted(.percent.precision(.fractionLength(0))) }

    private var luminanceText: String? {
        state.luminance.map { String.localizedStringWithFormat(String(localized: "display.control.nits"), Int($0.rounded())) }
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
        case .brightness: state.value < 50 ? "sun.min" : "sun.max"
        case .volume: state.value < 34 ? "speaker.wave.1" : state.value < 67 ? "speaker.wave.2" : "speaker.wave.3"
        case .mute: "speaker.slash"
        }
    }
}
