import SwiftUI

/// 显示层只整理实测功率与缺失状态，不用输入和负载的瞬时差值重算电池功率。
nonisolated struct PowerReadings {
    let module: MonitorModule

    var connected: Bool {
        !module.isPlaceholder && ["charging", "ac-power", "maintain"].contains(status)
    }

    var status: String { module.metrics.first { $0.name == "status" }?.value ?? "unknown" }

    var inputText: String {
        connected ? watts("power-in").map { wattString($0) } ?? "—" : "—"
    }

    var loadText: String { watts("power").map { wattString($0) } ?? "—" }

    var batteryText: String? {
        guard !module.isPlaceholder else { return nil }
        switch status {
        case "charging":
            return (watts("battery-flow") ?? watts("charging-power")).map { wattString($0) } ?? "—"
        case "on-battery":
            return (watts("battery-flow") ?? watts("power")).map { wattString($0) } ?? "—"
        case "maintain":
            return watts("battery-flow").map { wattString($0) } ?? "—"
        default:
            return nil
        }
    }

    private func watts(_ name: String) -> Double? {
        guard !module.isPlaceholder,
              let value = module.metrics.first(where: { $0.name == name })?.numericValue,
              value.isFinite else { return nil }
        let magnitude = name == "battery-flow" ? abs(value) : value
        return magnitude >= 0.05 ? magnitude : nil
    }
}

/// 标签和值分两行，复用网络胶囊的横向槽位，不挤占模块名称与电量。
struct PowerHeaderPills: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme

    private var readings: PowerReadings { PowerReadings(module: module) }
    private var hasBattery: Bool { module.metrics.first { $0.name == "type" }?.value == "battery" }

    var body: some View {
        HStack(spacing: RowHeaderPillMetrics.spacing) {
            if hasBattery || module.metrics.contains(where: { $0.name == "power-in" && $0.numericValue != nil }) {
                MetricLabelPill(title: String(localized: "panel.power.input"), value: readings.inputText, theme: theme)
                    .help(readings.connected
                        ? String(localized: "panel.power.input-help")
                        : String(localized: "panel.power.disconnected-help"))
            }
            if hasBattery || module.metrics.contains(where: { $0.name == "power" && $0.numericValue != nil }) {
                MetricLabelPill(title: String(localized: "panel.power.load"), value: readings.loadText, theme: theme)
                    .help(String(localized: "panel.power.load-help"))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
