import AppKit
import Combine
import Foundation
import OSLog

final class AuditSettings {
    @Published var statisticsEnabled = true
    @Published var alertNotificationsEnabled = false
}
final class MonitorStore { let settings = AuditSettings() }
enum ProcessIconCache {
    static func fullSizePNG(forPID: pid_t, sidePixels: Int) -> Data? { nil }
    static func fullSizePNG(forBundleIdentifier: String, sidePixels: Int) -> Data? { nil }
}
enum PressureAlertCenter { static let notificationCategory = "audit" }
enum AppLogger { static let sampler = Logger(subsystem: "audit", category: "audit") }

let center = ProcessAlertCenter.shared
let base = Date(timeIntervalSince1970: 1_790_000_000)
func cpu(_ offset: Double, _ usage: Double) {
    center.ingest(cpu: [("AuditCPU", 0, usage)], memory: [], gpu: [], network: [], at: base.addingTimeInterval(offset))
}
cpu(0, 70)
cpu(60, 70)
print("two_samples_elapsed_60s_reported_minutes=\(center.activeAlerts.first?.durationMinutes ?? -1)")
cpu(3600, 70)
print("after_59_minute_gap_start_preserved=\(center.activeAlerts.first?.startedAt == base), reported_minutes=\(center.activeAlerts.first?.durationMinutes ?? -1)")
center.reset()
for offset in [0.0, 60.0] {
    center.ingest(cpu: [], memory: [], gpu: [], network: [("AuditNetwork", 0, 1_048_576.0 * 60, 0)], at: base.addingTimeInterval(offset))
}
print("true_1MiB_per_second_network_alerts=\(center.activeAlerts.count), shown_average=\(center.activeAlerts.first?.averageUsage ?? -1)")
