import AppKit
import Foundation
import OSLog

private nonisolated let mediaKeyLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "MediaKey")

nonisolated enum MediaKey: Hashable, Sendable {
    case brightnessUp, brightnessDown
    case volumeUp, volumeDown, mute
}

nonisolated struct MediaKeyEvent: Sendable {
    let key: MediaKey
    let isPressed: Bool
    let isRepeat: Bool
    let modifiers: NSEvent.ModifierFlags
}

/// 线程安全不变量：MediaKeyTapBridge 仅由主线程 MediaKeyController 调用管理生命周期，底层 MachPort/RunLoop 由 cleanupBox 释放。
nonisolated final class MediaKeyTapBridge: @unchecked Sendable {
    typealias Handler = @MainActor (MediaKeyEvent) -> Bool

    private let cleanupBox = MediaKeyTapCleanupBox()
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

        // passUnretained:bridge 的生命周期由外部 owner(MediaKeyController)管理;
        // deinit 调用 stop() 同步移除 runLoopSource,移除完成后 in-flight 回调已退出。
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: SystemDefinedEventType.maskBit,
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            mediaKeyLog.error("CGEvent.tapCreate failed (likely missing Accessibility permission)")
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            mediaKeyLog.error("CFMachPortCreateRunLoopSource failed")
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        cleanupBox.install(eventTap: tap, runLoopSource: source)
        mediaKeyLog.notice("MediaKeyTapBridge started with \(keys.count, privacy: .public) keys")
        return true
    }

    func stop() {
        cleanupBox.cleanup()
        handler = nil
        enabledKeys = []
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, cgEvent, refcon in
        guard let refcon else { return Unmanaged.passUnretained(cgEvent) }
        let bridge = Unmanaged<MediaKeyTapBridge>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = bridge.cleanupBox.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // NX_SYSDEFINED 系统事件的解析。常量来源:
        //   - CGEventType.systemDefined 即 kCGEventSystemDefined,SDK 未向
        //     Swift 公开该 case,取值见 SystemDefinedEventType。
        //   - NSEvent.subtype == 8 即 NX_SUBTYPE_AUX_CONTROL_BUTTONS,
        //     覆盖亮度/音量/静音/Eject 等辅助控制键。
        // 解析格式参考 the0neyouseek/MediaKeyTap 与 MonitorControl 的实现。
        guard type == CGEventType(rawValue: SystemDefinedEventType.rawValue),
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

        let handled = MainActor.assumeIsolated {
            bridge.handler?(event) == true
        }

        if handled {
            return nil
        }
        return Unmanaged.passUnretained(cgEvent)
    }
}

/// 线程安全清理容器：在 deinit 阶段释放底层 MachPort 与 RunLoopSource。
private nonisolated final class MediaKeyTapCleanupBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEventTap: CFMachPort?
    private var storedRunLoopSource: CFRunLoopSource?

    var eventTap: CFMachPort? {
        lock.withLock { storedEventTap }
    }

    func install(eventTap: CFMachPort, runLoopSource: CFRunLoopSource) {
        lock.withLock {
            storedEventTap = eventTap
            storedRunLoopSource = runLoopSource
        }
    }

    nonisolated func cleanup() {
        let resources: (CFMachPort?, CFRunLoopSource?) = lock.withLock {
            let resources = (storedEventTap, storedRunLoopSource)
            storedEventTap = nil
            storedRunLoopSource = nil
            return resources
        }
        if let tap = resources.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = resources.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    deinit {
        cleanup()
    }
}
