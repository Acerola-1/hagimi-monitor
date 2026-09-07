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

    @Test func acceptsZeroPercent() {
        // 0% 是合法电量(设备耗尽),解析器须接受。
        #expect(BluetoothBatteryParser.batteryLevel(from: "0%") == 0)
        #expect(BluetoothBatteryParser.batteryLevel(from: "0") == 0)
    }

    @Test func rejectsOutOfRangeValues() {
        // GATT 2A19 规范:101-255 是保留值,不得污染缓存。
        #expect(BluetoothBatteryParser.batteryLevel(from: "101%") == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "255") == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "150%") == nil)
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
        // Audio/Video (major=4):实测小米耳夹式耳机 minor=0x6;红米 Buds 4 minor=0x1。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x6) == .headphones)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x1) == .headphones)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x8) == .speaker)
        // Peripheral (major=5):低 6 位子类型,依据 SDK 常量。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x01) == .gamepad)  // Joystick
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x02) == .gamepad)  // Gamepad (Xbox 手柄)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x10) == .keyboard)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x20) == .mouse)  // Pointing
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x30) == .mouse)  // Combo keyboard/pointing
        // 数位板 (Digitizer Tablet) 归 other,不强行猜测。
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x04) == nil)
        // misc(major=0,如 BLE 鼠标)无形态信息。
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

    @Test func mapsGAPAppearance() {
        // 值表:SIG Assigned Numbers appearance_values.yaml(Wearable Audio 0x0940 段、
        // Audio Sink 0x0840 段、HID 0x03C0 段)。
        #expect(BluetoothDeviceType.fromAppearance(0x0941) == .headphones) // Earbud
        #expect(BluetoothDeviceType.fromAppearance(0x0943) == .headphones) // Headphones
        #expect(BluetoothDeviceType.fromAppearance(0x0945) == .headphones) // Left Earbud
        #expect(BluetoothDeviceType.fromAppearance(0x0942) == .headset)    // Headset
        #expect(BluetoothDeviceType.fromAppearance(0x0841) == .speaker)    // Standalone Speaker
        #expect(BluetoothDeviceType.fromAppearance(0x0845) == .speaker)    // Speakerphone
        #expect(BluetoothDeviceType.fromAppearance(0x03C1) == .keyboard)
        #expect(BluetoothDeviceType.fromAppearance(0x03C2) == .mouse)
        #expect(BluetoothDeviceType.fromAppearance(0x03C4) == .gamepad)
        #expect(BluetoothDeviceType.fromAppearance(0x03C5) == .trackpad)   // Digitizer Tablet
        // 无对应图标语言的形态(phone 等)返回 nil,调用方沿名称推断兜底。
        #expect(BluetoothDeviceType.fromAppearance(0x0040) == nil)
        #expect(BluetoothDeviceType.fromAppearance(0x0002) == nil)
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
        battery: Int? = nil,
        appearance: UInt16? = nil
    ) -> BLEDeviceSnapshot {
        BLEDeviceSnapshot(identifier: UUID(uuidString: uuid)!, name: name, batteryLevel: battery, appearance: appearance)
    }

    @Test func appearanceFillsUnknownTypeForBoundDevice() {
        // 沙盒内 BLE-only 耳机无 CoD 可读(IO major=0)、profiler 为空时,靠 GATT Appearance 补齐形态类别。
        let binding = ["001122334455": "00000000-0000-0000-0000-0000000000AA"]
        let io = [Self.device("苏轼的鹅鸡", address: "001122334455")] // CoD 未知 → .other
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("改名后的新名", uuid: "00000000-0000-0000-0000-0000000000AA",
                              battery: 80, appearance: 0x0941),
            ],
            bindings: binding
        )
        let earbuds = result.devices.first { $0.address == "001122334455" }
        #expect(earbuds?.type == .headphones)
        #expect(earbuds?.batteryLevel == 80)
    }

    @Test func appearanceTypesCBOnlyDeviceAheadOfNameGuess() {
        // CB 独有设备:Appearance 是设备自报形态,优先于名称关键词推断。
        let result = BluetoothBatterySampler.merge(
            ioDevices: [],
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("SBT-5 无线终端", uuid: "00000000-0000-0000-0000-0000000000CC",
                              battery: 60, appearance: 0x0943),
            ],
            bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices[0].type == .headphones)
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
        // 两个 IO 设备同名 + 一个 BLE 快照同名:IO 侧不唯一,禁止学习绑定。
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
        // 不得错误学习绑定;BLE 快照成为 CB 独有设备,总数 = 2 IO + 1 CB = 3。
        #expect(result.learnedBindings.isEmpty)
        #expect(result.devices.count == 3)
    }

    @Test func doesNotPairWhenMultipleSnapshotsSameName() {
        // 一个 IO 设备 + 两个同名 BLE 快照:BLE 侧不唯一,禁止学习绑定。
        let io = [Self.device("AirPods Pro", address: "bbbb00000001", type: .headphones)]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("AirPods Pro", uuid: "00000000-0000-0000-0000-0000000000A1", battery: 80),
                Self.snapshot("AirPods Pro", uuid: "00000000-0000-0000-0000-0000000000A2", battery: 75),
            ],
            bindings: [:]
        )
        // 不得任选一个绑定;两个 BLE 快照均成为 CB 独有设备。
        #expect(result.learnedBindings.isEmpty)
        #expect(result.devices.count == 3)
    }

    @Test func doesNotPairWhenBothSidesHaveDuplicates() {
        // 两边各两台同名设备:双侧均不唯一,禁止学习绑定。
        let io = [
            Self.device("Magic Mouse", address: "cccc00000001", type: .mouse),
            Self.device("Magic Mouse", address: "cccc00000002", type: .mouse),
        ]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("Magic Mouse", uuid: "00000000-0000-0000-0000-0000000000B1", battery: 60),
                Self.snapshot("Magic Mouse", uuid: "00000000-0000-0000-0000-0000000000B2", battery: 55),
            ],
            bindings: [:]
        )
        #expect(result.learnedBindings.isEmpty)
        #expect(result.devices.count == 4)
    }

    @Test func existingBindingSurvivesRename() {
        // 已有可靠绑定时改名:绑定优先于同名/相似度匹配,改名免疫。
        let io = [Self.device("旧名字", address: "dddd00000001", type: .headphones)]
        let bindings = ["dddd00000001": "00000000-0000-0000-0000-0000000000C1"]
        let result = BluetoothBatterySampler.merge(
            ioDevices: io,
            profilerDevices: [],
            bleSnapshots: [
                Self.snapshot("新名字", uuid: "00000000-0000-0000-0000-0000000000C1", battery: 90),
            ],
            bindings: bindings
        )
        // 绑定命中,电量注入,不产生新学习绑定(已有绑定保持)。
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == 90)
        #expect(result.devices.first?.name == "旧名字")  // IOBluetooth 系统名优先
        #expect(result.learnedBindings.isEmpty)
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

    /// 测试辅助:提取 .success 结果,失败返回 nil。
    private static func parseSuccess(_ data: Data) -> (controllerOn: Bool?, devices: [BluetoothDeviceInfo])? {
        if case .success(let controllerOn, let devices) = BluetoothBatterySampler.parse(profilerJSON: data) {
            return (controllerOn, devices)
        }
        return nil
    }

    @Test func parsesConnectedDevicesOnly() {
        let result = Self.parseSuccess(Self.fixture)
        #expect(result?.controllerOn == true)
        #expect(result?.devices.count == 3)
        #expect(!(result?.devices.contains { $0.name == "Old Headset" } ?? false))
    }

    @Test func parsesBatteryMainAndLegacyKeys() {
        let result = Self.parseSuccess(Self.fixture)
        #expect(result?.devices.first { $0.name == "Magic Mouse" }?.batteryLevel == 74)
        // macOS 26 的 Main 键。
        #expect(result?.devices.first { $0.name == "Redmi Buds 4" }?.batteryLevel == 100)
        // 多单体取最小值。
        #expect(result?.devices.first { $0.name == "AirPods Pro" }?.batteryLevel == 65)
    }

    @Test func normalizesAddressInParse() {
        // 解析阶段即完成归一化(去冒号小写),与 IOBluetooth 地址可直接对齐。
        let result = Self.parseSuccess(Self.fixture)
        #expect(result?.devices.first { $0.name == "Redmi Buds 4" }?.address == "aabbccddee02")
    }

    @Test func sortsBatteryReportingDevicesFirst() {
        let result = Self.parseSuccess(Self.fixture)
        #expect(result?.devices.first?.batteryLevel != nil)
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
        // 探针成功报告蓝牙关闭:允许清空设备清单,与 .failure 区分。
        #expect(BluetoothBatterySampler.parse(profilerJSON: json) == .success(controllerOn: false, devices: []))
    }

    @Test func successWithEmptyDevicesIsNotFailure() {
        // 探针成功但无已连接设备(蓝牙开启):允许清空 profiler 设备。
        let json = Data("""
        {
          "SPBluetoothDataType": [
            {
              "controller_properties": { "controller_state": "attrib_on" },
              "device_connected": []
            }
          ]
        }
        """.utf8)
        #expect(BluetoothBatterySampler.parse(profilerJSON: json) == .success(controllerOn: true, devices: []))
    }

    @Test func malformedJSONIsFailure() {
        // JSON 失效 = 数据不完整,不构成关闭证据;保留上次成功快照。
        #expect(BluetoothBatterySampler.parse(profilerJSON: Data("not json".utf8)) == .failure)
    }

    @Test func sandboxSkeletonIsFailure() {
        // App Store 沙盒内 system_profiler 返回空骨架(无 controller_state、
        // 无 device_connected):不构成权威结论,归为 failure 保留上次快照。
        let json = Data("""
        {
          "SPBluetoothDataType": [
            {
              "controller_properties" : {}
            }
          ]
        }
        """.utf8)
        #expect(BluetoothBatterySampler.parse(profilerJSON: json) == .failure)
    }
}

