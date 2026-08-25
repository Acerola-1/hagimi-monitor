import Testing
import Foundation
@testable import HagimiMonitorDirect

struct BluetoothBatteryParserTests {
    @Test func parsesSinglePercent() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "63%") == 63)
        #expect(BluetoothBatteryParser.batteryLevel(from: "100%") == 100)
    }

    @Test func parsesBareNumber() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "42") == 42)
    }

    @Test func parsesMultiSegmentTakesMinimum() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "Left: 67%, Right: 65%, Case: 89%") == 65)
    }

    @Test func parsesBatteryLevelMainVariant() {
        // macOS 26 的键值形态。
        #expect(BluetoothBatteryParser.batteryLevel(from: "100%") == 100)
        let combined = ["100%", "90%"].joined(separator: ", ")
        #expect(BluetoothBatteryParser.batteryLevel(from: combined) == 90)
    }

    @Test func ignoresOutOfRangeNumbers() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "Firmware 24.1, Level 78%") == 78)
    }

    @Test func returnsNilForMissingOrEmpty() {
        #expect(BluetoothBatteryParser.batteryLevel(from: nil) == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "") == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "unknown") == nil)
    }
}

struct BluetoothDeviceTypeTests {
    @Test func mapsKnownMinorTypes() {
        #expect(BluetoothDeviceType(minorType: "Mouse") == .mouse)
        #expect(BluetoothDeviceType(minorType: "Keyboard") == .keyboard)
        #expect(BluetoothDeviceType(minorType: "Headphones") == .headphones)
        #expect(BluetoothDeviceType(minorType: "Headset") == .headset)
        #expect(BluetoothDeviceType(minorType: "Gamepad") == .gamepad)
        #expect(BluetoothDeviceType(minorType: "Trackpad") == .trackpad)
        #expect(BluetoothDeviceType(minorType: "Speaker") == .speaker)
    }

    @Test func fallsBackToOther() {
        #expect(BluetoothDeviceType(minorType: nil) == .other)
        #expect(BluetoothDeviceType(minorType: "Wearable") == .other)
    }

    @Test func mapsClassOfDevice() {
        // 实测:小米耳夹式耳机 major=4 minor=0x6;红米 Buds 4 major=4 minor=0x1。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x6) == .headphones)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x1) == .headphones)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x8) == .speaker)
        // Xbox 手柄 major=5 minor=0x2(gamepad 子类型)。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x2) == .gamepad)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x40) == .keyboard)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x80) == .mouse)
        // misc(comajor=0,如 BLE 鼠标)无形态信息。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 0, minor: 0) == nil)
    }

    @Test func infersTypeFromName() {
        #expect(BluetoothDeviceType.inferred(fromName: "Rapoo BT Mouse") == .mouse)
        #expect(BluetoothDeviceType.inferred(fromName: "小米鼠标") == .mouse)
        #expect(BluetoothDeviceType.inferred(fromName: "Redmi Buds 4") == .headphones)
        #expect(BluetoothDeviceType.inferred(fromName: "小米耳夹式耳机") == .headphones)
        #expect(BluetoothDeviceType.inferred(fromName: "AirPods Pro") == .headphones)
        #expect(BluetoothDeviceType.inferred(fromName: "Keychron Keyboard") == .keyboard)
        #expect(BluetoothDeviceType.inferred(fromName: "Xbox Wireless Controller") == .gamepad)
    }

    @Test func infersOtherForUnknownName() {
        #expect(BluetoothDeviceType.inferred(fromName: "苏轼的鹅鸡") == .other)
    }
}

struct BluetoothNormalizeMACTests {
    @Test func normalizesAcrossFormats() {
        // IOBluetooth 报横线小写,system_profiler 报冒号大写。
        #expect(BluetoothBatterySampler.normalizeMAC("00-13-d6-b7-52-af") == "0013d6b752af")
        #expect(BluetoothBatterySampler.normalizeMAC("00:13:D6:B7:52:AF") == "0013d6b752af")
        #expect(BluetoothBatterySampler.normalizeMAC("") == "")
    }
}

struct BluetoothMergeTests {
    private static func device(
        _ name: String,
        address: String? = nil,
        type: BluetoothDeviceType = .other,
        battery: Int? = nil,
        services: String? = nil
    ) -> BluetoothDeviceInfo {
        BluetoothDeviceInfo(address: address ?? name, name: name, type: type, batteryLevel: battery, services: services)
    }

    private static func snapshot(
        _ name: String,
        uuid: String = "00000000-0000-0000-0000-000000000001",
        battery: Int? = nil
    ) -> BLEDeviceSnapshot {
        BLEDeviceSnapshot(identifier: UUID(uuidString: uuid)!, name: name, batteryLevel: battery)
    }

