import Combine
import CoreAudio
import Foundation
import IOBluetooth
import OSLog

extension BluetoothDeviceType {
    /// 耳机、耳麦与音箱支持作为系统音频输出目标。
    nonisolated var supportsAudioOutput: Bool {
        switch self {
        case .headphones, .headset, .speaker:
            return true
        default:
            return false
        }
    }
}

/// CoreAudio 侧单个可用输出端点的轻量快照（纯值类型，便于离线的身份匹配单测）。
nonisolated struct BluetoothAudioOutputEndpoint: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32

    /// 从 CoreAudio 设备 UID（如 `"7C-C9-5E-67-E5-3F:output"`）提取归一化 12 位小写 MAC。
    var normalizedMAC: String? {
        let prefix = uid.split(separator: ":", maxSplits: 1).first.map(String.init) ?? uid
        if let mac = BluetoothDeviceIdentity.mac(prefix) {
            return mac
        }
        return BluetoothDeviceIdentity.mac(uid)
    }

    var isBluetoothTransport: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}

/// 蓝牙音频输出状态探测与一键切换控制器。
///
/// 通过公开 CoreAudio 属性监听（`kAudioHardwarePropertyDefaultOutputDevice` 与
/// `kAudioHardwarePropertyDevices`）事件驱动更新，不建立后台轮询定时器；
/// 沙盒与直连双渠道共用同一套实现。
@MainActor
final class BluetoothAudioOutputController: ObservableObject {
    static let shared = BluetoothAudioOutputController()

    @Published private(set) var endpoints: [BluetoothAudioOutputEndpoint] = []
    @Published private(set) var defaultOutputDeviceID: AudioDeviceID?

    private var listenerRegistration: ListenerRegistration?
    /// 用户点击尚未建立 CoreAudio 输出流（如仅广播电量的待机耳机）时，建连成功后自动补切为输出。
    private var pendingSwitchDevice: BluetoothDeviceInfo?

