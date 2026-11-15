// 只读诊断：同时记录原始 IOReport 计数、生产采样结果和显示器状态。
// 编译（仓库根目录）：
// swiftc -import-objc-header HagimiMonitorDirectOnly/DisplayBridgingHeader.h -lIOReport \
//   -framework IOKit -framework CoreGraphics HagimiMonitorDirectOnly/IOReportPowerSampler.swift \
//   HagimiMonitorDirectOnly/IOReportSubscription.swift HagimiMonitorDirectOnly/CLPCPowerChannels.swift \
//   HagimiMonitor/Samplers/PowerTelemetry.swift \
//   HagimiMonitor/Samplers/GPUClockState.swift scripts/validation/power-topology-probe.swift \
//   -o tmp/power-topology-audit/probe
// 运行：tmp/power-topology-audit/probe [样本数 2...600] [间隔秒 0.25...10]
// PRODUCTION_ONLY=1 仅运行生产采样，用于排除额外诊断订阅的影响。
import Foundation
import IOKit
import CoreGraphics

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

final class RawSubscription {
    let group: String
    let subscription: CFTypeRef
    let channels: CFMutableDictionary
    init?(_ group: String, subgroup: String?, accepts: (String) -> Bool) {
        self.group = group
        guard let source = IOReportCopyChannelsInGroup(group as CFString, subgroup as CFString?, 0, 0)?.takeRetainedValue(),
              let all = (source as NSDictionary)["IOReportChannels"] as? [NSDictionary],
              let requested = CFDictionaryCreateMutableCopy(nil, 0, source) else { return nil }
        let selected = all.filter {
            let name = IOReportChannelGetChannelName($0 as CFDictionary)?.takeUnretainedValue() as String? ?? ""
            return accepts(name)
        }
        for channel in selected {
            emit(["event": "discovered", "group": group, "metadata": Self.metadata(channel as CFDictionary)])
        }
        guard !selected.isEmpty else { return nil }
        let key = "IOReportChannels" as CFString
        let array = selected as CFArray
        CFDictionarySetValue(requested, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(array).toOpaque())
        var output: Unmanaged<CFMutableDictionary>?
        guard let subscription = IOReportCreateSubscription(nil, requested, &output, 0, nil)?.takeRetainedValue(),
              let channels = output?.takeRetainedValue() else { return nil }
        self.subscription = subscription
        self.channels = channels
    }
    static func metadata(_ channel: CFDictionary) -> [String: Any] {
        let dict = channel as NSDictionary
        return [
            "name": IOReportChannelGetChannelName(channel)?.takeUnretainedValue() as String? ?? "",
            "subgroup": IOReportChannelGetSubGroup(channel)?.takeUnretainedValue() as String? ?? "",
            "format": IOReportChannelGetFormat(channel),
            "unit": String(format: "%016llx", IOReportChannelGetUnit(channel)),
            "driver": dict["DriverName"] as? String ?? "",
            "driverID": String(describing: dict["DriverID"] ?? ""),
            "channelID": String(describing: (dict["LegendChannel"] as? [Any])?.first ?? ""),
            "rawElements": (dict["RawElements"] as? Data)?.map { String(format: "%02x", $0) }.joined() ?? ""
        ]
    }
    func sample(frame: Int) {
        guard let report = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue(),
              let values = (report as NSDictionary)["IOReportChannels"] as? [NSDictionary] else {
            emit(["event": "sample-failed", "group": group, "frame": frame]); return
        }
        for channel in values {
            var data = Self.metadata(channel as CFDictionary)
            data["counter"] = IOReportSimpleGetIntegerValue(channel as CFDictionary, 0)
            data["frame"] = frame
            data["uptime"] = ProcessInfo.processInfo.systemUptime
            data["event"] = "raw"
            data["group"] = group
            emit(data)
        }
    }
}

