import AppKit
import CoreGraphics
import Foundation

@MainActor
final class MediaKeyController {
    private let tap = MediaKeyTapBridge()
    private let feedback = MediaControlOSD()
    let permission = AccessibilityPermissionService.shared
    private weak var controller: DisplayControlController?
    private var settings: MonitorSettings?

    private let standardStep: Double = 100.0 / 16.0
    private let fineStep: Double = 100.0 / 64.0
    /// 缺少历史音量时，以一个标准步进解除静音。
    private let unmuteFallback: Double = 100.0 / 16.0

    private var lastNonZeroVolume: [CGDirectDisplayID: Double] = [:]

    private var feedbackOutput: AudioOutputDetector.VolumeOutput?
    private var nativeRestoreLevels: [UInt32: Double] = [:]

    init() {}

    func attach(controller: DisplayControlController, settings: MonitorSettings) {
        self.controller = controller
        self.settings = settings
        refresh()
    }

    func refresh() {
        guard let settings else { return }
        // 键盘锁定期间功能键由锁定 tap 统一吞掉,媒体键 tap 必须停用:
        // 两者同为 headInsert 且掩码在 systemDefined 上重叠,锁定期内重建会插到锁 tap 之前,
        // 让功能键绕过键盘锁;解锁后由锁定状态订阅触发的 refresh 恢复。
        guard !QuickToolsStore.shared.keyboardLocked else {
            apply(desired: [])
            return
        }
        let wantBrightness = settings.mediaKeyBrightnessEnabled
        let wantVolume = settings.mediaKeyVolumeEnabled

        guard wantBrightness || wantVolume else {
            apply(desired: [])
            return
        }
        guard permission.isTrusted else {
            apply(desired: [])
            return
        }

        var keys: Set<MediaKey> = []
        if wantBrightness, controller?.displays.contains(where: { $0.supportsBrightness }) == true {
            keys.formUnion([.brightnessUp, .brightnessDown])
        }
        let nativeOutput = wantVolume ? AudioOutputDetector.volumeOutput() : nil
        let volumeTarget = wantVolume && nativeOutput == nil ? targetDisplayID(for: .volumeUp) : nil
        if nativeOutput != nil || volumeTarget != nil {
            keys.formUnion([.volumeUp, .volumeDown, .mute])
        }

        if feedback.control == .brightness, !keys.contains(.brightnessUp) {
            feedback.hide()
        } else if let control = feedback.control, control != .brightness, (feedbackOutput != nativeOutput || (nativeOutput == nil && feedback.displayID != volumeTarget)) {
            feedback.hide()
        }
        apply(desired: keys)
    }

    func dismissFeedback() { feedback.hide() }

    /// 仅在监听的按键集合变化时重建事件 tap，避免干扰系统事件顺序。
    private func apply(desired: Set<MediaKey>) {
        switch MediaKeyTapLifecycle.action(desired: desired, active: tap.activeKeys) {
        case .keep:
            return
        case .stop:
            tap.stop()
            feedback.hide()
        case .start(let keys):
            // start 失败时 activeKeys 仍为 nil;下一次真正的输入变化可以重试,
            // 不把失败请求缓存成已生效状态。
            _ = tap.start(keys: keys) { [weak self] event in
                guard let self else { return false }
                return self.handle(event: event)
            }
        }
    }

    private func handle(event: MediaKeyEvent) -> Bool {
        switch event.key {
        case .volumeUp, .volumeDown, .mute:
            if let output = AudioOutputDetector.volumeOutput() {
                if isOptionOnly(modifiers: event.modifiers) {
                    if event.isPressed && !event.isRepeat { openPreferencePane(for: event.key) }
                    return true
                }
                guard event.isPressed, !(event.key == .mute && event.isRepeat) else { return true }
                return adjustAudio(event, on: output)
            }
        default: break
        }

        // 亮度跟随鼠标所在屏，音量跟随当前音频输出。没有匹配目标时交还系统。
        guard let targetDisplayID = targetDisplayID(for: event.key) else {
            return false
        }

        if isOptionOnly(modifiers: event.modifiers) {
            if event.isPressed && !event.isRepeat { openPreferencePane(for: event.key) }
            return true
        }

        switch event.key {
        case .mute:
            // 长按静音键只切换一次。
            guard event.isPressed, !event.isRepeat else { return true }
            return toggleMute(on: targetDisplayID)
        case .brightnessUp, .brightnessDown, .volumeUp, .volumeDown:
            guard event.isPressed else { return true }
        }

        let step = stepSize(modifiers: event.modifiers)
        switch event.key {
        case .brightnessUp:
            return adjust(.brightness, by: step, on: targetDisplayID)
        case .brightnessDown:
            return adjust(.brightness, by: -step, on: targetDisplayID)
        case .volumeUp:
            return adjust(.volume, by: step, on: targetDisplayID)
        case .volumeDown:
            return adjust(.volume, by: -step, on: targetDisplayID)
        case .mute:
            return true
        }
    }

