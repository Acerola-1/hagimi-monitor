import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private let audioDetectorLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "AudioOutput")

/// 默认输出可直接调音量时走 Core Audio，其他设备由显示器路由匹配。
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

    struct VolumeOutput: Equatable {
        let id: AudioDeviceID
        let selector: AudioObjectPropertySelector

        private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                       mElement: kAudioObjectPropertyElementMain)
        }

        var level: Double? {
            var property = address(selector)
            var scalar: Float32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: scalar))
            guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &scalar) == noErr,
                  (0...1).contains(scalar) else { return nil }
            return Double(scalar) * 100
        }

        var muted: Bool? {
            var property = address(kAudioDevicePropertyMute)
            var flag: UInt32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: flag))
            guard AudioObjectHasProperty(id, &property),
                  AudioObjectGetPropertyData(id, &property, 0, nil, &size, &flag) == noErr else { return nil }
            return flag != 0
        }

        func setMuted(_ muted: Bool) -> Bool {
            var property = address(kAudioDevicePropertyMute)
            var flag: UInt32 = muted ? 1 : 0
            return AudioObjectSetPropertyData(id, &property, 0, nil, 4, &flag) == noErr
        }

        func setLevel(_ level: Double) -> Bool {
            var property = address(selector)
            var scalar = Float32(min(100, max(0, level)) / 100)
            guard AudioObjectSetPropertyData(id, &property, 0, nil, 4, &scalar) == noErr else { return false }
            return scalar == 0 || muted != true || setMuted(false)
        }
    }

    static func volumeOutput() -> VolumeOutput? {
        guard let id = defaultOutputDeviceID(), let selector = volumeSelector(id) else { return nil }
        return VolumeOutput(id: id, selector: selector)
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
