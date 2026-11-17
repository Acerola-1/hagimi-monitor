import SwiftUI

/// 普通明细格的宽度偏好；自动最多两列，手动选择始终优先。
nonisolated enum PanelMetricWidth: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case half
    case full

    var id: String { rawValue }
    var span: Int {
        switch self {
        case .automatic: 0
        case .half: 1
        case .full: 2
        }
    }

    @MainActor var title: String {
        switch self {
        case .automatic: String(localized: "panel.metric-width.automatic")
        case .half: String(localized: "panel.metric-width.half")
        case .full: String(localized: "panel.metric-width.full")
        }
    }

    @MainActor static func key(kind: MonitorKind, id: String) -> String {
        "\(kind.rawValue).\(PanelOrderCatalog.stableMetricID(kind: kind, displayedName: id))"
    }

    @MainActor static func supports(kind: MonitorKind, id: String) -> Bool {
        !(kind == .cpu && id == "core-split") && id != "power-flow"
    }
}

private struct PanelMetricWidthsKey: EnvironmentKey {
    static let defaultValue: [String: PanelMetricWidth] = [:]
}

extension EnvironmentValues {
    var panelMetricWidths: [String: PanelMetricWidth] {
        get { self[PanelMetricWidthsKey.self] }
        set { self[PanelMetricWidthsKey.self] = newValue }
    }
}

/// 同一宽度与字体环境中只增加自动格的宽度预算，避免读数来回变化时反复换行。
nonisolated struct MetricWidthResolution {
    struct Item {
        let id: String
        let span: Int
        let idealWidth: CGFloat
    }
    private var width: CGFloat?
    private var environment = ""
    private var largestWidths: [String: CGFloat] = [:]
    private var policies: [String: Int] = [:]

    mutating func spans(for items: [Item], width: CGFloat, environment: String) -> [Int] {
        if self.width != width || self.environment != environment {
            largestWidths.removeAll()
            policies.removeAll()
            self.width = width
            self.environment = environment
        }
        let ids = Set(items.map(\.id))
        largestWidths = largestWidths.filter { ids.contains($0.key) }
        policies = policies.filter { ids.contains($0.key) }
        let halfWidth = max(0, (width - MetricGridMetrics.columnSpacing) / 2)
        return items.map { item in
            if policies[item.id] != item.span { largestWidths.removeValue(forKey: item.id) }
            policies[item.id] = item.span
            if item.span == 1 || item.span == 2 { return item.span }
            let measured = item.idealWidth.isFinite ? ceil(max(0, item.idealWidth)) : width
            let required = max(largestWidths[item.id] ?? 0, measured)
            largestWidths[item.id] = required
            return required <= halfWidth ? 1 : 2
        }
    }
}

/// 设置页与卡片右键菜单共用的宽度选项。
struct PanelMetricWidthPicker: View {
    @ObservedObject var settings: MonitorSettings
    let kind: MonitorKind
    let id: String

    var body: some View {
        Picker(String(localized: "panel.metric-width.title"), selection: Binding(
            get: { settings.panelMetricWidth(for: kind, id: id) },
            set: { settings.setPanelMetricWidth($0, for: kind, id: id) }
        )) {
            ForEach(PanelMetricWidth.allCases) { width in
                Text(width.title).tag(width)
            }
        }
    }
}
