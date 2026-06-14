import AppKit
import Foundation
import OSLog

private let mediaKeyLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "MediaKey")

enum MediaKey {
    case brightnessUp, brightnessDown
    case volumeUp, volumeDown, mute
}

struct MediaKeyEvent {
    let key: MediaKey
    let isPressed: Bool
    let isRepeat: Bool
    let modifiers: NSEvent.ModifierFlags
}

final class MediaKeyTapBridge {
    typealias Handler = (MediaKeyEvent) -> Bool

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: Handler?
    private var enabledKeys: Set<MediaKey> = []

    func start(keys: Set<MediaKey>, handler: @escaping Handler) -> Bool {
        stop()
        guard !keys.isEmpty else {
            mediaKeyLog.notice("MediaKeyTapBridge.start called with empty keys; staying inactive")
            return false
        }
        self.enabledKeys = keys
        self.handler = handler

        let mask = (1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            mediaKeyLog.error("CGEvent.tapCreate failed (likely missing Accessibility permission)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        mediaKeyLog.notice("MediaKeyTapBridge started with \(keys.count, privacy: .public) keys")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
        enabledKeys = []
    }

    deinit { stop() }

    private static let tapCallback: CGEventTapCallBack = { _, type, cgEvent, refcon in
        guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
        let bridge = Unmanaged<MediaKeyTapBridge>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = bridge.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // NX_SYSDEFINED 系统事件的解析。常量来源:
        //   - CGEventType.systemDefined rawValue == 14(kCGSystemDefined,
        //     该 case 在当前 SDK 对 Swift 不公开,故用裸数字)。
        //   - NSEvent.subtype == 8 即 NX_SUBTYPE_AUX_CONTROL_BUTTONS,
        //     覆盖亮度/音量/静音/Eject 等辅助控制键。
        // 解析格式参考 the0neyouseek/MediaKeyTap 与 MonitorControl 的实现。
        guard type == CGEventType(rawValue: 14),
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.subtype.rawValue == 8
        else {
            return Unmanaged.passUnretained(cgEvent)
        }

        // systemDefined 事件的 data1 编码:
        //   [31:16] keyCode(NX_KEYTYPE_*)
        //   [15:8]  keyState(0x0A = keyDown, 0x0B = keyUp)
        //   [0]     isRepeat 标志位
        let data1 = nsEvent.data1
        let keyCode = Int32((data1 & 0xFFFF_0000) >> 16)
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isPressed = keyState == 0x0A
        let isRepeat = (keyFlags & 0x1) == 1

        // NX_KEYTYPE_* 来自 <IOKit/hidsystem/ev_keymap.h>,由 bridging header 引入。
        let key: MediaKey?
        switch keyCode {
        case Int32(NX_KEYTYPE_BRIGHTNESS_UP): key = .brightnessUp
        case Int32(NX_KEYTYPE_BRIGHTNESS_DOWN): key = .brightnessDown
        case Int32(NX_KEYTYPE_SOUND_UP): key = .volumeUp
        case Int32(NX_KEYTYPE_SOUND_DOWN): key = .volumeDown
        case Int32(NX_KEYTYPE_MUTE): key = .mute
        default: key = nil
        }

        guard let mediaKey = key, bridge.enabledKeys.contains(mediaKey) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let event = MediaKeyEvent(
            key: mediaKey,
            isPressed: isPressed,
            isRepeat: isRepeat,
            modifiers: nsEvent.modifierFlags
        )

        if bridge.handler?(event) == true {
            return nil
        }
        return Unmanaged.passUnretained(cgEvent)
    }
}