struct BluetoothAcceptanceMatrixTests {
    // 场景 1: 蓝牙关闭立即覆盖旧 profiler 开启快照
    @Test func bluetoothPowerOffOverridesOldProfiler() {
        let oldProfilerDate = Date(timeIntervalSinceNow: -5)
        let freshCBPowerOffDate = Date()
        let state = BluetoothBatterySampler.resolveControllerState(
            cbEvidence: (isOn: false, at: freshCBPowerOffDate),
            profilerEvidence: (isOn: true, at: oldProfilerDate),
            hasIODevices: true
        )
        #expect(state == .off)
    }

    // 场景 2: 蓝牙开启与权威状态恢复
    @Test func bluetoothPowerOnRestoresControllerState() {
        let now = Date()
        let state = BluetoothBatterySampler.resolveControllerState(
            cbEvidence: (isOn: true, at: now),
            profilerEvidence: nil,
            hasIODevices: false
        )
        #expect(state == .on)
    }

    // 场景 3: 权限未决定或拒绝时的降级状态
    @Test func authorizationIndeterminateOrDeniedDegradation() {
        // CB 处于未决定或拒绝时证据为 nil;若 profiler 探针也无权威状态,IO 清单为空时保持 unknown
        let stateUnknown = BluetoothBatterySampler.resolveControllerState(
            cbEvidence: nil,
            profilerEvidence: nil,
            hasIODevices: false
        )
        #expect(stateUnknown == .unknown)

        // IO 有设备时作为弱证据判定为 on
        let stateWeakOn = BluetoothBatterySampler.resolveControllerState(
            cbEvidence: nil,
            profilerEvidence: nil,
            hasIODevices: true
        )
        #expect(stateWeakOn == .on)
    }

