import CoreAudio
import Foundation

/// 默认音频输出切换后重新选择音量键目标，避免继续控制上一个设备。
@MainActor
final class AudioOutputChangeObserver {
    private var callback: (@Sendable () -> Void)?
    private let cleanupBox = AudioOutputObserverCleanupBox()

    func start(onChange: @escaping @Sendable () -> Void) {
        callback = onChange
        if !cleanupBox.registered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.listenerProc,
                Unmanaged.passUnretained(self).toOpaque()
            )
            if status == noErr {
                cleanupBox.registered = true
            }
        }
    }

    func stop() {
        if cleanupBox.registered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.listenerProc,
                Unmanaged.passUnretained(self).toOpaque()
            )
            cleanupBox.registered = false
        }
        cleanupBox.cancelTimer()
    }

    deinit {
        cleanupBox.cancelTimer()
        // deinit 为非隔离上下文。listener 注销不依赖 actor 状态,且重复注销安全。
        if cleanupBox.registered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.listenerProc,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    fileprivate func handleDefaultOutputChanged() {
        // 设备切换瞬间 CoreAudio 可能连续多次回调,防抖 1000ms 取最后一次。
        cleanupBox.cancelTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(1000))
        timer.setEventHandler { [weak self] in
            self?.callback?()
        }
        cleanupBox.debounceTimer = timer
        timer.resume()
    }

    // C 函数指针不依赖 actor 隔离;标 nonisolated 以便 deinit(nonisolated 上下文)
    // 安全引用来注销回调。
    private nonisolated static let listenerProc: AudioObjectPropertyListenerProc = { _, _, _, userInfo in
        guard let userInfo else { return noErr }
        let observer = Unmanaged<AudioOutputChangeObserver>.fromOpaque(userInfo).takeUnretainedValue()
        DispatchQueue.main.async {
            observer.handleDefaultOutputChanged()
        }
        return noErr
    }
}

/// 线程安全清理容器：管理 CoreAudio 属性监听注册状态与防抖定时器。
private nonisolated final class AudioOutputObserverCleanupBox: @unchecked Sendable {
    var registered = false
    var debounceTimer: DispatchSourceTimer?

    nonisolated func cancelTimer() {
        debounceTimer?.cancel()
        debounceTimer = nil
    }
}
