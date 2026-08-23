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

    /// 标准步进(对齐 macOS 系统行为:1/16)。
    private let standardStep: Double = 100.0 / 16.0
    private let fineStep: Double = 100.0 / 64.0
    /// unmute 时的保底最小音量(对齐 MonitorControl:1 个 chiclet ≈ 1/16)。
    /// 避免上次保存值恰好为 0 时 unmute 又立刻静音。
    private let unmuteFallback: Double = 100.0 / 16.0

    private var lastNonZeroVolume: [CGDirectDisplayID: Double] = [:]

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
            tap.stop()
            return
        }
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
        // 音量键仅在默认音频设备自身不可控(典型:音频走显示器喇叭)时接管。
        // 对齐 MonitorControl MediaKeyTapManager.updateMediaKeyTap 的策略,
        // 避免 AirPods/蓝牙/USB 声卡场景下音量键失效。
        // 设备切换的自动重评估依赖设置变化、显示器刷新等事件触发的 refresh。
        let shouldTakeVolume = wantVolume
            && !AudioOutputDetector.defaultOutputDeviceIsControllable()
            && hasExternalAudioCapableDisplay()
        if shouldTakeVolume {
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
        // Option 单按打开对应系统设置面板(对齐 MonitorControl handleOpenPrefPane)。
        // 注意:Option + repeat 不触发,避免长按反复弹面板。
        if isOptionOnly(modifiers: event.modifiers), !event.isRepeat {
            openPreferencePane(for: event.key)
            return true
        }

        // 定向控制:只作用于鼠标当前所在的外接屏(对齐 MonitorControl
        // getAffectedDisplays + getCurrentDisplay 的默认行为)。
        // 鼠标在内建屏 → 不吞事件,让 macOS 原生处理 MacBook 亮度/音量。
        guard let targetDisplayID = targetDisplayIDForCurrentMouseLocation() else {
            return false
        }

        switch event.key {
        case .mute:
            // Mute 键只响应单次按下,不响应 keyUp 与 repeat(对齐 MonitorControl:
            // "The mute key should not respond to press + hold or keyup")。
            // 否则长按 F10 会反复静音/取消静音。
            guard event.isPressed, !event.isRepeat else { return true }
            toggleMute(on: targetDisplayID)
            return true
        case .brightnessUp, .brightnessDown, .volumeUp, .volumeDown:
            guard event.isPressed else { return true }
        }

        let step = stepSize(for: event.key, modifiers: event.modifiers)
        switch event.key {
        case .brightnessUp:
            adjustBrightness(by: +step, on: targetDisplayID); return true
        case .brightnessDown:
            adjustBrightness(by: -step, on: targetDisplayID); return true
        case .volumeUp:
            adjustVolume(by: +step, on: targetDisplayID); return true
        case .volumeDown:
            adjustVolume(by: -step, on: targetDisplayID); return true
        case .mute:
            return true
        }
    }

    /// 返回鼠标当前所在的外接屏 displayID。
    /// 鼠标在内建屏或无法判定时,若只有一台外接屏可控则直接兜底作用于它
    /// (鼠标习惯留在内建屏、用快捷键调外接屏是常见场景);多台外接屏时
    /// 无法判断意图,仍返回 nil 交给系统原生处理。
    /// 参考 MonitorControl DisplayManager.getCurrentDisplay:用 NSEvent.mouseLocation
    /// 与 NSScreen.screens 做 hit-test,再映射回 CGDirectDisplayID。
    private func targetDisplayIDForCurrentMouseLocation() -> CGDirectDisplayID? {
        if let displayID = externalDisplayIDUnderMouse() {
            return displayID
        }
        return singleExternalDisplayIDFallback()
    }

    private func externalDisplayIDUnderMouse() -> CGDirectDisplayID? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return nil
        }
        let displayID = screenWithMouse.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let displayID,
              let controller,
              let display = controller.displays.first(where: { $0.id == displayID }),
              !display.isBuiltIn
        else {
            return nil
        }
        return displayID
    }

    private func singleExternalDisplayIDFallback() -> CGDirectDisplayID? {
        guard let controller else { return nil }
        let externalDisplays = controller.displays.filter { !$0.isBuiltIn }
        guard externalDisplays.count == 1 else { return nil }
        return externalDisplays.first?.id
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

    private func stepSize(for key: MediaKey, modifiers: NSEvent.ModifierFlags) -> Double {
        let isFine = modifiers.contains(.shift) && modifiers.contains(.option)
        return isFine ? fineStep : standardStep
    }

    private func adjustBrightness(by delta: Double, on displayID: CGDirectDisplayID) {
        guard let controller,
              let display = controller.displays.first(where: { $0.id == displayID }),
              display.supportsBrightness
        else { return }
        let current = controller.value(for: .brightness, displayID: displayID)
        let next = min(100, max(0, current + delta)).rounded()
        controller.setValueAsync(next, for: .brightness, displayID: displayID)
        if settings?.mediaKeyShowOSD == true {
            osd.show(.brightness, displayID: displayID, percent: next)
        }
    }

    private func adjustVolume(by delta: Double, on displayID: CGDirectDisplayID) {
        guard let controller,
              let display = controller.displays.first(where: { $0.id == displayID }),
              display.supportsVolume
        else { return }
        let current = controller.value(for: .volume, displayID: displayID)
        let next = min(100, max(0, current + delta)).rounded()
        controller.setValueAsync(next, for: .volume, displayID: displayID)
        rememberVolume(next, for: displayID)
        if settings?.mediaKeyShowOSD == true {
            let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
            osd.show(image, displayID: displayID, percent: next)
        }
    }

    private func toggleMute(on displayID: CGDirectDisplayID) {
        guard let controller,
              let display = controller.displays.first(where: { $0.id == displayID }),
              display.supportsVolume
        else { return }
        let current = controller.value(for: .volume, displayID: displayID)
        let next: Double
        if current > 0 {
            next = 0
        } else {
            next = lastNonZeroVolume[displayID] ?? unmuteFallback
        }
        controller.setValueAsync(next, for: .volume, displayID: displayID)
        rememberVolume(next, for: displayID)
        if settings?.mediaKeyShowOSD == true {
            let image: OSDImage = next <= 0 ? .speakerMuted : .speaker
            osd.show(image, displayID: displayID, percent: next)
        }
    }

    private func rememberVolume(_ value: Double, for displayID: CGDirectDisplayID) {
        guard value > 0 else { return }
        lastNonZeroVolume[displayID] = value
    }

    private func hasExternalDDCDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsBrightness } ?? false
    }

    private func hasExternalAudioCapableDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsVolume } ?? false
    }
}
