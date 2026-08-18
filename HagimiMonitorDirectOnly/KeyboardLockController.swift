import Foundation

/// 键盘锁定引擎:会话级 CGEventTap 吞掉全部键盘事件(keyDown/keyUp/
/// flagsChanged),鼠标事件不经过本 tap,点击解锁等鼠标交互不受影响。
///
/// 仅 Direct 渠道编译:主动式(拦截)事件 tap 属辅助功能权限体系,
/// 与 App Store 沙盒不兼容。
///
/// 线程模型与 `MediaKeyTapBridge` 一致:非隔离类,owner(`QuickToolsStore`,
/// MainActor)在主线程调用 start/stop;回调经 refcon 取回实例,
/// 无静态全局桥。
final class KeyboardLockController {
    /// 防"锁了就忘"的自动解锁兜底:默认 20 分钟后解除拦截。
    static let autoUnlockInterval: TimeInterval = 20 * 60

    /// 自动解锁触发(主线程回调),owner 负责同步 UI 状态。
    var onAutoUnlock: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var autoUnlockTimer: DispatchSourceTimer?

    /// 安装拦截 tap。重复调用幂等。
    /// - Returns: 是否成功(未授权时 tapCreate 失败返回 false)。
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        // passUnretained:生命周期由 owner 管理,stop() 同步移除 runLoopSource,
        // 移除完成后 in-flight 回调已退出(同 MediaKeyTapBridge 约定)。
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        startAutoUnlockTimer()
        return true
    }

    /// 解除拦截并停掉自动解锁计时。重复调用幂等。
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        autoUnlockTimer?.cancel()
        autoUnlockTimer = nil
    }

    deinit { stop() }

    // MARK: - 自动解锁

    /// 锁定生效期间计时,到点自动解锁。
    private func startAutoUnlockTimer() {
        autoUnlockTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.autoUnlockInterval)
        timer.setEventHandler { [weak self] in
            self?.stop()
            self?.onAutoUnlock?()
        }
        autoUnlockTimer = timer
        timer.resume()
    }

    // MARK: - Tap 回调

    /// 回调对三类键盘事件恒返回 nil 吞掉事件;tap 被系统因超时/用户输入
    /// 禁用时在回调内自恢复,保证锁定不因偶发禁用而静默失效。
    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<KeyboardLockController>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = controller.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}
