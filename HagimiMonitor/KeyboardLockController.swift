import CoreGraphics
import Foundation

/// CGEventType.systemDefined 的共享常量。kCGEventSystemDefined ==
/// NX_SYSDEFINED == 14,该 case 在当前 SDK 对 Swift 不公开;
/// 媒体键与键盘锁两个事件 tap 都拦截此通道,统一定义避免裸值漂移。
enum SystemDefinedEventType {
    static let rawValue: UInt32 = 14
    static let maskBit: CGEventMask = 1 << rawValue
}

/// 键盘锁定引擎:会话级 CGEventTap 吞掉全部键盘事件(keyDown/keyUp/
/// flagsChanged/systemDefined),鼠标事件不经过本 tap,点击解锁等鼠标
/// 交互不受影响。
///
/// 双渠道共用:Direct 凭辅助功能权限创建 tap(该权限同时服务媒体键
/// 接管);App Store 沙盒内凭输入监控权限创建(macOS 26 实测该权限
/// 足以建立过滤型 tap)。
///
/// 线程模型:非隔离类,owner(`QuickToolsStore`,MainActor)在主线程
/// 调用 start/stop;回调经 refcon 取回实例,无静态全局桥。
final class KeyboardLockController {
    /// 防"锁了就忘"的自动解锁兜底:默认 20 分钟后解除拦截。
    static let autoUnlockInterval: TimeInterval = 20 * 60

    /// 自动解锁触发(主线程回调),owner 负责同步 UI 状态。
    var onAutoUnlock: (() -> Void)?

    /// 当前这轮锁定的自动解锁截止时刻,未锁定为 nil。供 owner 转发
    /// 给 UI 做逐秒倒计时;与 autoUnlockTimer 同源,读值即真相。
    private(set) var autoUnlockDeadline: Date?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var autoUnlockTimer: DispatchSourceTimer?

    /// 安装拦截 tap。重复调用幂等。
    /// - Returns: 是否成功(未授权时 tapCreate 失败返回 false)。
    func start() -> Bool {
        guard eventTap == nil else { return true }
        // systemDefined 通道覆盖默认功能键模式下的 F1-F12,见
        // SystemDefinedEventType。
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | SystemDefinedEventType.maskBit
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
        autoUnlockDeadline = Date().addingTimeInterval(Self.autoUnlockInterval)
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
        autoUnlockDeadline = nil
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

    /// 回调对拦截到的所有键盘事件恒返回 nil 吞掉;tap 被系统因超时/用户输入
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
