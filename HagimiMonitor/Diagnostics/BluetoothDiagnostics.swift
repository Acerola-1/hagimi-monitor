import Foundation
import CoreBluetooth

/// 仅诊断测试包开启。数据在本机串行写入，随用户主动导出带走，不发送到网络。
nonisolated final class BluetoothDiagnostics: @unchecked Sendable {
    static let shared = BluetoothDiagnostics(
        enabled: isEnabled(Bundle.main.object(forInfoDictionaryKey: "HagimiBluetoothDiagnosticsEnabled"))
    )
    static func isEnabled(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let text = value as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return false
    }
    let enabled: Bool
    private let directory: URL
    private let queue = DispatchQueue(label: "com.acerola.hagimi-monitor.bluetooth-diagnostics", qos: .utility)
    private let session = UUID().uuidString
    private let maxFileSize: Int
    private let retainedFiles: Int
    private var sequence = 0
    private var previous: [String: (Data, Date)] = [:]

    init(enabled: Bool, directory: URL? = nil, maxFileSize: Int = 16 * 1024 * 1024, retainedFiles: Int = 4) {
        self.enabled = enabled
        self.directory = directory ?? DiagnosticsDirectories.applicationSupport.appendingPathComponent("BluetoothDiagnostics", isDirectory: true)
        self.maxFileSize = max(1, maxFileSize)
        self.retainedFiles = max(1, retainedFiles)
        if enabled {
            #if DIRECT_DISTRIBUTION
            let channel = "direct"
            #else
            let channel = "app-store-sandbox"
            #endif
            record("session", fields: [
                "channel": channel, "bundleID": Bundle.main.bundleIdentifier ?? "unknown",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "schema": 1, "maxFileBytes": self.maxFileSize, "retainedFiles": self.retainedFiles
            ])
        }
    }

    /// 将广播中的 Data/CBUUID（包括 UUID 作键的服务数据）转为可逆的 JSON 值。
    static func advertisement(_ value: Any) -> Any {
        switch value {
        case let data as Data: return ["encoding": "hex", "bytes": data.count, "value": data.map { String(format: "%02x", $0) }.joined()]
        case let uuid as CBUUID: return uuid.uuidString
        case let dictionary as [CBUUID: Data]:
            return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.uuidString, advertisement($0.value)) })
        case let dictionary as [String: Any]: return dictionary.mapValues(advertisement)
        case let array as [Any]: return array.map(advertisement)
        case let text as String: return text
        case let number as NSNumber: return number
        default: return String(describing: value)
        }
    }

    /// 原始负载保留到 2 MiB；截断时明确报告，避免无界磁盘与内存占用。
    static func raw(_ data: Data?) -> [String: Any] {
        guard let data else { return ["present": false] }
        let prefix = data.prefix(2 * 1024 * 1024)
        return ["present": true, "bytes": data.count, "truncated": prefix.count != data.count,
                "encoding": String(data: prefix, encoding: .utf8) == nil ? "base64" : "utf8",
                "value": String(data: prefix, encoding: .utf8) ?? Data(prefix).base64EncodedString()]
    }

    /// 区分未开放标准电池服务与服务发现失败，避免把缺少电量误解为没有发现设备。
    static func batteryServiceStatus(serviceUUIDs: [String], error: String?) -> [String: Any] {
        let available = serviceUUIDs.contains("180F")
        return ["standardService": "180F", "standardCharacteristic": "2A19",
                "available": error == nil ? available as Any : NSNull(),
                "reason": error != nil ? "service-discovery-failed" : available ? "battery-service-exposed" : "battery-service-not-exposed",
                "error": error as Any? ?? NSNull()]
    }

    func record(_ event: String, fields: [String: Any] = [:], deduplicate: Bool = false) {
        guard enabled,
              let payload = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .fragmentsAllowed]) else { return }
        let at = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            if deduplicate, let (old, last) = previous[event], old == payload, at.timeIntervalSince(last) < 60 { return }
            if deduplicate { previous[event] = (payload, at) }
            sequence += 1
            let entry: [String: Any] = [
                "event": event, "session": session, "sequence": sequence,
                "timestamp": ISO8601DateFormatter().string(from: at), "unixTime": at.timeIntervalSince1970,
                "uptime": uptime, "fields": (try? JSONSerialization.jsonObject(with: payload)) ?? [:]
            ]
            guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
            line.append(0x0A)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let current = file(0)
                let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size + line.count > maxFileSize {
                    try? FileManager.default.removeItem(at: file(retainedFiles - 1))
                    if retainedFiles > 1 {
                        for index in stride(from: retainedFiles - 2, through: 0, by: -1) where FileManager.default.fileExists(atPath: file(index).path) {
                            try FileManager.default.moveItem(at: file(index), to: file(index + 1))
                        }
                    }
                }
                if !FileManager.default.fileExists(atPath: current.path) { _ = FileManager.default.createFile(atPath: current.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: current)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                AppLogStore.shared.warning("Bluetooth diagnostics write failed: \(error.localizedDescription)", category: "bluetooth")
            }
        }
    }

    private func file(_ index: Int) -> URL { directory.appendingPathComponent("bluetooth.\(index).jsonl") }

    /// 与写入/轮转共用队列，在导出瞬间复制，避免正在轮转的文件集合不一致。
    func copyLogs(to destination: URL) throws {
        guard enabled else { return }
        try queue.sync {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for index in 0..<retainedFiles where FileManager.default.fileExists(atPath: file(index).path) {
                try FileManager.default.copyItem(at: file(index), to: destination.appendingPathComponent(file(index).lastPathComponent))
            }
        }
    }

    static func devices(_ devices: [BluetoothDeviceInfo]) -> [[String: Any]] {
        devices.map { device in [
            "address": device.address, "name": device.name, "type": String(describing: device.type),
            "level": device.batteryLevel as Any? ?? NSNull(),
            "source": device.batterySource.map { String(describing: $0) } ?? "none",
            "charging": device.isCharging as Any? ?? NSNull(), "services": device.services as Any? ?? NSNull(),
            "vendor": device.vendorName as Any? ?? NSNull(), "model": device.modelName as Any? ?? NSNull(),
            "components": device.components.map { ["kind": $0.kind.rawValue, "level": $0.level,
                                                   "charging": $0.isCharging as Any? ?? NSNull()] as [String: Any] }
        ] }
    }
}
