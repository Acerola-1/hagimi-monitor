import Foundation
import Testing
@testable import HagimiMonitorDirect

struct AirPodsIdentityTests {
    struct Scene {
        var io: [BluetoothDeviceInfo]
        var profiler: [BluetoothDeviceInfo]
        var ble: [BLEDeviceSnapshot]
        var bindings: [String: String]
        var paired: [BluetoothDeviceInfo]

        func merge(aliases: [String: Set<String>] = [:], power: [BluetoothDeviceInfo] = []) -> (devices: [BluetoothDeviceInfo], learnedBindings: [String: String]) {
            BluetoothBatterySampler.merge(ioDevices: io, pmsetDevices: power, profilerDevices: profiler, bleSnapshots: ble,
                bindings: bindings, nameAliases: aliases, pairedDevices: paired, now: 1000)
        }
    }

    static func scene() throws -> Scene {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AirPodsDuplicateDevices.json")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let records = try #require(root["ioDevices"] as? [[String: Any]])
        let io = try records.map { item in
            BluetoothDeviceInfo(address: try #require(item["address"] as? String),
                name: try #require(item["name"] as? String),
                type: BluetoothDeviceType(minorType: try #require(item["type"] as? String)),
                batteryLevel: item["battery"] as? Int)
        }
        let profilerData = try JSONSerialization.data(withJSONObject: try #require(root["profiler"]))
        guard case .success(_, let profiler) = BluetoothBatterySampler.parse(profilerJSON: profilerData) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let snapshots = try #require(root["bleSnapshots"] as? [[String: String]])
        let ble = try snapshots.map {
            BLEDeviceSnapshot(identifier: try #require($0["identifier"].flatMap(UUID.init(uuidString:))),
                              name: $0["name"], batteryLevel: nil)
        }
        let paired = try #require(root["pairedAddresses"] as? [String])
        return Scene(io: io, profiler: profiler, ble: ble,
                     bindings: try #require(root["bindings"] as? [String: String]),
                     paired: io.filter { paired.contains($0.address) })
    }

    @Test func capturedIdentityStructurePublishesThreeDevicesInsteadOfSix() throws {
        let scene = try Self.scene()
        #expect(scene.profiler.filter(\.isBLETransportOnly).count == 1)
        let result = scene.merge()
        #expect(result.devices.count == 3)
        let headphones = try #require(result.devices.first { $0.type == .headphones })
        #expect(headphones.address == "aabbcc000001")
        #expect(headphones.name == "Personal AirPods")
        #expect(headphones.batteryLevel == 64)
        #expect(headphones.components.map(\.level) == [100, 64, 78])
        #expect(result.learnedBindings.isEmpty, "多个当前 UUID 不应任选一个覆盖旧绑定")
    }

    @Test func aPowerGroupUUIDDistinctFromBothCurrentBLEUUIDsUsesTheSamePhysicalMAC() throws {
        let scene = try Self.scene()
        let group = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let parts: [BluetoothBatteryComponent] = [.init(kind: .left, level: 93, isCharging: false),
            .init(kind: .right, level: 0, isCharging: true), .init(kind: .case, level: 77, isCharging: false)]
        let power = BluetoothDeviceInfo(address: "ble-" + group.uuidString, name: "AirPods 4 (ANC)",
            type: .headphones, batteryLevel: 0, components: parts, isCharging: true,
            batterySource: .powerSource, accessoryIdentifier: group)
        let result = scene.merge(power: [power])
        #expect(result.devices.count == 3)
        let headphones = try #require(result.devices.first { $0.type == .headphones })
        #expect(headphones.address == "aabbcc000001")
        #expect(headphones.name == "Personal AirPods")
        #expect(headphones.components == parts)
        #expect(headphones.batteryLevel == 0)
        #expect(headphones.isCharging == true)
        #expect(result.learnedBindings.isEmpty, "分组 UUID 和多个 GATT UUID 不能任选一个写入旧表")
    }

    @Test func independentPowerGroupsWithTheSameNameRemainSeparate() throws {
        let scene = try Self.scene()
        let groups = [UUID(), UUID()]
        let power = groups.map {
            BluetoothDeviceInfo(address: "ble-" + $0.uuidString, name: "AirPods 4 (ANC)",
                type: .headphones, batteryLevel: 12, accessoryIdentifier: $0)
        }
        for records in [power, Array(power.reversed())] {
            let devices = scene.merge(power: records).devices
            #expect(groups.allSatisfy { id in devices.contains { $0.address == "ble-" + id.uuidString } })
            #expect(devices.first { $0.address == "aabbcc000001" }?.batteryLevel == 64)
        }
    }

    @Test func aLiveGATTUUIDDoesNotConflictWithTheSeparatePowerGroupUUID() throws {
        var scene = try Self.scene()
        scene.bindings["aabbcc000001"] = scene.ble[0].identifier.uuidString
        let group = UUID()
        let power = BluetoothDeviceInfo(address: "ble-" + group.uuidString, name: "AirPods 4 (ANC)",
            type: .headphones, batteryLevel: 64,
            components: [.init(kind: .left, level: 100, isCharging: true), .init(kind: .right, level: 64, isCharging: true),
                         .init(kind: .case, level: 78, isCharging: false)], accessoryIdentifier: group)
        let result = scene.merge(power: [power])
        #expect(result.devices.count == 3)
        #expect(result.devices.first { $0.type == .headphones }?.components.map(\.isCharging) == [true, true, false])
        #expect(result.learnedBindings.isEmpty, "有效 GATT 绑定不被另一个命名空间的电源分组 UUID 替换")
    }

    @Test func inputOrderAndDuplicateSnapshotsDoNotChangeThePhysicalList() throws {
        let original = try Self.scene()
        for reverseIO in [false, true] {
            for reverseProfiler in [false, true] {
                var scene = original
                if reverseIO { scene.io.reverse() }
                if reverseProfiler { scene.profiler.reverse() }
                scene.ble = Array((scene.ble + scene.ble).reversed())
                let devices = scene.merge().devices
                #expect(devices.count == 3)
                #expect(Set(devices.map(\.id)).count == 3)
                #expect(devices.first { $0.type == .headphones }?.components.map(\.level) == [100, 64, 78])
            }
        }
    }

    @Test func sameNameIndependentPairedHeadphonesStaySeparate() throws {
        var scene = try Self.scene()
        let other = BluetoothDeviceInfo(address: "aabbcc000005", name: "Other AirPods", type: .headphones, batteryLevel: 25)
        scene.io.append(other)
        scene.paired.append(other)
        scene.profiler.append(BluetoothDeviceInfo(address: other.address, name: "AirPods 4 (ANC)", type: .headphones, batteryLevel: 25))
        let result = scene.merge()
        #expect(result.devices.contains { $0.address == other.address && $0.batteryLevel == 25 })
        #expect(result.devices.contains { $0.address == "aabbcc000001" && $0.batteryLevel == 64 })
        #expect(result.devices.contains { $0.address == "aabbcc000002" }, "存在两个主身份时不能猜测辅助记录归属")
    }

    @Test func unknownUUIDWithItsOwnBatteryIsNotCollapsedByName() throws {
        var scene = try Self.scene()
        scene.ble[1] = BLEDeviceSnapshot(identifier: scene.ble[1].identifier, name: scene.ble[1].name, batteryLevel: 12)
        let result = scene.merge()
        #expect(result.devices.count == 4)
        #expect(result.devices.contains { $0.address == "ble-" + scene.ble[1].identifier.uuidString && $0.batteryLevel == 12 })
    }

    @Test func anIndependentProfilerIdentityAlsoMakesTheAliasAmbiguous() throws {
        var scene = try Self.scene()
        scene.profiler.append(BluetoothDeviceInfo(address: "aabbcc000005", name: "AirPods 4 (ANC)",
            type: .headphones, batteryLevel: 25, services: "A2DP"))
        let devices = scene.merge().devices
        #expect(devices.contains { $0.address == "aabbcc000005" && $0.batteryLevel == 25 })
        #expect(devices.contains { $0.address == "aabbcc000002" }, "系统确认的独立音频身份也必须阻止猜测归并")
    }

    @Test func auxiliaryBatteryOnlyFillsAnEntirelyMissingPrimaryReport() throws {
        var scene = try Self.scene()
        let primary = try #require(scene.profiler.first { !$0.isBLETransportOnly })
        scene.profiler = scene.profiler.filter(\.isBLETransportOnly)
        scene.profiler.append(BluetoothDeviceInfo(address: primary.address, name: primary.name,
            type: primary.type, batteryLevel: nil, services: primary.services))
        let devices = scene.merge().devices
        #expect(devices.count == 3)
        #expect(devices.first { $0.type == .headphones }?.components.map(\.level) == [100, 78])
        #expect(devices.first { $0.type == .headphones }?.name == "Personal AirPods")
    }

    @Test func manyMACAliasesForOneUUIDDoNotDiscardTheCompletePrimaryReport() throws {
        var scene = try Self.scene()
        let id = scene.ble[0].identifier
        scene.bindings = ["aabbcc000001": id.uuidString, "aabbcc000002": id.uuidString]
        scene.ble = [scene.ble[0], scene.ble[0]]
        let devices = scene.merge().devices
        #expect(devices.count == 3)
        #expect(devices.first { $0.type == .headphones }?.components.map(\.level) == [100, 64, 78])
    }

    @Test func aCurrentBLEPlaceholderAloneKeepsOnePairedPhysicalIdentity() throws {
        var scene = try Self.scene()
        scene.io = []
        scene.profiler = []
        let devices = scene.merge(aliases: ["aabbcc000001": ["AirPods 4 (ANC)"]]).devices
        #expect(devices.count == 1)
        #expect(devices.first?.address == "aabbcc000001")
        #expect(devices.first?.name == "Personal AirPods")
        #expect(devices.first?.batteryLevel == nil)
    }

    @Test func aSingleCurrentUUIDCanReplaceAnAbsentCachedUUID() throws {
        var scene = try Self.scene()
        scene.ble = [scene.ble[0]]
        let result = scene.merge()
        #expect(result.learnedBindings["aabbcc000001"] == scene.ble[0].identifier.uuidString)
        #expect(result.devices.count == 3)
        scene.bindings.merge(result.learnedBindings) { _, new in new }
        scene.ble = [BLEDeviceSnapshot(identifier: scene.ble[0].identifier, name: scene.ble[0].name, batteryLevel: 0)]
        #expect(scene.merge().devices.first { $0.address == "aabbcc000001" }?.batteryLevel == 0)
    }

    @Test func aStillPresentCachedUUIDCannotBeStolenByAnotherUUID() throws {
        var scene = try Self.scene()
        let old = try #require(scene.bindings["aabbcc000001"].flatMap(UUID.init(uuidString:)))
        scene.ble = [BLEDeviceSnapshot(identifier: old, name: "Personal AirPods", batteryLevel: 64),
                     BLEDeviceSnapshot(identifier: scene.ble[0].identifier, name: "AirPods 4 (ANC)", batteryLevel: 12)]
        let result = scene.merge()
        #expect(result.learnedBindings["aabbcc000001"] == nil)
        #expect(result.devices.count == 4)
    }

    @Test func oneUnknownUUIDWithBatteryCannotReplaceAnOldBindingByNameAlone() throws {
        var scene = try Self.scene()
        let id = scene.ble[0].identifier
        scene.ble = [BLEDeviceSnapshot(identifier: id, name: scene.ble[0].name, batteryLevel: 12)]
        let result = scene.merge()
        #expect(result.learnedBindings["aabbcc000001"] == nil)
        #expect(result.devices.count == 4)
        #expect(result.devices.first { $0.address == "aabbcc000001" }?.batteryLevel == 64)
    }

    @Test func conflictingCachedUUIDsCannotAssignBatteryToAnArbitraryPhysicalDevice() throws {
        var scene = try Self.scene()
        let other = BluetoothDeviceInfo(address: "aabbcc000005", name: "Personal AirPods",
            type: .headphones, batteryLevel: 25)
        scene.io.append(other)
        scene.paired.append(other)
        let id = scene.ble[0].identifier
        scene.bindings = ["aabbcc000001": id.uuidString, other.address: id.uuidString]
        scene.ble = [BLEDeviceSnapshot(identifier: id, name: "Personal AirPods", batteryLevel: 12)]
        let result = scene.merge()
        #expect(result.devices.first { $0.address == "aabbcc000001" }?.batteryLevel == 64)
        #expect(result.devices.first { $0.address == other.address }?.batteryLevel == 25)
        #expect(result.devices.contains { $0.address == "ble-" + id.uuidString && $0.batteryLevel == 12 })
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func duplicateUUIDPrefersValidZeroAndStandaloneDevicesRemainVisible() {
        let id = UUID()
        let empty = BLEDeviceSnapshot(identifier: id, name: "Independent Headphones", batteryLevel: nil)
        let zero = BLEDeviceSnapshot(identifier: id, name: "Independent Headphones", batteryLevel: 0)
        for snapshots in [[empty, zero, empty], [zero, empty, zero]] {
            let result = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: snapshots, bindings: [:])
            #expect(result.devices.count == 1)
            #expect(result.devices.first?.batteryLevel == 0)
        }
    }

    @Test func duplicateUUIDRetainsAppearanceWhenOnlyTheOtherSnapshotHasBattery() {
        let id = UUID()
        let typed = BLEDeviceSnapshot(identifier: id, name: "Audio Accessory", batteryLevel: nil, appearance: 0x0941)
        let zero = BLEDeviceSnapshot(identifier: id, name: nil, batteryLevel: 0)
        for snapshots in [[typed, zero], [zero, typed]] {
            let result = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: snapshots, bindings: [:])
            #expect(result.devices.count == 1)
            #expect(result.devices.first?.type == .headphones)
            #expect(result.devices.first?.name == "Audio Accessory")
            #expect(result.devices.first?.batteryLevel == 0)
        }
    }

    @Test func pairedCustomNameWinsWithoutAClassicAudioConnection() throws {
        var scene = try Self.scene()
        scene.io = []
        let devices = scene.merge().devices
        #expect(devices.count == 1)
        #expect(devices.first?.address == "aabbcc000001")
        #expect(devices.first?.name == "Personal AirPods")
        #expect(devices.first?.components.map(\.level) == [100, 64, 78])
    }

    @Test func missingReportsAndReconnectNeverReintroduceEmptyDuplicateRows() throws {
        let original = try Self.scene()
        var missing = original
        missing.profiler = original.profiler.map { device in
            var empty = BluetoothDeviceInfo(address: device.address, name: device.name, type: device.type,
                batteryLevel: nil, services: device.services)
            empty.isBLETransportOnly = device.isBLETransportOnly
            return empty
        }
        var disconnected = original
        disconnected.io.removeAll { $0.type == .headphones }
        disconnected.profiler = []
        disconnected.ble = []
        let states = [original, missing, disconnected, original].map { $0.merge().devices }
        #expect(states.map { $0.filter { $0.type == .headphones }.count } == [1, 1, 0, 1])
        #expect(states[1].first { $0.type == .headphones }?.components.isEmpty == true)
        #expect(states[3].first { $0.type == .headphones }?.components.map(\.level) == [100, 64, 78])
    }

    @Test func openCaseUsesVerifiedSessionAliasesAndDoesNotResurrectAfterDisconnect() throws {
        var scene = try Self.scene()
        scene.io = []
        scene.profiler = scene.profiler.filter(\.isBLETransportOnly)
        let current = scene.merge(aliases: ["aabbcc000001": ["AirPods 4 (ANC)"]])
        #expect(current.devices.count == 1)
        #expect(current.devices.first?.address == "aabbcc000001")
        scene.profiler = []
        scene.ble = []
        #expect(scene.merge().devices.isEmpty)
    }

    @Test func coldStartWithOpenCaseUsesOfflineMACOnlyAsAnAlias() throws {
        var scene = try Self.scene()
        scene.io = []
        scene.profiler = scene.profiler.filter(\.isBLETransportOnly)
        let raw: [String: Any] = ["SPBluetoothDataType": [["device_not_connected": [["AirPods 4 (ANC)": [
            "device_address": "AA:BB:CC:00:00:01", "device_minorType": "Headphones"
        ]]]]]]
        let data = try JSONSerialization.data(withJSONObject: raw)
        let aliases = BluetoothBatterySampler.identityAliases(profilerJSON: data)
        #expect(aliases["aabbcc000001"] == ["AirPods 4 (ANC)"])
        let id = UUID()
        let power = BluetoothDeviceInfo(address: "ble-" + id.uuidString, name: "AirPods 4 (ANC)",
            type: .headphones, batteryLevel: 64,
            components: [.init(kind: .left, level: 100, isCharging: true), .init(kind: .right, level: 64, isCharging: true),
                         .init(kind: .case, level: 78, isCharging: false)], accessoryIdentifier: id)
        let devices = scene.merge(aliases: aliases, power: [power]).devices
        #expect(devices.count == 1)
        #expect(devices.first?.address == "aabbcc000001")
        #expect(devices.first?.name == "Personal AirPods")
        #expect(devices.first?.components.map(\.isCharging) == [true, true, false])
        scene.profiler = []
        scene.ble = []
        #expect(scene.merge(aliases: aliases).devices.isEmpty, "历史名称不能让离线设备重新上线")
    }
}
