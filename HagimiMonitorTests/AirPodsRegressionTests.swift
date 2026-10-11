import AppKit
import Foundation
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct AirPodsRegressionTests {
    private let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let address = "aabbccddeeff"

    private func data(_ hex: String) -> Data {
        Data(stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
    }

    // 来自两渠道真实采集；身份及电量之外的尾部字节已匿名化。
    private let directFrame = "4c000719010f2075a9b611000414e3e444000000000000000000000000"
    private let sandboxFrame = "4c000719010f2054a9b611000010e1e443000000000000000000000000"
    private func advertisement(_ frame: String, at: TimeInterval = 1000, id: UUID? = nil, name: String = "Test AirPods #2") throws -> AirPodsAdvertisement {
        try #require(AirPodsAdvertisement.decode(data(frame), identifier: id ?? uuid, name: name, observedAt: at, isDecrypted: true))
    }
    private func io(_ name: String = "AirPods", address: String? = nil) -> BluetoothDeviceInfo {
        BluetoothDeviceInfo(address: address ?? self.address, name: name, type: .headphones, batteryLevel: nil)
    }
    private func profiler() throws -> [BluetoothDeviceInfo] {
        let raw: [String: Any] = ["SPBluetoothDataType": [["device_connected": [["Test AirPods #2": [
            "device_address": "AA:BB:CC:DD:EE:FF", "device_minorType": "Headphones",
            "device_batteryLevelLeft": "99%", "device_batteryLevelRight": "100%", "device_batteryLevelCase": "68%"
        ]]]]]]
        let data = try JSONSerialization.data(withJSONObject: raw)
        guard case .success(_, let devices) = BluetoothBatterySampler.parse(profilerJSON: data) else { throw CocoaError(.coderReadCorrupt) }
        return devices
    }
    private func pmset() throws -> [BluetoothDeviceInfo] {
        let entries: [[String: Any]] = [
            ["Accessory Identifier": uuid.uuidString, "Group Identifier": uuid.uuidString, "Name": "Test AirPods #2", "Part Identifier": "Combined", "Accessory Category": "Audio", "Current Capacity": 99,
             "Combined Parts": [["Part Identifier": "Left", "Current Capacity": 99, "Is Charging": true], ["Part Identifier": "Right", "Current Capacity": 100, "Is Charging": true]]],
            ["Accessory Identifier": uuid.uuidString, "Group Identifier": uuid.uuidString, "Name": "Test AirPods #2", "Part Identifier": "Case", "Accessory Category": "Audio Battery Case", "Current Capacity": 68, "Is Charging": false]
        ]
        let raw = try entries.reduce(into: Data()) { result, entry in
            result.append(try PropertyListSerialization.data(fromPropertyList: entry, format: .xml, options: 0))
        }
        return PMSetAccessoryParser.parse(xmlData: raw)
    }

    @Test func directSourcesMergeRenamedAirPodsIntoOneIdentity() throws {
        let power = try pmset()
        #expect(power.first?.accessoryIdentifier == uuid)
        #expect(power.first?.address == "ble-" + uuid.uuidString)
        let result = BluetoothBatterySampler.merge(ioDevices: [io()], pmsetDevices: power, profilerDevices: try profiler(), bleSnapshots: [], bindings: [:], airPodsAdvertisements: [try advertisement(directFrame)], now: 1000)
        let device = try #require(result.devices.first)
        #expect(result.devices.count == 1)
        #expect(device.address == address)
        #expect(device.name == "AirPods")
        #expect(device.batteryLevel == 99)
        #expect(device.components.map(\.level) == [99, 100, 68])
        #expect(device.components.map(\.isCharging) == [true, true, false])
        #expect(result.learnedBindings[address] == uuid.uuidString)
    }

    @Test func sandboxUsesPublicBroadcastWithoutProfilerOrPowerSource() throws {
        let result = BluetoothBatterySampler.merge(ioDevices: [io()], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [try advertisement(sandboxFrame)], nameAliases: [address: ["Test AirPods #2"]], now: 1000)
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == 97)
        #expect(result.devices.first?.batterySource == .advertisement)
        #expect(result.devices.first?.components.map(\.level) == [100, 97, 67])
        #expect(result.devices.first?.components.map(\.isCharging) == [true, true, false])
    }

    @Test func profilerAndPowerSourceExcludeCaseFromMainBattery() throws {
        #expect(try profiler().first?.batteryLevel == 99)
        #expect(try pmset().first?.batteryLevel == 99)
        let result = BluetoothBatterySampler.merge(ioDevices: [], pmsetDevices: try pmset(), profilerDevices: try profiler(), bleSnapshots: [], bindings: [:])
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == 99)
    }

    @Test func missingPartsReplaceOldReadingsAndZeroRemainsReal() throws {
        var raw = data(sandboxFrame)
        raw[14] = 0x00; raw[15] = 0xff; raw[16] = 0xff
        let snapshot = try #require(AirPodsAdvertisement.decode(raw, identifier: uuid, name: "AirPods", observedAt: 1000, isDecrypted: true))
        let result = BluetoothBatterySampler.merge(ioDevices: [io()], profilerDevices: try profiler(), bleSnapshots: [], bindings: [address: uuid.uuidString], airPodsAdvertisements: [snapshot], now: 1000)
        #expect(result.devices.first?.batteryLevel == 0)
        #expect(result.devices.first?.components == [BluetoothBatteryComponent(kind: .right, level: 0, isCharging: false)])
        raw[14] = 0xff
        let empty = try #require(AirPodsAdvertisement.decode(raw, identifier: uuid, name: "AirPods", observedAt: 1000, isDecrypted: true))
        let missing = BluetoothBatterySampler.merge(ioDevices: [io()], profilerDevices: try profiler(), bleSnapshots: [], bindings: [address: uuid.uuidString], airPodsAdvertisements: [empty], now: 1000)
        #expect(missing.devices.first?.batteryLevel == nil)
        #expect(missing.devices.first?.components.isEmpty == true)
    }

    @Test func nearbyAndExpiredBroadcastsCannotCreateOrPoisonDevices() throws {
        let frame = try advertisement(sandboxFrame)
        #expect(BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], now: 1000).devices.isEmpty)
        for now in [999.0, 1091.0] {
            let result = BluetoothBatterySampler.merge(ioDevices: [io("Test AirPods #2")], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], now: now)
            #expect(result.devices.first?.batteryLevel == nil)
        }
        let namesakes = BluetoothBatterySampler.merge(ioDevices: [io("Test AirPods #2"), io("Test AirPods #2", address: "112233445566")], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], now: 1000)
        #expect(namesakes.devices.allSatisfy { $0.batteryLevel == nil })
        #expect(namesakes.learnedBindings.isEmpty)
        let ambiguous = BluetoothBatterySampler.merge(ioDevices: [io("Test AirPods #2")], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame, try advertisement(sandboxFrame, id: UUID())], now: 1000)
        #expect(ambiguous.devices.first?.batteryLevel == nil)
    }

    @Test func rejectsMalformedUnknownAndSingleBodyPackets() {
        for count in [0, 25, 28, 30] {
            #expect(AirPodsAdvertisement.decode(Data(repeating: 0, count: count), identifier: uuid, name: nil, observedAt: 0, isDecrypted: true) == nil)
        }
        for model in [UInt8(0x0a), 0xff] {
            var raw = data(sandboxFrame); raw[5] = model
            #expect(AirPodsAdvertisement.decode(raw, identifier: uuid, name: nil, observedAt: 0, isDecrypted: true) == nil)
        }
        var raw = data(sandboxFrame); raw[3] = 0
        #expect(AirPodsAdvertisement.decode(raw, identifier: uuid, name: nil, observedAt: 0, isDecrypted: true) == nil)
    }

    @Test func newerFrameWinsRegardlessOfInputOrderAndBoundNameChanges() throws {
        let older = try advertisement(directFrame, at: 995)
        let newer = try advertisement(sandboxFrame)
        for frames in [[older, newer], [newer, older]] {
            let result = BluetoothBatterySampler.merge(ioDevices: [io("Custom Headphones")], profilerDevices: [], bleSnapshots: [], bindings: [address: uuid.uuidString], airPodsAdvertisements: frames, now: 1000)
            #expect(result.devices.first?.batteryLevel == 97)
        }
    }
    @Test func replayAllCapturedFramesThroughProductionDecoder() throws {
        struct Frame: Decodable { let raw: String; let levels: [Int?]; let charging: [Bool?] }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/AirPodsBroadcasts.json")
        let frames = try JSONDecoder().decode([Frame].self, from: Data(contentsOf: url))
        #expect(frames.count == 59)
        for frame in frames {
            let decoded = try advertisement(frame.raw)
            for (index, kind) in [BluetoothBatteryComponent.Kind.left, .right, .case].enumerated() {
                #expect(decoded.components.first { $0.kind == kind }?.level == frame.levels[index])
                #expect(decoded.components.first { $0.kind == kind }?.isCharging == frame.charging[index])
            }
        }
    }

    @Test func openCaseBeforeAudioConnectionOnlyShowsUniquelyPairedAirPods() throws {
        let frame = try advertisement(sandboxFrame)
        let paired = io("Test AirPods #2")
        let result = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], pairedDevices: [paired], now: 1000)
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.address == address)
        #expect(result.devices.first?.components.map(\.level) == [100, 97, 67])
        let ambiguous = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], pairedDevices: [paired, io("Test AirPods #2", address: "112233445566")], now: 1000)
        #expect(ambiguous.devices.isEmpty)
        let expired = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [], bindings: [:], airPodsAdvertisements: [frame], pairedDevices: [paired], now: 1091)
        #expect(expired.devices.isEmpty)
        #expect(AirPodsAdvertisement.decode(data(sandboxFrame), identifier: uuid, name: nil, observedAt: 0, isDecrypted: false) == nil)
    }

    @Test func oldBroadcastDoesNotOverwriteNewerPowerSourceParts() throws {
        let result = BluetoothBatterySampler.merge(ioDevices: [io()], pmsetDevices: try pmset(), profilerDevices: try profiler(), bleSnapshots: [], bindings: [:], airPodsAdvertisements: [try advertisement(sandboxFrame, at: 990)], powerSourceObservedAt: 999, now: 1000)
        #expect(result.devices.first?.batterySource == .powerSource)
        #expect(result.devices.first?.components.map(\.level) == [99, 100, 68])
    }

}
