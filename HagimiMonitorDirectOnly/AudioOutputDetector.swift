import AudioToolbox
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
    /// - true  → 设备可控(如 AirPods、内建扬声器),音量键应交给系统
    /// - false → 设备不可控(如外接显示器音频),音量键可被 App 接管
    ///
    /// 检测顺序对齐 SimplyCoreAudio `canSetVirtualMainVolume`:
    /// 1. `kAudioDevicePropertyVolumeScalar`(main element)settable
    /// 2. `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` settable
    ///    ← MacBook 内建扬声器只满足这一项;漏掉它会导致音量键被错误接管。
    static func defaultOutputDeviceIsControllable() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else {
            audioDetectorLog.notice("No default output device; treating as not controllable")
            return false
        }

        if isPropertySettable(
            deviceID: deviceID,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioDevicePropertyScopeOutput
        ) {
            return true
        }

        // Fallback: virtual main volume(MacBook 内建扬声器的实际可写属性)。
        if isPropertySettable(
            deviceID: deviceID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput
        ) {
            return true
        }

        return false
    }

    private static func isPropertySettable(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }
        var isSettable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
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
