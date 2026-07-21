import Foundation
import IOKit
import DiskArbitration
import OSLog

final class StorageSampler: MonitorSampler {
    var kind: MonitorKind { .storage }

    private var previousDiskIO: (bytesRead: Int64, bytesWritten: Int64, timestamp: Date)?

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
                MonitorMetric(name: "free", value: bytes(free), numericValue: free),
                MonitorMetric(name: "total", value: bytes(total))
            ]

            if let ioStats = readDiskIOStats() {
                metrics.append(MonitorMetric(name: "cumulativeBytesRead", value: "\(ioStats.bytesRead)"))
                metrics.append(MonitorMetric(name: "cumulativeBytesWritten", value: "\(ioStats.bytesWritten)"))

                // 瞬时读写速率（bytes/sec）
                let now = Date()
                if let prev = previousDiskIO {
                    let dt = max(0.1, now.timeIntervalSince(prev.timestamp))
                    let readRate = max(0, Double(ioStats.bytesRead - prev.bytesRead) / dt)
                    let writeRate = max(0, Double(ioStats.bytesWritten - prev.bytesWritten) / dt)
                    metrics.append(MonitorMetric(name: "disk-read-rate", value: bytesPerSecond(readRate), numericValue: readRate))
                    metrics.append(MonitorMetric(name: "disk-write-rate", value: bytesPerSecond(writeRate), numericValue: writeRate))
                }
                previousDiskIO = (ioStats.bytesRead, ioStats.bytesWritten, now)
            } else {
                AppLogger.sampler.warning("StorageSampler readDiskIOStats returned nil")
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
            return placeholderModule(.storage, summary: String(localized: "sampler.unavailable"))
        }
    }

    /// 通过 DiskArbitration + IORegistry 读取磁盘累计读写字节
    /// 使用与 Stats app 相同的方式：通过 BSD name 找到 IOMedia，向上遍历到父设备读取 Statistics
    private func readDiskIOStats() -> (bytesRead: Int64, bytesWritten: Int64)? {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }

        let rootURL = URL(fileURLWithPath: "/")
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, rootURL as CFURL),
              let bsdName = DADiskGetBSDName(disk) else { return nil }

        let bsdString = String(cString: bsdName)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdString))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        // 向上遍历找到包含 Statistics 的父设备
        var parent: io_registry_entry_t = 0
        var current = service
        for _ in 0..<5 {
            if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) != KERN_SUCCESS { break }
            if current != service { IOObjectRelease(current) }

            var propsRef: Unmanaged<CFMutableDictionary>? = nil
            if IORegistryEntryCreateCFProperties(parent, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let stats = props["Statistics"] as? [String: Any] {
                var totalRead: Int64 = 0
                var totalWritten: Int64 = 0
                if let read = stats["Bytes (Read)"] as? Int64 {
                    totalRead += read
                } else if let read = stats["Bytes (Read)"] as? NSNumber {
                    totalRead += read.int64Value
                }
                if let written = stats["Bytes (Write)"] as? Int64 {
                    totalWritten += written
                } else if let written = stats["Bytes (Write)"] as? NSNumber {
                    totalWritten += written.int64Value
                }
                if totalRead > 0 || totalWritten > 0 {
                    IOObjectRelease(parent)
                    return (totalRead, totalWritten)
                }
            }
            current = parent
        }
        if current != service { IOObjectRelease(current) }
        return nil
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
