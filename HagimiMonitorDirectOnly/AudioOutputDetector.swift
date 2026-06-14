import CoreAudio
import Foundation
import OSLog

private let audioDetectorLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "AudioOutput")

/// 探测默认音频输出设备是否自身可控。
///
/// macOS 上 F11/F12 音量键默认调节"系统当前选中的输出设备"。当该设备是
/// AirPods、蓝牙音箱、USB 声卡等自带音量控制的设备时,系统会自行处理音量键;
/// 此时 App 若也接管音量键,会让 AirPods 等设备的音量键失效。
///
/// 因此对齐 MonitorControl 的策略(`MediaKeyTapManager.updateMediaKeyTap` 中
/// `canSetVirtualMainVolume(scope: .output)` 判断):仅在默认输出设备自身
/// **不可控**时才接管音量键。典型场景是音频走外接显示器喇叭,系统认为不可控。
///
/// 设备切换(插拔 AirPods 等)的自动重评估不在本类型内处理;调用方在设置变化、
/// 显示器刷新、权限变化等事件里重新调用即可覆盖多数场景。
enum AudioOutputDetector {
    /// 返回当前默认输出设备是否可以被系统直接调节音量。
    /// - true  → 设备可控(如 AirPods),音量键应交给系统
    /// - false → 设备不可控(如外接显示器音频),音量键可被 App 接管
    static func defaultOutputDeviceIsControllable() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else {
            audioDetectorLog.notice("No default output device; treating as not controllable")
            return false
        }

        // 设备存在可写的 VolumeScalar 属性(element 0 = master/main channel)
        // → 系统可直接调音量,不需要 App 接管。
        var volumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &volumeProperty) else {
            return false
        }
        var isSettable: DarwinBoolean = false
        var size = UInt32(MemoryLayout<DarwinBoolean>.size)
        let status = withUnsafeMutablePointer(to: &isSettable) { ptr in
            AudioObjectGetPropertyData(deviceID, &volumeProperty, 0, nil, &size, ptr)
        }
        return status == noErr && isSettable.boolValue
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &deviceID) { ptr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                ptr
            )
        }
        guard status == noErr else {
            audioDetectorLog.warning("Failed to read default output device: \(status, privacy: .public)")
            return nil
        }
        return deviceID
    }
}
