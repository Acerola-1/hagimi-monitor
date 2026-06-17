import Foundation
import IOKit
import OSLog

final class StorageSampler: MonitorSampler {
    var kind: MonitorKind { .storage }

    func sample(previous: MonitorModule?) -> MonitorModule {
        do {
            let rootURL = URL(fileURLWithPath: "/")
            let values = try rootURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = Double(values.volumeTotalCapacity ?? Int((attributes[.systemSize] as? NSNumber)?.int64Value ?? 0))
            let free = Double(values.volumeAvailableCapacity ?? Int((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0))
            let used = max(0, total - free)
            let percentage = total > 0 ? (used / total) * 100 : 0

            var metrics = [
                MonitorMetric(name: "used", value: bytes(used)),
                MonitorMetric(name: "free", value: bytes(free)),
                MonitorMetric(name: "total", value: bytes(total))
            ]

            if let ioStats = readDiskIOStats() {
                metrics.append(MonitorMetric(name: "cumulativeBytesRead", value: "\(ioStats.bytesRead)"))
                metrics.append(MonitorMetric(name: "cumulativeBytesWritten", value: "\(ioStats.bytesWritten)"))
            }

            return MonitorModule(
                kind: .storage,
                context: externalVolumesJSON(),
                value: percentage,
                summary: percent(percentage),
                metrics: metrics,
                samples: seedSamples(percentage)
            )
        } catch {
            AppLogger.sampler.error("StorageSampler failed to read storage info: \(error.localizedDescription, privacy: .public)")
            return placeholderModule(.storage, summary: "无法读取")
        }
    }

    /// 从 IOBlockStorageDriver 读取磁盘累计读写字节
    private func readDiskIOStats() -> (bytesRead: Int64, bytesWritten: Int64)? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: Int64 = 0
        var totalWritten: Int64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            if let properties = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let read = properties["Bytes (Read)"] as? Int64 {
                    totalRead += read
                } else if let read = properties["Bytes (Read)"] as? NSNumber {
                    totalRead += read.int64Value
                }
                if let written = properties["Bytes (Written)"] as? Int64 {
                    totalWritten += written
                } else if let written = properties["Bytes (Written)"] as? NSNumber {
                    totalWritten += written.int64Value
                }
            }
            service = IOIteratorNext(iterator)
        }

        return (bytesRead: totalRead, bytesWritten: totalWritten)
    }

    private func externalVolumesJSON() -> String? {
        let volumes = detectExternalVolumes()
        guard !volumes.isEmpty else { return nil }

        let payload = volumes.map { vol in
            let pct = vol.total > 0 ? Int((vol.used / vol.total * 100).rounded()) : 0
            return ExternalVolumePayload(
                name: vol.name,
                used: bytes(vol.used),
                free: bytes(vol.free),
                total: bytes(vol.total),
                percentage: pct
            )
        }

        guard let data = try? JSONEncoder().encode(payload) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func detectExternalVolumes() -> [ExternalVolume] {
        guard let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey], options: []) else {
            return []
        }

        var volumes: [ExternalVolume] = []
        for url in volumeURLs {
            guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey]),
                  let totalCapacity = values.volumeTotalCapacity,
                  let availableCapacity = values.volumeAvailableCapacity,
                  let name = values.volumeName,
                  // 用 volumeIsInternalKey == false 检测外置卷，比 removable 更准确
                  values.volumeIsInternal == false else {
                continue
            }

            let total = Double(totalCapacity)
            let free = Double(availableCapacity)
            let used = max(0, total - free)

            guard total > 0 else { continue }

            volumes.append(ExternalVolume(name: name, used: used, free: free, total: total))
        }

        // 最多 3 个，避免撑高面板
        return Array(volumes.prefix(3))
    }
}

private struct ExternalVolume {
    let name: String
    let used: Double
    let free: Double
    let total: Double
}

private struct ExternalVolumePayload: Encodable {
    let name: String
    let used: String
    let free: String
    let total: String
    let percentage: Int
}
