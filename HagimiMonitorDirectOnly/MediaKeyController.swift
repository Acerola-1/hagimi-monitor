import AppKit
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class MediaKeyController {
    private let tap = MediaKeyTapBridge()
    private let feedback = MediaControlOSD()
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
        if wantBrightness, hasExternalDDCDisplay() {
            keys.formUnion([.brightnessUp, .brightnessDown])
        }
        // 音量键仅在默认音频设备自身不可控(典型:音频走显示器喇叭)时接管。
        // 对齐 MonitorControl MediaKeyTapManager.updateMediaKeyTap 的策略,
        // 避免 AirPods/蓝牙/USB 声卡场景下音量键失效。
        // 设备切换的自动重评估依赖设置变化、显示器刷新等事件触发的 refresh。
        let volumeTarget = wantVolume ? targetDisplayID(for: .volumeUp) : nil
        let shouldTakeVolume = volumeTarget != nil
        if shouldTakeVolume {
            keys.formUnion([.volumeUp, .volumeDown, .mute])
        }

        if feedback.control == .brightness, !keys.contains(.brightnessUp) {
            feedback.hide()
        } else if let control = feedback.control, control != .brightness, feedback.displayID != volumeTarget {
            feedback.hide()
        }
        apply(desired: keys)
    }

    func dismissFeedback() { feedback.hide() }

    /// 按目标按键集合触碰 tap,但**只在目标与当前已安装状态不一致时**才重建。
    ///
    /// tap 装在 `.headInsertEventTap` 上、掩码覆盖整个 NX_SYSDEFINED 事件类,
    /// 重建一次就是往系统事件流最前面插一次新拦截点;而本方法挂在显示器刷新
    /// 链路的收尾上(轮询 5s 一次、外加每次展开/显示器变化),配置没变也重建
    /// 没有必要,还可能扰动系统事件/焦点状态。因此这里以 tap 的实际安装状态
    /// 为准做幂等:同集合直接返回,不碰 tap。
    /// 授权、锁定、设置、音频路由、显示拓扑这些真正改变决策的输入各自有订阅,
    /// 会在变化时再次进入本方法。
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
        // Option 单按打开对应系统设置面板(对齐 MonitorControl handleOpenPrefPane)。
        // 注意:Option + repeat 不触发,避免长按反复弹面板。
        if isOptionOnly(modifiers: event.modifiers), !event.isRepeat {
            openPreferencePane(for: event.key)
            return true
        }

        // 亮度跟随鼠标所在屏，音量跟随当前音频输出。没有匹配目标时交还系统。
        guard let targetDisplayID = targetDisplayID(for: event.key) else {
            return false
        }

        switch event.key {
        case .mute:
            // Mute 键只响应单次按下,不响应 keyUp 与 repeat(对齐 MonitorControl:
            // "The mute key should not respond to press + hold or keyup")。
            // 否则长按 F10 会反复静音/取消静音。
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

    /// 根据鼠标当前所在屏幕选择亮度键目标。鼠标在内建屏时交还系统,
    /// 让 macOS 继续控制内建屏亮度;无法取得屏幕位置时才使用单外接屏兜底。
    /// 参考 MonitorControl DisplayManager.getCurrentDisplay:用 NSEvent.mouseLocation
    /// 与 NSScreen.screens 做 hit-test,再映射回 CGDirectDisplayID。
    private func targetDisplayIDForCurrentMouseLocation() -> CGDirectDisplayID? {
        let mouseDisplayID = currentDisplayIDUnderMouse()
        guard let controller else { return nil }
        let displays = controller.displays.map {
            (
                displayID: $0.id,
                isBuiltIn: $0.isBuiltIn,
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
        let current = controller.value(for: control, displayID: displayID)
        let next = min(100, max(0, current + delta)).rounded()
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
        feedback.show(control: kind, value: value, displayID: displayID) { [weak self] value, final in
            guard let self, self.controller?.displays.contains(where: {
                $0.id == displayID && $0.storageID == storageID
            }) == true else { return false }
            if control == .volume, self.targetDisplayID(for: .volumeUp) != displayID { return false }
            return self.submit(value, for: control, on: displayID, final: final)
        }
        return true
    }

    private func submit(_ value: Double, for control: DisplayControlKind, on displayID: CGDirectDisplayID, final: Bool) -> Bool {
        guard let controller else { return false }
        let afterNativeWrite: (@MainActor @Sendable () -> Void)?
        if control == .brightness, controller.displays.contains(where: {
            $0.id == displayID && $0.kind == .appleNative && $0.dimmingMode == .hardware
        }) {
            afterNativeWrite = { [weak self] in self?.feedback.refreshLuminance(on: displayID, percent: value) }
        } else {
            afterNativeWrite = nil
        }
        guard controller.setValueAsync(value, for: control, displayID: displayID,
                                       final: final, afterNativeWrite: afterNativeWrite) else { return false }
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

    private func hasExternalDDCDisplay() -> Bool {
        controller?.displays.contains { !$0.isBuiltIn && $0.supportsBrightness } ?? false
    }

}
