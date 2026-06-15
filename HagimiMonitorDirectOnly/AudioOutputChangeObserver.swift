import CoreAudio
import Foundation

/// 监听系统默认音频输出设备的变化。
///
/// `MediaKeyController` 是否接管音量键取决于 `AudioOutputDetector
/// .defaultOutputDeviceIsControllable()` 的判定结果,但该判定只在启动、
/// 设置变化、显示器刷新时执行。当用户把输出从外接显示器喇叭切回内建
/// 扬声器(或反之)时,若不重新评估,会出现"音量键仍调外接屏而非系统当前
/// 输出"的问题。本观察者补上这一事件源:监听 CoreAudio 的
/// `kAudioHardwarePropertyDefaultOutputDevice` 属性,变化时触发回调,
/// 调用方据此重新执行 `mediaKeyController.refresh()`。
///
/// 对齐 MonitorControl `AppDelegate.subscribeEventListeners` 中订阅
/// `defaultOutputDeviceChanged` 通知(由 SimplyCoreAudio 发出)的做法,
/// 但本项目用纯 CoreAudio C API,不引入第三方依赖。
@MainActor
final class AudioOutputChangeObserver {
    private var callback: (() -> Void)?
    private var debounceTimer: DispatchSourceTimer?
    // `registered` 仅作"是否已注册 listener"的幂等性标志。读写本就只在
    // @MainActor 方法里发生,但 deinit 在非隔离上下文执行,为避免 Swift 6
    // 严格并发告警,标记为 nonisolated(unsafe);重复
    // AudioObjectRemovePropertyListener 是安全的。
    private nonisolated(unsafe) var registered = false

    func start(onChange: @escaping () -> Void) {
        callback = onChange
        if !registered {
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
                registered = true
            }
        }
    }

    func stop() {
        if registered {
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
            registered = false
        }
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    deinit {
        // deinit 为非隔离上下文。listener 注销不依赖 actor 状态,且重复注销安全。
        if registered {
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
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(1000))
        timer.setEventHandler { [weak self] in
            self?.callback?()
        }
        debounceTimer = timer
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