    private func adjustAudio(_ event: MediaKeyEvent, on output: AudioOutputDetector.VolumeOutput) -> Bool {
        guard let level = output.level else { return false }
        let muted = output.muted
        let next: Double
        if event.key == .mute {
            if level > 0 { nativeRestoreLevels[output.id] = level }
            if let muted, level > 0, output.setMuted(!muted) {
                next = muted ? level : 0
            } else {
                next = level > 0 && muted != true ? 0 : nativeRestoreLevels[output.id] ?? unmuteFallback
                guard output.setLevel(next) else { return false }
            }
        } else {
            let step = stepSize(modifiers: event.modifiers)
            next = min(100, max(0, (muted == true ? 0 : level) + (event.key == .volumeUp ? step : -step)))
            guard output.setLevel(next) else { return false }
        }
        feedbackOutput = output
        feedback.show(control: next == 0 ? .mute : .volume, value: next,
                      displayID: currentDisplayIDUnderMouse() ?? CGMainDisplayID()) { value, _ in
            guard AudioOutputDetector.volumeOutput() == output else { return false }
            return output.setLevel(value)
        }
        return true
    }

    private func targetDisplayIDForCurrentMouseLocation() -> CGDirectDisplayID? {
        let mouseDisplayID = currentDisplayIDUnderMouse()
        guard let controller else { return nil }
        let displays = controller.displays.map {
            (
                displayID: $0.id,
                supportsBrightness: $0.supportsBrightness
            )
        }
        return MediaKeyTargetSelector.brightnessTarget(
            mouseDisplayID: mouseDisplayID,
            displays: displays
        )
    }

