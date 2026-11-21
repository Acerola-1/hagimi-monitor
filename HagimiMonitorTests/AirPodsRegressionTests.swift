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

    @Test func compactBatteryUsesSingleComponentWithoutGuessingPartsFromNameOrSource() {
        var device = io("AirPods")
        device.batterySource = .advertisement
        #expect(!device.hasSeparateBatteryParts)
        #expect(device.compactBatteryLevel == nil)
        device.components = [.init(kind: .single, level: 0, isCharging: true)]
        #expect(!device.hasSeparateBatteryParts)
        #expect(device.compactBatteryLevel == 0)
        #expect(device.compactChargingState == true)
    }

    @Test func separateBatteryLayoutSurvivesMissingReadingsOnlyForThePresentDevice() {
        var leftOnly = io()
        leftOnly.components = [.init(kind: .left, level: 30)]
        #expect(leftOnly.hasSeparateBatteryParts)
        let fresh = [io(), io(address: "another-device")]
        let next = BluetoothBatterySampler.continuingBatteryReports(fresh, after: [leftOnly])
        #expect(next.map(\.hasSeparateBatteryParts) == [true, false])
        #expect(next[0].components.isEmpty)
        #expect(next[0].compactBatteryLevel == nil)
        let later = BluetoothBatterySampler.continuingBatteryReports(fresh, after: next)
        #expect(later[0].hasSeparateBatteryParts)
        let disconnected = BluetoothBatterySampler.continuingBatteryReports([], after: later)
        let reconnected = BluetoothBatterySampler.continuingBatteryReports(fresh, after: disconnected)
        #expect(!reconnected[0].hasSeparateBatteryParts)
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

    // 人工身份样本覆盖跨来源重复，不代表用户截图中已经确认的原始记录。
    @Test func renamedPowerSourceAndBLEUseOneSystemIdentity() throws {
        let power = try pmset()
        let snapshot = BLEDeviceSnapshot(identifier: uuid, name: "AirPods 4 (ANC)", batteryLevel: nil)
        let result = BluetoothBatterySampler.merge(
            ioDevices: [io("AirPods 4 (ANC)")], pmsetDevices: power,
            profilerDevices: [], bleSnapshots: [snapshot], bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.address == address)
        #expect(result.devices.first?.name == "AirPods 4 (ANC)")
        #expect(result.devices.first?.components.map(\.level) == [99, 100, 68])
        #expect(result.learnedBindings[address] == uuid.uuidString)
    }

    @Test func powerSourceAndBLEWithoutClassicConnectionDoNotDuplicateUUID() throws {
        let result = BluetoothBatterySampler.merge(
            ioDevices: [], pmsetDevices: try pmset(), profilerDevices: [],
            bleSnapshots: [BLEDeviceSnapshot(identifier: uuid, name: "Renamed Headphones", batteryLevel: 80)], bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == 80)
        #expect(result.devices.first?.components.map(\.level) == [99, 100, 68])
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func repeatedPowerRecordsUseIdentityLearnedInSameMerge() throws {
        let power = try #require(try pmset().first)
        let renamed = BluetoothDeviceInfo(address: power.address, name: "Renamed Headphones", type: power.type,
                                      batteryLevel: power.batteryLevel, components: power.components,
                                      accessoryIdentifier: power.accessoryIdentifier)
        for records in [[power, renamed], [renamed, power]] {
            let result = BluetoothBatterySampler.merge(
                ioDevices: [io("Test AirPods #2")], pmsetDevices: records,
                profilerDevices: [], bleSnapshots: [], bindings: [:]
            )
            #expect(result.devices.count == 1)
            #expect(result.devices.first?.address == address)
        }
    }

    @Test func groupedPowerSourceKeepsClassicMACDespiteDifferentNames() throws {
        let entries: [[String: Any]] = [
            ["Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Group Identifier": uuid.uuidString,
             "Name": "Test AirPods #2", "Part Identifier": "Combined", "Current Capacity": 77],
            ["Accessory Identifier": "11:22:33:44:55:66", "Group Identifier": uuid.uuidString,
             "Name": "Case", "Part Identifier": "Case", "Current Capacity": 96]
        ]
        let raw = try entries.reduce(into: Data()) { result, entry in
            result.append(try PropertyListSerialization.data(fromPropertyList: entry, format: .xml, options: 0))
        }
        let power = PMSetAccessoryParser.parse(xmlData: raw)
        #expect(power.first?.address == address)
        #expect(power.first?.accessoryIdentifier == uuid)
        let result = BluetoothBatterySampler.merge(
            ioDevices: [io("AirPods 4 (ANC)")], pmsetDevices: power,
            profilerDevices: [io("AirPods 4 (ANC)")],
            bleSnapshots: [BLEDeviceSnapshot(identifier: uuid, name: "Renamed Headphones", batteryLevel: nil)], bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.name == "AirPods 4 (ANC)")
        #expect(result.devices.first?.components.first { $0.kind == .case }?.level == 96)
    }

    @Test func powerUUIDCannotOverrideAnotherHeadphonesBindingByName() throws {
        let otherUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let result = BluetoothBatterySampler.merge(
            ioDevices: [io("Test AirPods #2")], pmsetDevices: try pmset(), profilerDevices: [],
            bleSnapshots: [BLEDeviceSnapshot(identifier: uuid, name: "Test AirPods #2", batteryLevel: nil)],
            bindings: [address: otherUUID.uuidString]
        )
        #expect(result.devices.count == 2)
        #expect(result.devices.first { $0.address == address }?.batteryLevel == nil)
        #expect(result.devices.first { $0.accessoryIdentifier == uuid }?.components.count == 3)
        #expect(result.learnedBindings[address] == nil)
    }

    @Test func sameNameHeadphonesRemainSeparateWhenPowerUUIDIsAmbiguous() throws {
        let secondAddress = "112233445566"
        let result = BluetoothBatterySampler.merge(
            ioDevices: [io("Test AirPods #2"), io("Test AirPods #2", address: secondAddress)],
            pmsetDevices: try pmset(), profilerDevices: [],
            bleSnapshots: [BLEDeviceSnapshot(identifier: uuid, name: "Test AirPods #2", batteryLevel: nil)], bindings: [:]
        )
        #expect(result.devices.count == 3)
        #expect(result.devices.filter { $0.address == address || $0.address == secondAddress }.allSatisfy { $0.batteryLevel == nil })
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func differentKnownUUIDsRemainSeparateDespiteSameName() throws {
        let otherUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let result = BluetoothBatterySampler.merge(
            ioDevices: [], pmsetDevices: try pmset(), profilerDevices: [],
            bleSnapshots: [BLEDeviceSnapshot(identifier: otherUUID, name: "Test AirPods #2", batteryLevel: 12)], bindings: [:]
        )
        #expect(result.devices.count == 2)
        #expect(result.devices.first { $0.accessoryIdentifier == uuid }?.batteryLevel == 99)
        #expect(result.devices.first { $0.address == "ble-" + otherUUID.uuidString }?.batteryLevel == 12)
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func issue147CaseAndTwoBLEEndpointsBelongToOneHeadset() throws {
        let earbud = UUID()
        let chargingCase = UUID()
        let nickname = "林舍的 AirPods"
        let xml = try PropertyListSerialization.data(fromPropertyList: [
            "Accessory Identifier": chargingCase.uuidString, "Group Identifier": uuid.uuidString,
            "Part Identifier": "Case", "Accessory Category": "Audio Battery Case",
            "Name": nickname, "Current Capacity": 57
        ], format: .xml, options: 0)
        let power = PMSetAccessoryParser.parse(xmlData: xml)
        var system = io("AirPods 4 (ANC)")
        system.components = [.init(kind: .left, level: 94), .init(kind: .right, level: 91), .init(kind: .case, level: 56)]
        let snapshots = [earbud, chargingCase].map { BLEDeviceSnapshot(identifier: $0, name: nickname, batteryLevel: nil) }
        for order in [snapshots, Array(snapshots.reversed())] {
            let result = BluetoothBatterySampler.merge(ioDevices: [io("AirPods 4 (ANC)")], pmsetDevices: power,
                profilerDevices: [system], bleSnapshots: order, bindings: [:],
                cachedAddresses: [earbud: address, chargingCase: address])
            #expect(result.devices.count == 1)
            let device = try #require(result.devices.first)
            #expect(device.address == address)
            #expect(device.name == nickname)
            #expect(device.components == [.init(kind: .left, level: 94), .init(kind: .right, level: 91), .init(kind: .case, level: 57)])
            #expect(result.learnedBindings.isEmpty)
        }
    }

    @Test func powerGroupIdentifiesMemberPeripheralsWithoutSystemCache() throws {
        let bud = UUID()
        let chargingCase = UUID()
        let entries: [[String: Any]] = [
            ["Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Combined", "Current Capacity": 62],
            ["Accessory Identifier": bud.uuidString, "Part Identifier": "Left", "Current Capacity": 62],
            ["Accessory Identifier": chargingCase.uuidString, "Part Identifier": "Case", "Current Capacity": 19]
        ]
        let xml = try entries.reduce(into: Data()) { data, entry in
            var fields = entry
            fields["Group Identifier"] = uuid.uuidString
            fields["Name"] = "Studio headphones"
            data.append(try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0))
        }
        let power = PMSetAccessoryParser.parse(xmlData: xml)
        #expect(power.first?.memberIdentifiers == Set([bud, chargingCase]))
        let result = BluetoothBatterySampler.merge(ioDevices: [io()], pmsetDevices: power, profilerDevices: [],
            bleSnapshots: [
                .init(identifier: bud, name: "Studio headphones", batteryLevel: nil),
                .init(identifier: chargingCase, name: "Studio headphones", batteryLevel: 19)
            ], bindings: [:])
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.name == "Studio headphones")
        #expect(result.devices.first?.batteryLevel == 62)
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func sameNamePairsAndUnrelatedBLEDeviceRetainSeparateIdentities() {
        let second = "112233445566"
        let other = UUID()
        let unrelated = UUID()
        let name = "AirPods"
        let snapshots = [
            BLEDeviceSnapshot(identifier: uuid, name: name, batteryLevel: 88),
            BLEDeviceSnapshot(identifier: other, name: name, batteryLevel: 23),
            BLEDeviceSnapshot(identifier: unrelated, name: name, batteryLevel: nil)
        ]
        // 过期的历史绑定指向另一副耳机，以当前系统映射为准。
        let result = BluetoothBatterySampler.merge(ioDevices: [io(name), io(name, address: second)],
            profilerDevices: [], bleSnapshots: snapshots, bindings: [address: other.uuidString],
            cachedAddresses: [uuid: address, other: second])
        #expect(result.devices.count == 3)
        #expect(result.devices.first { $0.address == address }?.batteryLevel == 88)
        #expect(result.devices.first { $0.address == second }?.batteryLevel == 23)
        #expect(result.devices.contains { $0.address == "ble-\(unrelated.uuidString)" })
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func cacheOnlyAcceptsUnambiguousUUIDAndAddressPairs() {
        let alias = UUID()
        let broken = UUID()
        let conflicted = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let entries: [String: Any] = [
            uuid.uuidString: ["DeviceAddress": "AA:BB:CC:DD:EE:FF"],
            alias.uuidString: ["DeviceAddress": "aa-bb-cc-dd-ee-ff"],
            broken.uuidString: ["DeviceAddress": "bad address"],
            "invalid": ["DeviceAddress": "aa-bb-cc-dd-ee-ff"],
            conflicted.uuidString: ["DeviceAddress": "aa-bb-cc-dd-ee-ff"],
            conflicted.uuidString.lowercased(): ["DeviceAddress": "11:22:33:44:55:66"]
        ]
        #expect(BluetoothBatterySampler.parseCacheAddresses(entries) == [uuid: address, alias: address])
        #expect(BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [],
            bindings: [:], cachedAddresses: [uuid: address]).devices.isEmpty)
    }
}
