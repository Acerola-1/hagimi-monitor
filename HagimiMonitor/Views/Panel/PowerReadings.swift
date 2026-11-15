import SwiftUI

/// 占位电池的独立功率仅由拓扑页展示；主读数与统计沿用占位模块过滤。
nonisolated struct BatteryPowerPresentation {
    static let independentNames: Set<String> = ["display-power", "cpu-power", "gpu-power", "ane-power"]
    let module: MonitorModule
    let enabledNames: Set<String>

    func metrics(for tab: BatteryPageTab) -> [MonitorMetric] {
        if module.isPlaceholder && tab != .flow { return [] }
        return tab.metricNames.compactMap { name in
            guard enabledNames.contains(name),
                  !module.isPlaceholder || Self.independentNames.contains(name),
                  let metric = module.metrics.first(where: { $0.name == name }) else { return nil }
            return metric
        }
    }

    func tabs(showPowerFlow: Bool) -> [BatteryPageTab] {
        if module.isPlaceholder {
            #if DIRECT_DISTRIBUTION
            return metrics(for: .flow).isEmpty ? [] : [.flow]
            #else
            return []
            #endif
        }
        var tabs: [BatteryPageTab] = []
        if module.metrics.contains(where: { $0.name == "type" && $0.value == "battery" }) { tabs.append(.health) }
        #if DIRECT_DISTRIBUTION
        if !metrics(for: .flow).isEmpty || (showPowerFlow && module.metrics.contains(where: { $0.name == "power" && $0.numericValue != nil })) {
            tabs.append(.flow)
        }
        #endif
        tabs.append(.supply)
        return tabs
    }
}

enum PowerReadingPresentation {
    static func help(_ reading: PowerReading?) -> String? {
        guard let reading else { return nil }
        switch reading.state {
        case .warmingUp: return String(localized: "power-reading.warming-up")
        case .unavailable: return String(localized: "power-reading.unavailable")
        case .frozen: return String(localized: "power-reading.frozen")
        case .unsupported: return String(localized: "power-reading.unsupported")
        case .unverified: return String(localized: "power-reading.unverified")
        case .valid:
            if reading.source == .derived { return String(localized: "power-reading.estimated") }
            if reading.interval > 0 {
                return String(format: String(localized: "power-reading.interval"), reading.interval)
            }
            return String(localized: "power-reading.reported")
        }
    }
}

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
        return magnitude >= 0 ? magnitude : nil
    }
}

/// 标签和值分两行，与网络共用读数分组，不挤占模块名称与电量。
struct PowerHeaderPills: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme

    private var readings: PowerReadings { PowerReadings(module: module) }
    private var hasBattery: Bool { module.metrics.first { $0.name == "type" }?.value == "battery" }

    var body: some View {
        PairedHeaderReadings(theme: theme) {
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
    }
}