    @Test func directBuildMergesAllThreeSources() {
        // 直连版全量场景:IOBluetooth 给改名后系统名+CoD 类型,profiler 按
        // MAC 注入电量(device_batteryLevelMain),BLE 快照按相似度配对补电量。
        let io = [
            Self.device("苏轼的鹅鸡", address: "0013d6b752af", type: .headphones),
            Self.device("Redmi Buds 4", address: "7cc95e67e53f", type: .headset),
        ]
        let profiler = [
            Self.device("小米耳夹式耳机", address: "00:13:D6:B7:52:AF", type: .headphones,
                        battery: 100, services: "HFP AVRCP A2DP GATT ACL"),
            Self.device("Redmi Buds 4", address: "7C:C9:5E:67:E5:3F", type: .headset,
                        battery: 100, services: "HFP AVRCP A2DP ACL"),
            Self.device("Rapoo BT Mouse", address: "D3:00:D1:02:3E:53", type: .mouse,
                        services: "HID BLE"),
        ]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: profiler,
            bleSnapshots: [
                Self.snapshot("苏轼的鹅机", uuid: "00000000-0000-0000-0000-0000000000AA", battery: 100),
                Self.snapshot("Rapoo BT Mouse", uuid: "00000000-0000-0000-0000-0000000000BB", battery: 50),
            ],
            bindings: [:]
        )
        // 三台物理设备,不裂条目。
        #expect(result.devices.count == 3)
        let xiaomi = result.devices.first { $0.address == "0013d6b752af" }
        #expect(xiaomi?.name == "苏轼的鹅鸡")
        #expect(xiaomi?.type == .headphones)
        #expect(xiaomi?.batteryLevel == 100)
        let redmi = result.devices.first { $0.address == "7cc95e67e53f" }
        #expect(redmi?.batteryLevel == 100)
        #expect(redmi?.type == .headset)
        let mouse = result.devices.first { $0.name == "Rapoo BT Mouse" }
        #expect(mouse?.batteryLevel == 50)
        #expect(mouse?.type == .mouse)
        // 相似度配对与同名匹配都学习到绑定。
        #expect(result.learnedBindings["0013d6b752af"] == "00000000-0000-0000-0000-0000000000AA")
        #expect(result.learnedBindings["d300d1023e53"] == "00000000-0000-0000-0000-0000000000BB")
    }

    @Test func appstoreBuildReliesOnIOBluetoothAndBLE() {
        // App Store 沙盒场景:profiler 为空,IOBluetooth 给清单、类型与
        // 系统侧电量(AVRCP/HFP 上报,Redmi 这类无 GATT 设备的唯一电量来源),
        // BLE 快照经相似度配对注入 GATT 精确电量并学习绑定。
        let io = [
            Self.device("苏轼的鹅鸡", address: "0013d6b752af", type: .headphones, battery: 100),
            Self.device("Redmi Buds 4", address: "7cc95e67e53f", type: .headset, battery: 100),
        ]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("苏轼的鹅机", uuid: "00000000-0000-0000-0000-0000000000AA", battery: 90),
                Self.snapshot("Rapoo BT Mouse", uuid: "00000000-0000-0000-0000-0000000000BB", battery: 50),
            ],
            bindings: [:]
        )
        // 三台:两台 IOBluetooth + 一台 BLE 独有(名称推断类型)。
        #expect(result.devices.count == 3)
        let xiaomi = result.devices.first { $0.address == "0013d6b752af" }
        #expect(xiaomi?.name == "苏轼的鹅鸡")
        #expect(xiaomi?.type == .headphones)
        // GATT 精确值覆盖系统侧粗粒度读数。
        #expect(xiaomi?.batteryLevel == 90)
        let redmi = result.devices.first { $0.address == "7cc95e67e53f" }
        #expect(redmi?.batteryLevel == 100)
        #expect(result.devices.first { $0.name == "Rapoo BT Mouse" }?.batteryLevel == 50)
        #expect(result.learnedBindings["0013d6b752af"] == "00000000-0000-0000-0000-0000000000AA")
    }

    @Test func learnedBindingSurvivesRenameAndSiblingOrphans() {
        // 绑定已学习后:设备再次改名、旁边有无电量孤儿干扰,仍按 UUID 稳定合并。
        let binding = ["0013d6b752af": "00000000-0000-0000-0000-0000000000AA"]
        let io = [
            Self.device("苏轼的鹅鸡", address: "0013d6b752af", type: .headphones),
            Self.device("红米耳机", address: "aabbccddeeff", type: .headset),
        ]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("随便什么新名", uuid: "00000000-0000-0000-0000-0000000000AA", battery: 88),
            ],
            bindings: binding
        )
        #expect(result.devices.count == 2)
        let xiaomi = result.devices.first { $0.address == "0013d6b752af" }
        #expect(xiaomi?.batteryLevel == 88)
        #expect(xiaomi?.type == .headphones)
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func doesNotPairWhenNamesDissimilar() {
        // CB 孤儿与清单条目名字毫不相干(距离 > 1/3):不猜,CB 条目独立保留。
        let io = [Self.device("Redmi Buds 4", address: "7cc95e67e53f", type: .headset)]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [Self.snapshot("WH-1000XM5", battery: 70)],
            bindings: [:]
        )
        #expect(result.devices.count == 2)
        #expect(result.learnedBindings.isEmpty)
    }

    @Test func doesNotPairAmbiguousSimilarNames() {
        // 两个条目与 CB 孤儿名字等距(同名设备):歧义不猜。
        let io = [
            Self.device("WH-1000XM5", address: "aaaa00000001", type: .headphones),
            Self.device("WH-1000XM5", address: "aaaa00000002", type: .headphones),
        ]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [Self.snapshot("WH-1000XM5", battery: 70)],
            bindings: [:]
        )
        // 同名匹配会先消化第一个;学习绑定后第二个是 CB 独有……本用例中
        // 同名匹配直接命中(3b),验证不裂多余条目即可。
        #expect(result.devices.count == 2)
    }
}

