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

/// 媒体键 tap 的生命周期决策:目标按键集合与「当前确实安装的集合」比较,
/// 只有真正变化才允许触碰 tap。
///
/// 独立成值类型,是为了把「配置未变绝不重启 head-insert tap」这条不变量钉在测试里:
/// tap 装在 `.headInsertEventTap` 上、掩码覆盖整个 NX_SYSDEFINED 事件类,重启一次
/// 就是往系统事件流最前面拔插一次拦截点,不应由周期性的显示数值刷新触发。
enum MediaKeyTapLifecycle {
    enum Action: Equatable {
        case keep
        case stop
        case start(Set<MediaKey>)
    }

    static func action(desired: Set<MediaKey>, active: Set<MediaKey>?) -> Action {
        // nil 表示当前没有已安装的 tap,不是“上次请求过空集合”。没有 tap
        // 且也没有目标时无需调用 stop;有目标时必须重新尝试 start。
        guard let active else {
            return desired.isEmpty ? .keep : .start(desired)
        }
        guard desired != active else { return .keep }
        return desired.isEmpty ? .stop : .start(desired)
    }
}

/// 线程安全不变量：MediaKeyTapBridge 仅由主线程 MediaKeyController 调用管理生命周期，底层 MachPort/RunLoop 由 cleanupBox 释放。
nonisolated final class MediaKeyTapBridge: @unchecked Sendable {
    typealias Handler = @MainActor (MediaKeyEvent) -> Bool

    private let cleanupBox = MediaKeyTapCleanupBox()
    private var handler: Handler?
    private var enabledKeys: Set<MediaKey> = []

    /// 当前真正安装在系统事件流中的按键集合。nil 表示没有成功安装 tap;
    /// 只读给主线程上的 MediaKeyController,不把一次失败的 start 误记成已生效。
    var activeKeys: Set<MediaKey>? {
        guard cleanupBox.eventTap != nil else { return nil }
        return enabledKeys
    }

    func start(keys: Set<MediaKey>, handler: @escaping Handler) -> Bool {
        // 幂等:已装着同一个按键集合就不再重建。重建意味着把 headInsert 拦截点
        // 从系统事件流里拔掉再插一次,调用方(每 5s 一次的显示刷新等)在配置
        // 未变时不应触发它。
        if cleanupBox.eventTap != nil, keys == enabledKeys {
            return true
        }
        stop()
        guard !keys.isEmpty else {
            mediaKeyLog.notice("MediaKeyTapBridge.start called with empty keys; staying inactive")
            return false
        }
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
        // 只有在 tap 和 run-loop source 都创建成功后才记录 handler/按键;
        // 这样失败的 start 不会给上层留下“已经激活”的假状态。先于 enable
        // 写入,避免首个系统事件到达时看不到配置。
        self.enabledKeys = keys
        self.handler = handler
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