    // 场景 4: 经典蓝牙耳机与渠道降级
    @Test func classicHeadphonesChannelDifferentiation() {
        let device = BluetoothDeviceInfo(
            address: "112233445566",
            name: "Sony WH-1000XM4",
            type: .headphones,
            batteryLevel: nil
        )
        let result = BluetoothBatterySampler.merge(
            ioDevices: [device],
            profilerDevices: [],
            bleSnapshots: [],
            bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.type == .headphones)
        #expect(result.devices.first?.batteryLevel == nil)
    }

    // 场景 5: 标准 BLE 键鼠识别与精确电量优先
    @Test func standardBLEPeripheralDetectionAndBattery() {
        let ioMouse = BluetoothDeviceInfo(
            address: "aabbcc001122",
            name: "MX Master 3",
            type: .mouse,
            batteryLevel: 60
        )
        let bleSnapshot = BLEDeviceSnapshot(
            identifier: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "MX Master 3",
            batteryLevel: 65,
            appearance: 0x03C2 // HID Mouse
        )
        let result = BluetoothBatterySampler.merge(
            ioDevices: [ioMouse],
            profilerDevices: [],
            bleSnapshots: [bleSnapshot],
            bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == 65) // GATT 实时精确电量覆盖系统电量
        #expect(result.devices.first?.type == .mouse)
        #expect(result.learnedBindings["aabbcc001122"] == "11111111-2222-3333-4444-555555555555")
    }

