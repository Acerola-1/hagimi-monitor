import SwiftUI

/// 电源展开区分区多页切换标签（拓扑 / 健康 / 排名 / 供电）。
enum BatteryPageTab: String, CaseIterable, Identifiable {
    case flow = "flow"
    case health = "health"
    case ranking = "ranking"
    case supply = "supply"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flow:
            return String(localized: "panel.battery.tab.flow")
        case .health:
            return String(localized: "panel.battery.tab.health")
        case .ranking:
            return String(localized: "panel.battery.tab.ranking")
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
        case .ranking:
            return "list.number"
        case .supply:
            return "powerplug.fill"
        }
    }

    /// 设置页预览可选的分页:排名页的数据源(逐进程能耗)仅直连版产得出,
    /// 商店版既不产也不展示,避免预览出现面板永远不会出现的分页。
    static var previewCases: [BatteryPageTab] {
        #if DIRECT_DISTRIBUTION
        return allCases
        #else
        return allCases.filter { $0 != .ranking }
        #endif
    }

    /// 各分页归属的可勾指标名:面板展开区分栏渲染与设置页选项过滤同源。
    /// 供电页为固定诊断视图、排名页为固定列表,均不含可勾指标,返回空。
    var metricNames: [String] {
        switch self {
        case .flow:
            #if DIRECT_DISTRIBUTION
            return ["power", "display-power", "cpu-power", "gpu-power", "ane-power"]
            #else
            return ["power"]
            #endif
        case .health:
            return [
                "health", "cycle-count", "temperature", "power-loss",
                "voltage", "current", "cell-balance", "capacity",
                "cell-qmax", "cell-resistance", "thermal-limit-seconds", "time-at-high-soc"
            ]
        case .ranking, .supply:
            return []
        }
    }
}

// MARK: - 供电协议与输入诊断视图

/// 供电端专属诊断视图：一行一项的「标签 + 数值」，排版直接复用健康页同一套
/// `MetricDetailGrid`（逐格主题色块、标签左数值右），不自造网格。
///
/// 五行的整行登记与最坏值契约在 `StaticMetricSizing` 审计表里：这些值是
/// 「20V/3.25A/65W」「5/9/15/20V」这类长技术串，半格放不下，两语都按整行。
/// 只渲染本帧真实读到的行（缺失不占位）；未插电或缺失帧不铺五行 "--"，
/// 回落为单行状态文本。
struct PowerSupplyDiagnosticsView: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme

    /// 固定行序：端口 → PD 协议 → 可协商档位 → 同口通道 → 适配器输入。
    private static let rowOrder = [
        "adapter-port", "pd-contract", "pd-tiers", "adapter-transports", "input-telemetry"
    ]

    var body: some View {
        if isUnavailable || !connected {
            standaloneStatus(String(localized: "panel.battery.diag.disconnected"))
        } else if supplyMetrics.isEmpty {
            standaloneStatus("--")
        } else {
            MetricDetailGrid(
                metrics: supplyMetrics,
                kind: .battery,
                theme: theme,
                showsSeparator: false
            )
        }
    }

    /// 本帧读到的诊断行，按固定行序排列；值为 "--" 的行不占位。
    private var supplyMetrics: [MonitorMetric] {
        Self.rowOrder.compactMap { name in
            guard let metric = module.metrics.first(where: { $0.name == name }),
                  metric.value != "--" else { return nil }
            return metric
        }
    }

    /// 未连接 / 缺失态：单段状态文本，不铺空行。
    private func standaloneStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(theme.valueText)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.trackFill))
    }

    private var connected: Bool {
        let status = module.metrics.first { $0.name == "status" }?.value
        return status == "charging" || status == "ac-power" || status == "maintain"
    }

    /// 缺失帧(IOPS 接口不可信):供电状态未知,不宣称"未连接",状态相关字段显示 "--"。
    private var isUnavailable: Bool { module.isPlaceholder }
}
