import Foundation
import Darwin
import Testing
@testable import HagimiMonitorDirect

/// 人工协议样本验证解析与合并边界，不代表任何型号的实机兼容性。
struct BluetoothRegressionTests {
    private static func profiler(_ name: String, properties: [String: Any]) throws -> [BluetoothDeviceInfo] {
        let json: [String: Any] = ["SPBluetoothDataType": [["device_connected": [[name: properties]]]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        guard case .success(_, let devices) = BluetoothBatterySampler.parse(profilerJSON: data) else {
            Issue.record("协议样本应成功解析")
            return []
        }
        return devices
    }

    private nonisolated static func xml(_ entries: [[String: Any]]) throws -> Data {
        try entries.reduce(into: Data()) { data, entry in
            data.append(try PropertyListSerialization.data(fromPropertyList: entry, format: .xml, options: 0))
        }
    }

    private static func keyboard(_ address: String, level: Int) -> BluetoothDeviceInfo {
        BluetoothDeviceInfo(address: address, name: "MX Keys", type: .keyboard, batteryLevel: level)
    }

    @Test(arguments: ["Headphones", "Sony Headphones", "Bose Headphones"])
    func headphoneNamesSurviveProfilerAndMerge(name: String) throws {
        let devices = try Self.profiler(name, properties: ["device_address": "AA:BB:CC:DD:EE:FF"])
        let merged = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: devices, bleSnapshots: [], bindings: [:])
        #expect(merged.devices.first?.type == .headphones)
        #expect(merged.devices.first?.type.symbol == "headphones")
    }

    @Test func appearanceCorrectsUnknownTypesThroughBLEMerge() {
        for (appearance, expected) in [(UInt16(0x0083), BluetoothDeviceType.computer), (0x0087, .tablet), (0x0944, .headphones)] {
            let snapshot = BLEDeviceSnapshot(identifier: UUID(), name: "Custom Device", batteryLevel: nil, appearance: appearance)
            let result = BluetoothBatterySampler.merge(ioDevices: [], profilerDevices: [], bleSnapshots: [snapshot], bindings: [:])
            #expect(result.devices.first?.type == expected)
        }
    }

    @Test func pmsetAddressWinsOverAnEarlierNamesake() throws {
        let report = try Self.xml([["Accessory Identifier": "BB:BB:BB:BB:BB:BB", "Name": "MX Keys", "Current Capacity": 90]])
        let devices = PMSetAccessoryParser.parse(xmlData: report)
        let result = BluetoothBatterySampler.merge(
            ioDevices: [Self.keyboard("aaaaaaaaaaaa", level: 10), Self.keyboard("bbbbbbbbbbbb", level: 20)],
            pmsetDevices: devices, profilerDevices: [], bleSnapshots: [], bindings: [:]
        )
        #expect(result.devices.count == 2)
        #expect(result.devices.first { $0.address == "aaaaaaaaaaaa" }?.batteryLevel == 10)
        #expect(result.devices.first { $0.address == "bbbbbbbbbbbb" }?.batteryLevel == 90)
    }

    @Test func ambiguousPmsetNameDoesNotChangeEitherKeyboard() throws {
        let report = try Self.xml([["Accessory Identifier": "CC:CC:CC:CC:CC:CC", "Name": "MX Keys", "Current Capacity": 90]])
        let result = BluetoothBatterySampler.merge(
            ioDevices: [Self.keyboard("aaaaaaaaaaaa", level: 10), Self.keyboard("bbbbbbbbbbbb", level: 20)],
            pmsetDevices: PMSetAccessoryParser.parse(xmlData: report), profilerDevices: [], bleSnapshots: [], bindings: [:]
        )
        #expect(result.devices.count == 3)
        #expect(result.devices.first { $0.address == "aaaaaaaaaaaa" }?.batteryLevel == 10)
        #expect(result.devices.first { $0.address == "bbbbbbbbbbbb" }?.batteryLevel == 20)
    }

    @Test func powerSourceZeroSurvivesProfilerAndBLEMetadata() throws {
        let report = try Self.xml([["Accessory Identifier": "AA:AA:AA:AA:AA:AA", "Name": "MX Keys", "Current Capacity": 0]])
        let stale = try Self.profiler("MX Keys", properties: ["device_address": "AA:AA:AA:AA:AA:AA", "device_batteryLevelMain": "76%"])
        let metadata = BLEDeviceSnapshot(identifier: UUID(), name: "MX Keys", batteryLevel: nil, appearance: 0x03C1)
        let result = BluetoothBatterySampler.merge(
            ioDevices: [Self.keyboard("aaaaaaaaaaaa", level: 50)],
            pmsetDevices: PMSetAccessoryParser.parse(xmlData: report), profilerDevices: stale, bleSnapshots: [metadata], bindings: [:]
        )
        #expect(result.devices.count == 1)
        #expect(result.devices[0].batteryLevel == 0)
        #expect(result.devices[0].batterySource == .powerSource)
    }

    @Test func matchingOneNamesakeDoesNotMakeAnotherIdentityUnique() throws {
        let report = try Self.xml([
            ["Accessory Identifier": "AA:AA:AA:AA:AA:AA", "Name": "MX Keys", "Current Capacity": 80],
            ["Accessory Identifier": "CC:CC:CC:CC:CC:CC", "Name": "MX Keys", "Current Capacity": 90]
        ])
        let result = BluetoothBatterySampler.merge(
            ioDevices: [Self.keyboard("aaaaaaaaaaaa", level: 10), Self.keyboard("bbbbbbbbbbbb", level: 20)],
            pmsetDevices: PMSetAccessoryParser.parse(xmlData: report), profilerDevices: [], bleSnapshots: [], bindings: [:]
        )
        #expect(result.devices.count == 3)
        #expect(result.devices.first { $0.address == "aaaaaaaaaaaa" }?.batteryLevel == 80)
        #expect(result.devices.first { $0.address == "bbbbbbbbbbbb" }?.batteryLevel == 20)
    }

    @Test func profilerSplitFieldsBecomeComponentsThroughMerge() throws {
        let devices = try Self.profiler("AirPods Pro", properties: [
            "device_address": "AA:BB:CC:DD:EE:FF", "device_minorType": "Headphones",
            "device_batteryLevelLeft": "67%", "device_batteryLevelRight": "0%", "device_batteryLevelCase": "89%"
        ])
        let io = BluetoothDeviceInfo(address: "aabbccddeeff", name: "AirPods Pro", type: .headphones, batteryLevel: nil)
        let result = BluetoothBatterySampler.merge(ioDevices: [io], profilerDevices: devices, bleSnapshots: [], bindings: [:])
        let device = try #require(result.devices.first)
        #expect(device.batteryLevel == 0)
        #expect(device.batterySource == .profiler)
        #expect(device.components == [
            BluetoothBatteryComponent(kind: .left, level: 67),
            BluetoothBatteryComponent(kind: .right, level: 0),
            BluetoothBatteryComponent(kind: .case, level: 89)
        ])
    }

    @Test func legacyCompositeTextRetainsComponentLabels() throws {
        let devices = try Self.profiler("AirPods", properties: [
            "device_address": "AA:BB:CC:DD:EE:FF", "device_batteryLevel": "Left: 67%, Right: 65%, Case: 89%"
        ])
        #expect(devices.first?.components.count == 3)
    }

    @Test(arguments: [false, true])
    func separateCaseGroupsBeforeDeviceMerge(caseFirst: Bool) throws {
        let combined: [String: Any] = [
            "Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Name": "AirPods Pro", "Group Identifier": "earphones-1",
            "Part Identifier": "Combined", "Accessory Category": "Audio", "Current Capacity": 10,
            "Combined Parts": [["Part Identifier": "Left", "Current Capacity": 10], ["Part Identifier": "Right", "Current Capacity": 70]]
        ]
        let caseEntry: [String: Any] = [
            "Accessory Identifier": "11:22:33:44:55:66", "Name": "AirPods Pro Case", "Group Identifier": "earphones-1",
            "Part Identifier": "Case", "Accessory Category": "Audio Battery Case", "Current Capacity": 89, "Is Charging": true
        ]
        let report = try Self.xml(caseFirst ? [caseEntry, combined] : [combined, caseEntry])
        let devices = PMSetAccessoryParser.parse(xmlData: report)
        let io = BluetoothDeviceInfo(address: "aabbccddeeff", name: "AirPods Pro", type: .headphones, batteryLevel: nil)
        let result = BluetoothBatterySampler.merge(ioDevices: [io], pmsetDevices: devices, profilerDevices: [], bleSnapshots: [], bindings: [:])
        #expect(result.devices.count == 1)
        let device = try #require(result.devices.first)
        #expect(device.address == "aabbccddeeff")
        #expect(device.batteryLevel == 10)
        #expect(device.isCharging == nil)
        #expect(device.components.first { $0.kind == .case }?.level == 89)
        #expect(device.components.first { $0.kind == .case }?.isCharging == true)
        #expect(device.components.first { $0.kind == .left }?.isCharging == nil)
    }

    private nonisolated static func executable(in directory: URL, name: String, body: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test(arguments: [false, true])
    nonisolated func pmsetTimeoutTerminatesProbeAndAllowsNextRead(closesStdout: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let hung = try Self.executable(in: directory, name: "hung", body:
            "echo $$ > '\(pidFile.path)'\ntrap '' TERM\n" + (closesStdout ? "exec 1>&-\n" : "") + "exec /bin/sleep 30\n"
        )
        let start = ContinuousClock.now
        let result = BluetoothBatterySampler.probePmset(executableURL: hung, timeout: .seconds(2))
        #expect(result.isEmpty)
        #expect(start.duration(to: .now) < .seconds(5))
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while kill(pid, 0) == 0 && ContinuousClock.now < deadline { await Task.yield() }
        #expect(kill(pid, 0) == -1)

        let valid = try Self.xml([["Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Name": "MX Keys", "Current Capacity": 0]])
        let text = try #require(String(data: valid, encoding: .utf8))
        let next = try Self.executable(in: directory, name: "next", body: "cat <<'REPORT'\n\(text)\nREPORT\n")
        #expect(BluetoothBatterySampler.probePmset(executableURL: next).first?.batteryLevel == 0)
    }

    @Test nonisolated func pmsetLargeStderrDoesNotBlockStdout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let valid = try Self.xml([["Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Name": "MX Keys", "Current Capacity": 70]])
        let text = try #require(String(data: valid, encoding: .utf8))
        let script = try Self.executable(in: directory, name: "stderr", body: "/usr/bin/head -c 200000 /dev/zero >&2\ncat <<'REPORT'\n\(text)\nREPORT\n")
        #expect(BluetoothBatterySampler.probePmset(executableURL: script, timeout: .seconds(3)).first?.batteryLevel == 70)
    }
}
