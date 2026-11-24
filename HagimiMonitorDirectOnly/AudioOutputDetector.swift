import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private let audioDetectorLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "AudioOutput")

/// 仅探测默认音频输出的名称与系统可控性：系统可调的设备交还 macOS，不可控设备再尝试匹配外接屏 DDC。
enum AudioOutputDetector {
    static func defaultOutputDescription() -> AudioOutputDescription? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return AudioOutputDescription(
            deviceUID: stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID) ?? "",
            name: stringProperty(kAudioObjectPropertyName, deviceID: deviceID) ?? "",
            transportType: nil,
            isControllable: volumeSelector(deviceID) != nil
        )
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func volumeSelector(_ deviceID: AudioDeviceID) -> AudioObjectPropertySelector? {
        [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar].first {
            isPropertySettable(deviceID: deviceID, selector: $0, scope: kAudioDevicePropertyScopeOutput)
        }
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