    private func targetDisplayID(for key: MediaKey) -> CGDirectDisplayID? {
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard let controller else { return nil }
            guard let output = AudioOutputDetector.defaultOutputDescription(), !output.isControllable else { return nil }
            let externals = controller.displays.filter { !$0.isBuiltIn && $0.supportsVolume }
            let displays = externals.map {
                (
                    identity: displayIdentity(for: $0),
                    displayID: $0.id,
                    supportsVolume: $0.supportsVolume
                )
            }
            return MediaKeyTargetSelector.volumeTarget(
                audioOutput: output,
                boundIdentity: nil,
                boundDisplayID: nil,
                displays: displays,
                displayNames: Dictionary(uniqueKeysWithValues: externals.map { ($0.id, $0.name) })
            )
        case .brightnessUp, .brightnessDown:
            return targetDisplayIDForCurrentMouseLocation()
        }
    }

    private func displayIdentity(for display: ControlledDisplay) -> DisplayIdentity {
        let serial = CGDisplaySerialNumber(display.id)
        return DisplayIdentity(
            vendorID: UInt16(truncatingIfNeeded: CGDisplayVendorNumber(display.id)),
            productID: UInt16(truncatingIfNeeded: CGDisplayModelNumber(display.id)),
            serialNumber: serial == 0 ? nil : String(serial),
            edidUUID: nil,
            isBuiltIn: display.isBuiltIn
        )
    }

    private func currentDisplayIDUnderMouse() -> CGDirectDisplayID? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return nil
        }
        return screenWithMouse.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func isOptionOnly(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.option)
            && !modifiers.contains(.shift)
            && !modifiers.contains(.command)
            && !modifiers.contains(.control)
    }

    private func openPreferencePane(for key: MediaKey) {
        switch key {
        case .brightnessUp, .brightnessDown:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
        case .volumeUp, .volumeDown, .mute:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
        }
    }

    private func stepSize(modifiers: NSEvent.ModifierFlags) -> Double {
        let isFine = modifiers.contains(.shift) && modifiers.contains(.option)
        return isFine ? fineStep : standardStep
    }

    private func adjust(_ control: DisplayControlKind, by delta: Double, on displayID: CGDirectDisplayID) -> Bool {
        guard let controller else { return false }
        guard let current = controller.mediaKeyBaseline(for: control, displayID: displayID) else { return false }
        let next = min(100, max(0, current + delta))
        return submitWithFeedback(next, for: control, on: displayID)
    }

    private func toggleMute(on displayID: CGDirectDisplayID) -> Bool {
        guard let controller else { return false }
        let current = controller.value(for: .volume, displayID: displayID)
        let next: Double
        if current > 0 {
            rememberVolume(current, for: displayID)
            next = 0
        } else {
            // 恢复优先级:进程内最近非零音量 → 持久化音量(DDC 写入成功时保存,跨会话)→ 兜底。
            next = lastNonZeroVolume[displayID]
                ?? persistedNonZeroVolume(for: displayID)
                ?? unmuteFallback
        }
        return submitWithFeedback(next, for: .volume, on: displayID, muted: next == 0)
    }

    private func submitWithFeedback(
        _ value: Double, for control: DisplayControlKind, on displayID: CGDirectDisplayID, muted: Bool = false
    ) -> Bool {
        let kind: MediaKeyKind
        switch control {
        case .brightness: kind = .brightness
        case .volume: kind = muted ? .mute : .volume
        case .contrast: return false
        }
        guard let storageID = controller?.displays.first(where: { $0.id == displayID })?.storageID,
              submit(value, for: control, on: displayID, final: true) else { return false }
        feedbackOutput = nil
        feedback.show(control: kind, value: value, displayID: displayID,
                      expectsLuminance: usesNativeBrightness(control, on: displayID)) { [weak self] value, final in
            guard let self, self.controller?.displays.contains(where: {
                $0.id == displayID && $0.storageID == storageID
            }) == true else { return false }
            if control == .volume, self.targetDisplayID(for: .volumeUp) != displayID { return false }
            return self.submit(value, for: control, on: displayID, final: final)
        }
        return true
    }

    private func usesNativeBrightness(_ control: DisplayControlKind, on displayID: CGDirectDisplayID) -> Bool {
        control == .brightness && controller?.displays.contains {
            $0.id == displayID && ($0.kind == .appleNative || $0.kind == .builtIn) && $0.dimmingMode == .hardware
        } == true
    }

    private func submit(_ value: Double, for control: DisplayControlKind, on displayID: CGDirectDisplayID, final: Bool) -> Bool {
        guard let controller else { return false }
        let afterNativeWrite: (@MainActor @Sendable () -> Void)?
        let nativeBrightness = usesNativeBrightness(control, on: displayID)
        if nativeBrightness {
            afterNativeWrite = { [weak self] in self?.feedback.refreshLuminance(on: displayID, percent: value) }
        } else {
            afterNativeWrite = nil
        }
        guard controller.setValueAsync(value, for: control, displayID: displayID,
                                       final: final, smoothBrightness: nativeBrightness, afterNativeWrite: afterNativeWrite) else { return false }
        switch control {
        case .brightness:
            guard CGDisplayIsInMirrorSet(displayID) != 0 else { break }
            let primary = CGDisplayMirrorsDisplay(displayID)
            let mirrorSource = primary == kCGNullDirectDisplay ? displayID : primary
            // 镜像已经共享源画面，额外写入仅用于独立的硬件背光。
            for display in controller.displays where display.id != displayID && display.supportsBrightness && display.dimmingMode == .hardware {
                guard display.id == mirrorSource || CGDisplayMirrorsDisplay(display.id) == mirrorSource else { continue }
                controller.setValueAsync(value, for: control, displayID: display.id, final: final)
            }
        case .volume:
            rememberVolume(value, for: displayID)
        case .contrast:
            break
        }
        return true
    }

    private func rememberVolume(_ value: Double, for displayID: CGDirectDisplayID) {
        guard value > 0 else { return }
        lastNonZeroVolume[displayID] = value
    }

    /// 从 UserDefaults 读取持久化音量(DDC 写入成功时由 DisplayControlService 保存)。
    /// 与 DisplayControlService.storedValueKey 的 key 格式保持一致。
    private func persistedNonZeroVolume(for displayID: CGDirectDisplayID) -> Double? {
        guard let controller,
              let display = controller.displays.first(where: { $0.id == displayID }) else {
            return nil
        }
        let key = "displayControl.value.\(display.storageID).\(DisplayControlKind.volume.storageKey)"
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return value > 0 ? min(100, max(0, value)) : nil
    }

}