    init(installSystemListeners: Bool = true) {
        if installSystemListeners {
            refreshFromSystem()
            listenerRegistration = ListenerRegistration { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshFromSystem()
                }
            }
        }
    }

    /// 仅供单测或预览注入确定性的端点快照。
    init(endpoints: [BluetoothAudioOutputEndpoint], defaultOutputDeviceID: AudioDeviceID?) {
        self.endpoints = endpoints
        self.defaultOutputDeviceID = defaultOutputDeviceID
    }

    /// 判断给定蓝牙设备是否为当前系统默认音频输出。
    func isDefaultOutput(_ device: BluetoothDeviceInfo) -> Bool {
        guard device.type.supportsAudioOutput,
              let defaultID = defaultOutputDeviceID,
              let matched = Self.matchEndpoint(for: device, in: endpoints) else {
            return false
        }
        return matched.id == defaultID
    }

    /// 将给定蓝牙音频设备切换为系统默认音频输出。
    /// 若该设备已在 CoreAudio 注册输出流，直接切换；若仅处于蓝牙连接/广播但音频流未就绪，
    /// 则在后台发起 `IOBluetoothDevice.openConnection()` 并在音频端点出现后自动切过去。
    func selectOutput(for device: BluetoothDeviceInfo) {
        guard device.type.supportsAudioOutput else { return }
        if let endpoint = Self.matchEndpoint(for: device, in: endpoints) {
            pendingSwitchDevice = nil
            guard endpoint.id != defaultOutputDeviceID else { return }
            if Self.setSystemDefaultOutputDevice(endpoint.id) {
                defaultOutputDeviceID = endpoint.id
            }
            refreshFromSystem()
            return
        }

        // CoreAudio 尚未出现对应输出流：尝试唤醒已配对经典蓝牙音频链路，待设备列表回调后补切。
        pendingSwitchDevice = device
        Self.connectPairedBluetoothAudioDeviceIfNeeded(device)
    }

    /// 纯函数匹配：优先按归一化 MAC 精确匹配 CoreAudio UID，其次按归一化名称匹配蓝牙输出端点。
    nonisolated static func matchEndpoint(
        for device: BluetoothDeviceInfo,
        in endpoints: [BluetoothAudioOutputEndpoint]
    ) -> BluetoothAudioOutputEndpoint? {
        guard device.type.supportsAudioOutput, !endpoints.isEmpty else { return nil }

        // 1. MAC 精确匹配（跨设备改名仍稳定）
        if let deviceMAC = BluetoothDeviceIdentity.mac(device.address) {
            if let exactMAC = endpoints.first(where: { $0.normalizedMAC == deviceMAC }) {
                return exactMAC
            }
        }

        // 2. 归一化名称匹配（优先蓝牙传输端点，兼容沙盒内 ble-UUID 设备）
        let targetName = BluetoothDeviceIdentity.normalizedName(device.name)
        guard !targetName.isEmpty else { return nil }

        if let btExact = endpoints.first(where: {
            $0.isBluetoothTransport && BluetoothDeviceIdentity.normalizedName($0.name) == targetName
        }) {
            return btExact
        }

        if let anyExact = endpoints.first(where: {
            BluetoothDeviceIdentity.normalizedName($0.name) == targetName
        }) {
            return anyExact
        }

        // 3. 通用 AirPods 名称与唯一蓝牙 AirPods 端点兜底匹配
        if BluetoothDeviceInfo.isGenericAirPodsName(device.name) {
            let airPodsEndpoints = endpoints.filter {
                $0.isBluetoothTransport && $0.name.localizedCaseInsensitiveContains("airpods")
            }
            if airPodsEndpoints.count == 1 {
                return airPodsEndpoints[0]
            }
        }

        return nil
    }

    // MARK: - CoreAudio 读取与监听

    nonisolated private static var defaultOutputPropertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static var devicesPropertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private final class ListenerRegistration: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.bt-audio-output", qos: .userInitiated)
        private let defaultBlock: AudioObjectPropertyListenerBlock
        private let listBlock: AudioObjectPropertyListenerBlock

        init(onChange: @escaping @Sendable () -> Void) {
            let systemObject = AudioObjectID(kAudioObjectSystemObject)
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            self.defaultBlock = block
            self.listBlock = block

            var defaultAddress = BluetoothAudioOutputController.defaultOutputPropertyAddress
            AudioObjectAddPropertyListenerBlock(systemObject, &defaultAddress, queue, defaultBlock)

            var listAddress = BluetoothAudioOutputController.devicesPropertyAddress
            AudioObjectAddPropertyListenerBlock(systemObject, &listAddress, queue, listBlock)
        }

        deinit {
            let systemObject = AudioObjectID(kAudioObjectSystemObject)
            var defaultAddress = BluetoothAudioOutputController.defaultOutputPropertyAddress
            AudioObjectRemovePropertyListenerBlock(systemObject, &defaultAddress, queue, defaultBlock)

            var listAddress = BluetoothAudioOutputController.devicesPropertyAddress
            AudioObjectRemovePropertyListenerBlock(systemObject, &listAddress, queue, listBlock)
        }
    }

    func refreshFromSystem() {
        let snapshot = Self.readSystemSnapshot()
        if endpoints != snapshot.endpoints {
            endpoints = snapshot.endpoints
        }
        if defaultOutputDeviceID != snapshot.defaultOutputID {
            defaultOutputDeviceID = snapshot.defaultOutputID
        }
        if let pending = pendingSwitchDevice,
           let matched = Self.matchEndpoint(for: pending, in: snapshot.endpoints) {
            pendingSwitchDevice = nil
            if matched.id != snapshot.defaultOutputID, Self.setSystemDefaultOutputDevice(matched.id) {
                defaultOutputDeviceID = matched.id
            }
        }
    }

    nonisolated private static func readSystemSnapshot() -> (
        endpoints: [BluetoothAudioOutputEndpoint],
        defaultOutputID: AudioDeviceID?
    ) {
        let defaultID = readDefaultOutputDeviceID()
        let deviceIDs = readAllAudioDeviceIDs()
        let endpoints = deviceIDs.compactMap { id -> BluetoothAudioOutputEndpoint? in
            guard hasOutputStreams(id) else { return nil }
            let uid = readStringProperty(kAudioDevicePropertyDeviceUID, deviceID: id) ?? ""
            let name = readStringProperty(kAudioObjectPropertyName, deviceID: id) ?? ""
            guard !name.isEmpty else { return nil }
            let transport = readUInt32Property(kAudioDevicePropertyTransportType, deviceID: id) ?? 0
            return BluetoothAudioOutputEndpoint(id: id, uid: uid, name: name, transportType: transport)
        }
        return (endpoints, defaultID)
    }

    nonisolated private static func readDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var address = defaultOutputPropertyAddress
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
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    nonisolated private static func setSystemDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var targetID = deviceID
        var address = defaultOutputPropertyAddress
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &targetID) { ptr in
            AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                size,
                ptr
            )
        }
        if status != noErr {
            AppLogger.ui.warning("Failed to switch default audio output to \(deviceID, privacy: .public): \(status, privacy: .public)")
            return false
        }
        return true
    }

    nonisolated private static func readAllAudioDeviceIDs() -> [AudioDeviceID] {
        var address = devicesPropertyAddress
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, base)
        }
        guard status == noErr else { return [] }
        return ids
    }

    nonisolated private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }
        return dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    nonisolated private static func readStringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    nonisolated private static func readUInt32Property(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return value
    }

    nonisolated private static func connectPairedBluetoothAudioDeviceIfNeeded(_ device: BluetoothDeviceInfo) {
        let targetMAC = BluetoothDeviceIdentity.mac(device.address)
        let targetName = BluetoothDeviceIdentity.normalizedName(device.name)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let matched = paired.first { candidate in
                if let targetMAC,
                   let candidateAddress = candidate.addressString,
                   BluetoothDeviceIdentity.mac(candidateAddress) == targetMAC {
                    return true
                }
                if let candidateName = candidate.nameOrAddress,
                   !targetName.isEmpty,
                   BluetoothDeviceIdentity.normalizedName(candidateName) == targetName {
                    return true
                }
                return false
            }
            if let matched {
                _ = matched.openConnection()
            }
        }
    }
}
