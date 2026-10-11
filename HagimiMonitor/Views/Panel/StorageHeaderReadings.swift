import SwiftUI

/// 主行消费完整采样指标，不受展开区指标开关影响。
nonisolated enum StorageHeaderReadings {
    static func rate(_ module: MonitorModule, key: String) -> String {
        guard !module.isPlaceholder,
              let rate = module.metrics.first(where: { $0.name == key })?.numericValue,
              rate.isFinite, rate >= 0 else { return "—" }
        return bytesPerSecond(rate)
    }

    static func hasRates(_ module: MonitorModule) -> Bool {
        !module.isPlaceholder && ["disk-read-rate", "disk-write-rate"].contains { key in
            module.metrics.contains { $0.name == key && ($0.numericValue.map { $0.isFinite && $0 >= 0 } ?? false) }
        }
    }

    static func freeSpace(_ module: MonitorModule) -> String {
        guard !module.isPlaceholder else { return "—" }
        return module.metrics.first { $0.name == "free" }?.value ?? "—"
    }

    static func accessibilityValue(_ module: MonitorModule, summary: String) -> String {
        guard hasRates(module) else {
            return "\(summary), \(String(localized: "panel.storage.available")) \(freeSpace(module))"
        }
        return "\(summary), \(String(localized: "panel.storage.read")) \(rate(module, key: "disk-read-rate")), \(String(localized: "panel.storage.write")) \(rate(module, key: "disk-write-rate"))"
    }
}

struct StorageHeaderPills: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme

    /// 设置预览只构造视图输入，不注入实际采样或统计记录。
    static var previewModule: MonitorModule {
        MonitorModule(kind: .storage, value: 68, summary: "68%", metrics: [
            MonitorMetric(name: "disk-read-rate", value: "", numericValue: 12_000_000),
            MonitorMetric(name: "disk-write-rate", value: "", numericValue: 4_000_000)
        ], samples: [])
    }

    var body: some View {
        PairedHeaderReadings(theme: theme) {
            if StorageHeaderReadings.hasRates(module) {
                MetricLabelPill(title: String(localized: "panel.storage.read"),
                                value: StorageHeaderReadings.rate(module, key: "disk-read-rate"), theme: theme)
                MetricLabelPill(title: String(localized: "panel.storage.write"),
                                value: StorageHeaderReadings.rate(module, key: "disk-write-rate"), theme: theme)
            } else {
                MetricLabelPill(title: String(localized: "panel.storage.available"),
                                value: StorageHeaderReadings.freeSpace(module), theme: theme)
            }
        }
    }
}
