import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DisplayChangeObserver {
    private var callback: (() -> Void)?
    private var debounceTimer: DispatchSourceTimer?
    // `registered` 仅作"是否已注册 CG 回调"的幂等性标志。读写本就只在 @MainActor
    // 方法里发生,但 deinit 在非隔离上下文执行,为避免 Swift 6 严格并发告警,
    // 标记为 nonisolated(unsafe);重复 CGDisplayRemoveReconfigurationCallback 是安全的。
    private nonisolated(unsafe) var registered = false
    // nonisolated(unsafe): 同 registered,deinit 中安全注销。
    private nonisolated(unsafe) var workspaceRegistered = false

    func start(onChange: @escaping () -> Void) {
        callback = onChange
        if !registered {
            CGDisplayRegisterReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = true
        }
        if !workspaceRegistered {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(systemDidWake(_:)),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
            workspaceRegistered = true
        }
    }

    func stop() {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
        if workspaceRegistered {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            workspaceRegistered = false
        }
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    deinit {
        // deinit 为非隔离上下文。CG 回调注销与 NSWorkspace removeObserver 均不依赖
        // actor 状态,且重复注销安全;缺失则对象释放后通知可能向已 dealloc 对象发消息。
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.cgCallback, Unmanaged.passUnretained(self).toOpaque())
        }
        if workspaceRegistered {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
        }
    }

    @objc private func systemDidWake(_ note: Notification) {
        scheduleCallback(after: .milliseconds(800))
    }

    fileprivate func handleReconfigure() {
        scheduleCallback(after: .milliseconds(1000))
    }

    private func scheduleCallback(after delay: DispatchTimeInterval) {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.callback?()
        }
        debounceTimer = timer
        timer.resume()
    }

    // C 函数指针不依赖 actor 隔离;标 nonisolated 以便 deinit(nonisolated 上下文)
    // 安全引用来注销回调。
    private nonisolated static let cgCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        if flags.contains(.addFlag) ||
           flags.contains(.removeFlag) {
            let observer = Unmanaged<DisplayChangeObserver>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                observer.handleReconfigure()
            }
        }
    }
}