@main
struct PowerTopologyProbe {
    static func main() {
        let arguments = CommandLine.arguments
        let samples = arguments.count > 1 ? Int(arguments[1]) ?? 0 : 12
        let interval = arguments.count > 2 ? Double(arguments[2]) ?? 0 : 1.0
        guard (2...600).contains(samples), interval.isFinite, (0.25...10).contains(interval) else {
            emit(["event": "error", "message": "samples must be 2...600; interval must be 0.25...10 seconds"])
            exit(2)
        }
        func sysctlString(_ key: String) -> String {
            var size = 0
            guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return "unknown" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return "unknown" }
            return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        emit(["event": "hardware", "chip": sysctlString("machdep.cpu.brand_string"),
              "model": sysctlString("hw.model"), "samples": samples, "intervalSeconds": interval])
        emit(["event": "environment", "os": ProcessInfo.processInfo.operatingSystemVersionString])
        let rawEnabled = ProcessInfo.processInfo.environment["PRODUCTION_ONLY"] != "1"
        let display = rawEnabled ? RawSubscription("DCP", subgroup: "display stats") { $0 == "power" } : nil
        let energy = rawEnabled ? RawSubscription("Energy Model", subgroup: nil) {
            $0 == "CPU Energy" || $0 == "GPU Energy" || $0.hasPrefix("ANE")
        } : nil
        let clpc = rawEnabled ? IOReportSubscription.clpc() : nil
        emit(["event": "subscriptions", "rawEnabled": rawEnabled, "display": display != nil,
              "energy": energy != nil, "clpc": clpc != nil])
        if let clpc {
            for descriptor in clpc.expected.sorted(by: { $0.identity < $1.identity }) {
                emit(["event": "requested", "group": "CLPC", "name": descriptor.name,
                      "driverID": String(descriptor.driver), "channelID": String(format: "%016llx", descriptor.channel),
                      "format": descriptor.format, "unit": String(format: "%016llx", descriptor.unit)])
            }
        }
        for frame in 0..<samples {
            autoreleasepool {
                display?.sample(frame: frame)
                energy?.sample(frame: frame)
                // 与生产代码共用报告解析，原始源时间戳不以探针取样时间替代。
                if let clpc {
                    if let report = clpc.report(), let snapshot = clpc.snapshot(in: report, generation: 0) {
                        for record in snapshot.records {
                            emit(["event": "raw", "group": "CLPC", "frame": frame,
                                  "name": record.descriptor.name, "driverID": String(record.descriptor.driver),
                                  "channelID": String(format: "%016llx", record.descriptor.channel),
                                  "format": record.descriptor.format, "unit": String(format: "%016llx", record.descriptor.unit),
                                  "counter": record.value, "sourceTimestampTicks": record.timestamp,
                                  "continuousTime": IOReportPowerSampler.continuousTime])
                        }
                        emit(["event": "clpc-report", "frame": frame, "expectedCount": snapshot.expected.count,
                              "decodedCount": snapshot.records.count])
                    } else {
                        emit(["event": "sample-failed", "group": "CLPC", "frame": frame])
                    }
                }
                let sample = IOReportPowerSampler.shared.sample()
                func number(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }
                emit(["event": "production", "frame": frame,
                      "displayW": number(sample.displayWatts), "cpuW": number(sample.cpuWatts),
                      "gpuW": number(sample.gpuWatts), "aneW": number(sample.aneWatts)])
                for (name, reading) in sample.readings.sorted(by: { $0.key < $1.key }) {
                    emit(["event": "reading", "frame": frame, "name": name, "source": reading.source.rawValue,
                          "state": reading.state.rawValue, "identity": reading.identity,
                          "watts": number(reading.watts), "intervalStart": reading.intervalStart,
                          "intervalEnd": reading.intervalEnd])
                }
                var displays = [CGDirectDisplayID](repeating: 0, count: 16)
                var count: UInt32 = 0
                if CGGetOnlineDisplayList(16, &displays, &count) == .success {
                    emit(["event": "displays", "frame": frame, "screens": displays.prefix(Int(count)).map {
                        ["builtIn": CGDisplayIsBuiltin($0), "active": CGDisplayIsActive($0), "asleep": CGDisplayIsAsleep($0)]
                    }])
                }
            }
            if frame < samples - 1 { Thread.sleep(forTimeInterval: interval) }
        }
    }
}
