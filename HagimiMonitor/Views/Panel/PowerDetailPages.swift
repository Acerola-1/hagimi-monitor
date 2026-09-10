import SwiftUI

/// 电源展开区分区多页切换标签（拓扑 / 健康 / 供电）。
enum BatteryPageTab: String, CaseIterable, Identifiable {
    case flow = "flow"
    case health = "health"
    case supply = "supply"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow:
            return String(localized: "panel.battery.tab.flow")
        case .health:
            return String(localized: "panel.battery.tab.health")
        case .supply:
            return String(localized: "panel.battery.tab.supply")
        }
    }

    var icon: String {
        switch self {
        case .flow:
            return "point.3.connected.trianglepath.dotted"
        case .health:
            return "heart.fill"
        case .supply:
            return "powerplug.fill"
        }
    }

    /// 各分页归属的可勾指标名:面板展开区分栏渲染与设置页选项过滤同源。
    /// 供电页为固定诊断视图,不含可勾指标,返回空。
    var metricNames: [String] {
        switch self {
        case .flow:
            #if DIRECT_DISTRIBUTION
            return ["power", "display-power", "gpu-power"]
            #else
            return ["power"]
            #endif
        case .health:
            return [
                "health", "cycle-count", "temperature", "power-loss",
                "voltage", "current", "cell-balance", "capacity",
                "cell-qmax", "cell-resistance", "thermal-limit-seconds", "time-at-high-soc"
            ]
        case .supply:
            return []
        }
    }
}

// MARK: - 供电协议与输入诊断视图

/// 供电端专属诊断视图（双卡片整行排版，全宽对称对齐，杜绝文本截断）。
struct PowerSupplyDiagnosticsView: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            // 卡片 1: 充电源硬件与握手协议
            adapterCard

            // 卡片 2: 适配器输入实测（单行卡片）
            inputCard
        }
    }

    // MARK: - 子卡片

    private var adapterCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(connected ? tint : theme.captionText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(connected ? theme.badgeFill(for: .battery) : theme.palette.trackFill)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(String(localized: "panel.battery.diag.adapter"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.captionText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(adapterValue)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.valueText)
                        .lineLimit(1)
                }

                HStack {
                    Text(String(localized: "panel.battery.diag.pd-contract"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.captionText.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(pdContractValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.trackFill)
        )
    }

    private var inputCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(connected ? tint : theme.captionText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(connected ? theme.badgeFill(for: .battery) : theme.palette.trackFill)
                )

            Text(String(localized: "panel.battery.diag.input-bus"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.captionText)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(telemetryValue)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.trackFill)
        )
    }

    // MARK: - 数据读取与格式化

    private var connected: Bool {
        let s = metric("status")
        return s == "charging" || s == "ac-power" || s == "maintain"
    }

    /// 缺失帧(IOPS 接口不可信):供电状态未知,不宣称"未连接",状态相关字段显示 "--"。
    private var isUnavailable: Bool { module.isPlaceholder }

    private var adapterValue: String {
        guard connected else {
            return isUnavailable ? "--" : String(localized: "panel.battery.diag.disconnected")
        }
        let watts = metric("adapter")
        return watts != "--" ? watts : "--"
    }

    /// PD 协议握手档位：移除末尾冗余的功率括号（如 "(65W)"），因为上方第一行已展示该瓦数。
    private var pdContractValue: String {
        guard connected else { return "--" }
        let contract = metric("pd-contract")
        guard contract != "--" else { return "--" }
        if let parenIdx = contract.firstIndex(of: "(") {
            return String(contract[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        }
        return contract
    }

    private var telemetryValue: String {
        guard connected else { return "--" }
        let telem = metric("input-telemetry")
        if telem != "--" { return telem }
        let v = metric("input-voltage")
        let c = metric("input-current")
        if v != "--" && c != "--" { return "\(v) · \(c)" }
        return "--"
    }

    private func metric(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}
