import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class MediaKeyController {
    private let tap = MediaKeyTapBridge()
    private let osd = OSDBridge()
    let permission = AccessibilityPermissionService.shared
    private weak var controller: DisplayControlController?
    private var settings: MonitorSettings?

    private var standardStep: Double = 100.0 / 16.0
    private var fineStep: Double = 100.0 / 64.0

    init() {}

    func attach(controller: DisplayControlController, settings: MonitorSettings) {
        self.controller = controller
        self.settings = settings
        refresh()
    }

    func refresh() {
        guard let settings else { return }
        let wantBrightness = settings.mediaKeyBrightnessEnabled
        let wantVolume = settings.mediaKeyVolumeEnabled

        guard wantBrightness || wantVolume else {
            tap.stop()
            return
        }
        guard permission.isTrusted else {
            tap.stop()
            return
        }

        var keys: Set<MediaKey> = []
        if wantBrightness, hasExternalDDCDisplay() {
            keys.formUnion([.brightnessUp, .brightnessDown])
        }
        if wantVolume, hasExternalAudioCapableDisplay() {
            keys.formUnion([.volumeUp, .volumeDown, .mute])
        }
        if keys.isEmpty {
            tap.stop()
            return
        }

        _ = tap.start(keys: keys) { [weak self] event in
            guard let self else { return false }
            return self.handle(event: event)
        }
    }

    private func handle(event: MediaKeyEvent) -> Bool {
        guard event.isPressed else { return true }

        let isOptionOnly = event.modifiers.contains(.option)
            && !event.modifiers.contains(.shift)
            && !event.modifiers.contains(.command)
            && !event.modifiers.contains(.control)

        if isOptionOnly && !event.isRepeat {
            switch event.key {
            case .brightnessUp, .brightnessDown:
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
            case .volumeUp, .volumeDown, .mute:
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
            }
            return true
        }

        let isFine = event.modifiers.contains(.shift) && event.modifiers.contains(.option)
        let invertFine: Bool
        switch event.key {
        case .brightnessUp, .brightnessDown:
            invertFine = settings?.mediaKeyFineScaleBrightness ?? false
        default:
            invertFine = settings?.mediaKeyFineScaleVolume ?? false
        }
        let useFine = invertFine ? !isFine : isFine
        let step = useFine ? fineStep : standardStep

        switch event.key {
        case .brightnessUp:
            adjustBrightness(by: +step); return true
        case .brightnessDown:
            adjustBrightness(by: -step); return true
        case .volumeUp:
            adjustVolume(by: +step); return true
        case .volumeDown:
            adjustVolume(by: -step); return true
        case .mute:
            toggleMute(); return true
        }
    }

    private func adjustBrightness(by delta: Double) {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsBrightness {
            let current = controller.value(for: .brightness, displayID: display.id)
            let next = min(100, max(0, current + delta))
            controller.setValueAsync(next, for: .brightness, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                osd.show(.brightness, displayID: display.id, percent: next)
            }
        }
    }

    private func adjustVolume(by delta: Double) {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsVolume {
            let current = controller.value(for: .volume, displayID: display.id)
            let next = min(100, max(0, current + delta))
            controller.setValueAsync(next, for: .volume, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
                osd.show(image, displayID: display.id, percent: next)
            }
        }
    }

    private func toggleMute() {
        guard let controller else { return }
        for display in controller.displays where !display.isBuiltIn && display.supportsVolume {
            let current = controller.value(for: .volume, displayID: display.id)
            let next: Double = current > 0 ? 0 : 50
            controller.setValueAsync(next, for: .volume, displayID: display.id)
            if settings?.mediaKeyShowOSD == true {
                let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
                osd.show(image, displayID: display.id, percent: next)
            }
        }
    }

    private func hasExternalDDCDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsBrightness } ?? false
    }

    private func hasExternalAudioCapableDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsVolume } ?? false
    }
}