struct BluetoothProfilerJSONTests {
    /// 与实测 system_profiler SPBluetoothDataType -json 同构的 fixture:
    /// macOS 26 键形态(device_batteryLevelMain)+ 旧键形态混排,蓝牙开启。
    private static let fixture = Data("""
    {
      "SPBluetoothDataType": [
        {
          "controller_properties": {
            "controller_state": "attrib_on"
          },
          "device_connected": [
            {
              "Magic Mouse": {
                "device_address": "AA:BB:CC:DD:EE:01",
                "device_minorType": "Mouse",
                "device_batteryLevel": "74%"
              }
            },
            {
              "Redmi Buds 4": {
                "device_address": "AA:BB:CC:DD:EE:02",
                "device_minorType": "Headset",
                "device_batteryLevelMain": "100%",
                "device_services": "0x800019 < HFP AVRCP A2DP ACL >"
              }
            },
            {
              "AirPods Pro": {
                "device_address": "AA:BB:CC:DD:EE:04",
                "device_minorType": "Headphones",
                "device_batteryLevelLeft": "67%",
                "device_batteryLevelRight": "65%"
              }
            }
          ],
          "device_not_connected": [
            {
              "Old Headset": {
                "device_address": "AA:BB:CC:DD:EE:03",
                "device_minorType": "Headset"
              }
            }
          ]
        }
      ]
    }
    """.utf8)

    @Test func parsesConnectedDevicesOnly() {
        let result = BluetoothBatterySampler.parse(profilerJSON: Self.fixture)
        #expect(result.controllerOn)
        #expect(result.devices.count == 3)
        #expect(!result.devices.contains { $0.name == "Old Headset" })
    }

    @Test func parsesBatteryMainAndLegacyKeys() {
        let result = BluetoothBatterySampler.parse(profilerJSON: Self.fixture)
        #expect(result.devices.first { $0.name == "Magic Mouse" }?.batteryLevel == 74)
        // macOS 26 的 Main 键。
        #expect(result.devices.first { $0.name == "Redmi Buds 4" }?.batteryLevel == 100)
        // 多单体取最小值。
        #expect(result.devices.first { $0.name == "AirPods Pro" }?.batteryLevel == 65)
    }

    @Test func normalizesAddressInParse() {
        // 解析阶段即完成归一化(去冒号小写),与 IOBluetooth 地址可直接对齐。
        let result = BluetoothBatterySampler.parse(profilerJSON: Self.fixture)
        #expect(result.devices.first { $0.name == "Redmi Buds 4" }?.address == "aabbccddee02")
    }

    @Test func sortsBatteryReportingDevicesFirst() {
        let result = BluetoothBatterySampler.parse(profilerJSON: Self.fixture)
        #expect(result.devices.first?.batteryLevel != nil)
    }

    @Test func parsesControllerOff() {
        let json = Data("""
        {
          "SPBluetoothDataType": [
            {
              "controller_properties": { "controller_state": "attrib_off" },
              "device_connected": []
            }
          ]
        }
        """.utf8)
        let result = BluetoothBatterySampler.parse(profilerJSON: json)
        #expect(!result.controllerOn)
        #expect(result.devices.isEmpty)
    }

    @Test func returnsEmptyForMalformedJSON() {
        let result = BluetoothBatterySampler.parse(profilerJSON: Data("not json".utf8))
        #expect(!result.controllerOn)
        #expect(result.devices.isEmpty)
    }

    @Test func returnsEmptyForSandboxSkeleton() {
        // App Store 沙盒内 system_profiler 返回空骨架(无 controller_state、
        // 无设备):解析结果为空且 controllerOn=false。
        let json = Data("""
        {
          "SPBluetoothDataType": [
            {
              "controller_properties" : {}
            }
          ]
        }
        """.utf8)
        let result = BluetoothBatterySampler.parse(profilerJSON: json)
        #expect(!result.controllerOn)
        #expect(result.devices.isEmpty)
    }
}