    // 场景 6: 私有协议设备明确降级不伪造数据
    @Test func proprietaryDeviceDegradesWithoutFakeData() {
        let proprietary = BluetoothDeviceInfo(
            address: "aabbccddeeff",
            name: "Custom Device",
            type: .other,
            batteryLevel: nil,
            services: "Custom Vendor Profile"
        )
        let result = BluetoothBatterySampler.merge(
            ioDevices: [proprietary],
            profilerDevices: [],
            bleSnapshots: [],
            bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices.first?.batteryLevel == nil)
    }

    // 场景 7: 绑定记录的失效与过期维护
    @Test func bindingRecordMaintenanceAndStaleness() {
        let now = Date()
        let activeUUID = "AAAAAAAA-0000-0000-0000-000000000001"
        let staleUUID = "BBBBBBBB-0000-0000-0000-000000000002"

        let bindings: [String: BindingRecord] = [
            "111111111111": BindingRecord(uuid: activeUUID, version: 1, lastSeenAt: now.addingTimeInterval(-7200)),
            "222222222222": BindingRecord(uuid: staleUUID, version: 1, lastSeenAt: now.addingTimeInterval(-8 * 24 * 3600)),
        ]

        let outcome = BluetoothBatterySampler.maintainBindings(
            bindings,
            recalledUUIDs: [activeUUID],
            now: now,
            stalenessThreshold: 7 * 24 * 3600
        )

        #expect(outcome.changed)
        #expect(outcome.bindings["222222222222"] == nil) // 8 天未召回被淘汰
        #expect(outcome.bindings["111111111111"] != nil)
        #expect(outcome.bindings["111111111111"]?.lastSeenAt == now) // 超过 1 小时被刷新
    }

    // 场景 8: 多 Battery Service 实例聚合取最低电量
    @Test func multiBatteryServiceAggregationTakesMinimum() {
        // 模拟多单体设备：左耳 45%，右耳 80%，充电盒 95%
        let readingA = ["Left: 45%", "Right: 80%", "Case: 95%"].joined(separator: ", ")
        let minLevelA = BluetoothBatteryParser.batteryLevel(from: readingA)
        #expect(minLevelA == 45)

        // 顺序调换：右耳先到达，聚合结果依然保持最低值 45%
        let readingB = ["Right: 80%", "Left: 45%", "Case: 95%"].joined(separator: ", ")
        let minLevelB = BluetoothBatteryParser.batteryLevel(from: readingB)
        #expect(minLevelB == 45)
    }

    // 场景 9: 边界电量 0% 与 100% 完整支持
    @Test func boundaryBatteryZeroAndHundredAccepted() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "0%") == 0)
        #expect(BluetoothBatteryParser.batteryLevel(from: "100%") == 100)
    }

    // 场景 10: 越界电量 101% 与 255 严密拒绝
    @Test func outOfBoundsBatteryValuesRejected() {
        #expect(BluetoothBatteryParser.batteryLevel(from: "101%") == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "255%") == nil)
        #expect(BluetoothBatteryParser.batteryLevel(from: "255") == nil)
    }

    // 场景 11: 异常 JSON 与超时保留上次成功快照
    @Test func profilerFailurePreservesLastKnownSnapshot() {
        let malformed = BluetoothBatterySampler.parse(profilerJSON: Data("<html>502 Bad Gateway</html>".utf8))
        #expect(malformed == .failure)

        let emptyData = BluetoothBatterySampler.parse(profilerJSON: Data())
        #expect(emptyData == .failure)
    }

    // 场景 12: CoD 解析增强验证（扬声器、键盘混合低位）
    @Test func classOfDeviceEnhancedCoverage() {
        // 扬声器：Loudspeaker 0x05, Car 0x08, HiFi 0x0A
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x05) == .speaker)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x08) == .speaker)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 4, minor: 0x0A) == .speaker)

        // 键盘：带低位附加特性的键盘（0x14）依然识别为键盘
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x14) == .keyboard)

        // 鼠标：0x20
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x20) == .mouse)

        // 手柄：Joystick 0x01, Gamepad 0x02
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x01) == .gamepad)
        #expect(BluetoothDeviceType.fromClassOfDevice(major: 5, minor: 0x02) == .gamepad)
    }
}

