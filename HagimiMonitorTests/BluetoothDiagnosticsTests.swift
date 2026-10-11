import Foundation
import CoreBluetooth
import Testing
@testable import HagimiMonitorDirect

struct BluetoothDiagnosticsTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func records(_ folder: URL) throws -> [[String: Any]] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .flatMap { try Data(contentsOf: $0).split(separator: 0x0A).map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] } }
    }

    @Test func diagnosticsExportContainsRawBluetoothAndDisplay() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = BluetoothDiagnostics(enabled: true, directory: root.appendingPathComponent("capture"))
        let raw = Data("<plist>充电仓\n0%</plist>".utf8)
        capture.record("probe", fields: ["source": "pmset", "stdout": BluetoothDiagnostics.raw(raw)])
        let device = BluetoothDeviceInfo(address: "aabbcc", name: "AirPods", type: .headphones, batteryLevel: 0,
            components: [.init(kind: .left, level: 0), .init(kind: .case, level: 80, isCharging: true)], batterySource: .powerSource)
        capture.record("merge", fields: ["display": BluetoothDiagnostics.devices([device])])
        capture.record("ble.battery-service-status", fields: BluetoothDiagnostics.batteryServiceStatus(serviceUUIDs: ["180A", "D0611E78-BBB4-4591-A5F8-487910AE4366"], error: nil))
        capture.record("ble.device-information", fields: ["characteristic": "2A24", "text": "Watch6,7"])
        let exporter = AppLogExporter(configuration: .init(
            outputDirectory: root.appendingPathComponent("export"), appLogStore: AppLogStore(baseDirectory: root),
            launchStateTracker: AppLaunchStateTracker(baseDirectory: root), dateProvider: Date.init,
            compress: true, bluetoothDiagnostics: capture))
        let zip = try exporter.export()
        #expect(zip.pathExtension == "zip")
        let unpacked = root.appendingPathComponent("unpacked")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zip.path, unpacked.path]
        try task.run(); task.waitUntilExit()
        #expect(task.terminationStatus == 0)
        let folder = try #require(FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first)
        let log = try records(folder.appendingPathComponent("bluetooth"))
        let probe = try #require(log.first { $0["event"] as? String == "probe" }?["fields"] as? [String: Any])
        let stdout = try #require(probe["stdout"] as? [String: Any])
        #expect(stdout["value"] as? String == String(data: raw, encoding: .utf8))
        let merge = try #require(log.first { $0["event"] as? String == "merge" }?["fields"] as? [String: Any])
        let display = try #require((merge["display"] as? [[String: Any]])?.first)
        #expect(display["level"] as? Int == 0)
        #expect((display["components"] as? [[String: Any]])?.count == 2)
        let status = try #require(log.first { $0["event"] as? String == "ble.battery-service-status" }?["fields"] as? [String: Any])
        #expect(status["reason"] as? String == "battery-service-not-exposed")
        #expect(status["available"] as? Bool == false)
        let watch = try #require(log.first { $0["event"] as? String == "ble.device-information" }?["fields"] as? [String: Any])
        #expect(watch["text"] as? String == "Watch6,7")
        let failure = BluetoothDiagnostics.batteryServiceStatus(serviceUUIDs: [], error: "connection lost")
        #expect(failure["reason"] as? String == "service-discovery-failed")
        #expect(failure["available"] is NSNull)
        #expect(log.allSatisfy { $0["session"] != nil && $0["timestamp"] != nil && $0["uptime"] != nil })
    }

    @Test func advertisementPreservesManufacturerAndVendorServiceBytes() throws {
        let uuid = CBUUID(string: "FFF0")
        let input: [String: Any] = [CBAdvertisementDataManufacturerDataKey: Data([0x4c, 0x00, 0xff]),
            CBAdvertisementDataServiceUUIDsKey: [uuid], CBAdvertisementDataServiceDataKey: [uuid: Data([0, 100])]]
        let value = BluetoothDiagnostics.advertisement(input)
        let data = try JSONSerialization.data(withJSONObject: value)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json[CBAdvertisementDataManufacturerDataKey] as? [String: Any])?["value"] as? String == "4c00ff")
        #expect(json[CBAdvertisementDataServiceUUIDsKey] as? [String] == ["FFF0"])
        let services = try #require(json[CBAdvertisementDataServiceDataKey] as? [String: [String: Any]])
        #expect(services["FFF0"]?["value"] as? String == "0064")
    }

    @Test func metadataReadIsLimitedToReadableStandardDeviceInformation() {
        #expect(BLEBatteryReader.shouldReadDiagnosticMetadata(serviceUUID: "180A", characteristicUUID: "2A29", isReadable: true))
        #expect(BLEBatteryReader.shouldReadDiagnosticMetadata(serviceUUID: "180A", characteristicUUID: "2A26", isReadable: true))
        #expect(!BLEBatteryReader.shouldReadDiagnosticMetadata(serviceUUID: "FFF0", characteristicUUID: "2A29", isReadable: true))
        #expect(!BLEBatteryReader.shouldReadDiagnosticMetadata(serviceUUID: "180A", characteristicUUID: "FFF1", isReadable: true))
        #expect(!BLEBatteryReader.shouldReadDiagnosticMetadata(serviceUUID: "180A", characteristicUUID: "2A29", isReadable: false))
    }

    @Test func disabledCaptureDoesNotCreateFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("disabled")
        let store = BluetoothDiagnostics(enabled: false, directory: folder)
        store.record("connect", fields: ["name": "Watch"])
        try store.copyLogs(to: root.appendingPathComponent("export"))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("export").path))
        #expect(BluetoothDiagnostics.isEnabled("YES"))
        #expect(BluetoothDiagnostics.isEnabled(true))
        #expect(!BluetoothDiagnostics.isEnabled(nil))
        #expect(!BluetoothDiagnostics.isEnabled("NO"))
    }

    @Test func rotationRetainsRecentEventsAndDedupKeepsChanges() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BluetoothDiagnostics(enabled: true, directory: root.appendingPathComponent("capture"), maxFileSize: 1000, retainedFiles: 3)
        for index in 0..<30 { store.record("value", fields: ["index": index, "padding": String(repeating: "x", count: 180)]) }
        store.record("state", fields: ["level": 0], deduplicate: true)
        store.record("state", fields: ["level": 0], deduplicate: true)
        store.record("state", fields: ["level": 1], deduplicate: true)
        let output = root.appendingPathComponent("out")
        try store.copyLogs(to: output)
        #expect(try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).count == 3)
        let log = try records(output)
        #expect(log.contains { ($0["fields"] as? [String: Any])?["index"] as? Int == 29 })
        #expect(!log.contains { ($0["fields"] as? [String: Any])?["index"] as? Int == 0 })
        #expect(log.filter { $0["event"] as? String == "state" }.count == 2)
    }

    @Test nonisolated func probeRecordsErrorsAndRawOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BluetoothDiagnostics(enabled: true, directory: root.appendingPathComponent("capture"))
        let output = BluetoothBatterySampler.probeProcessData(executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'raw-battery-zero'; printf 'permission-denied' >&2; exit 2"],
            diagnosticsSource: "fixture", diagnostics: store)
        #expect(output == nil)
        let exported = root.appendingPathComponent("out")
        try store.copyLogs(to: exported)
        let lines = try Data(contentsOf: exported.appendingPathComponent("bluetooth.0.jsonl")).split(separator: 0x0A)
        let log = try lines.map { try JSONSerialization.jsonObject(with: Data($0)) as! [String: Any] }
        let fields = try #require(log.first { $0["event"] as? String == "probe" }?["fields"] as? [String: Any])
        #expect(fields["status"] as? String == "failed")
        #expect(fields["exit"] as? Int == 2)
        #expect((fields["stdout"] as? [String: Any])?["value"] as? String == "raw-battery-zero")
        #expect((fields["stderr"] as? [String: Any])?["value"] as? String == "permission-denied")
    }
}
