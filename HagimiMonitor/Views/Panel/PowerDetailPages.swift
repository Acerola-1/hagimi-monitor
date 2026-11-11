import SwiftUI

/// 电源展开区分区多页切换标签（健康 / 拓扑 / 供电），耗电 TOP 属于分页外的公共明细。
enum BatteryPageTab: String, CaseIterable, Identifiable {
    case health = "health"
    case flow = "flow"
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

    /// 设置页预览可选的分页:拓扑页(分项功耗)仅直连版
    /// 产得出,商店版既不产也不展示,避免预览出现面板永远不会出现的分页。
    static var previewCases: [BatteryPageTab] {
        #if DIRECT_DISTRIBUTION
        return allCases
        #else
        return allCases.filter { $0 != .flow }
        #endif
    }

    /// 各分页归属的可勾指标名:面板展开区分栏渲染与设置页选项过滤同源。
    /// 「功率流」是网格外可视化选项(无采样指标),归入承载流向图的分页:
    /// 直连版在拓扑页、沙盒版在健康页。供电页为固定诊断视图,不含可勾指标。
    var metricNames: [String] {
        switch self {
        case .flow:
            #if DIRECT_DISTRIBUTION
            return ["power", "display-power", "cpu-power", "gpu-power", "ane-power", "power-flow"]
            #else
            return ["power"]
            #endif
        case .health:
            var names = [
                "health", "cycle-count", "temperature", "power-loss",
                "voltage", "current", "cell-balance", "capacity",
                "cell-qmax", "cell-resistance", "thermal-limit-seconds", "time-at-high-soc"
            ]
            #if !DIRECT_DISTRIBUTION
            names.append("power-flow")
            #endif
            return names
        case .supply:
            return []
        }
    }
}

/// 二级导航沿用明细字体与内衬；原生按钮处理激活，分段语义供辅助技术操作。
struct PowerPagePicker: View {
    @Binding var selection: BatteryPageTab
    let items: [BatteryPageTab]
    let theme: MonitorPanelTheme
    @FocusState private var isFocused: Bool
    @State private var hoveredPage: BatteryPageTab?
    @State private var suppressFocusRing = false
    @Environment(\.colorSchemeContrast) private var contrast

    private static let inset: CGFloat = 2
    private static let segmentRadius = CGFloat(MonitorConstants.rowCornerRadius / 2)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { page in
                let selected = page == selection
                Button {
                    suppressFocusRing = true
                    if !isFocused { isFocused = true }
                    select(page)
                } label: {
                    Text(page.title)
                        .monitorPanelCaptionFont(.caption2, weight: selected ? .semibold : .medium)
                        .foregroundStyle(selected ? theme.valueText : theme.captionText)
                        .fixedSize()
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background {
                            RoundedRectangle(cornerRadius: Self.segmentRadius)
                                .fill(selected ? theme.badgeFill(for: .battery)
                                      : hoveredPage == page ? theme.trackFill : .clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.segmentRadius)
                                .strokeBorder(outline(for: page), lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(page.title)
                .onHover { hovering in
                    if hovering { hoveredPage = page }
                    else if hoveredPage == page { hoveredPage = nil }
                }
            }
        }
        .padding(Self.inset)
        .background {
            RoundedRectangle(cornerRadius: Self.segmentRadius + Self.inset)
                .fill(theme.trackFill.opacity(contrast == .increased ? 1 : 0.45))
        }
        .focusable(interactions: .edit)
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: isFocused) { _, focused in
            if !focused { suppressFocusRing = false }
        }
        .onKeyPress(.leftArrow) { moveSelection(by: -1) ? .handled : .ignored }
        .onKeyPress(.rightArrow) { moveSelection(by: 1) ? .handled : .ignored }
        .accessibilityRepresentation {
            Picker(String(localized: "panel.power-pages"), selection: Binding(
                get: { selection }, set: { select($0) }
            )) {
                ForEach(items) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func outline(for page: BatteryPageTab) -> Color {
        guard selection == page else { return .clear }
        if isFocused && !suppressFocusRing { return theme.moduleTint(for: .battery) }
        return contrast == .increased ? theme.valueText : .clear
    }

    private func select(_ page: BatteryPageTab) {
        guard selection != page else { return }
        withPanelExpansionState { selection = page }
    }

    private func moveSelection(by offset: Int) -> Bool {
        guard isFocused, let index = items.firstIndex(of: selection) else { return false }
        suppressFocusRing = false
        let next = index + offset
        guard items.indices.contains(next) else { return true }
        select(items[next])
        return true
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
    var metricOrder: [String] = []

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
                metricOrder: metricOrder,
                orderScope: .battery(.supply),
                showsSeparator: false
            )
        }
    }

    /// 本帧读到的诊断行先按默认行序取出，再由指标网格应用保存顺序；缺失行不占位。
    private var supplyMetrics: [MonitorMetric] {
        PanelOrderCatalog.supplyIDs.compactMap { name in
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
