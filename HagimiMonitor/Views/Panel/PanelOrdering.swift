import Foundation

/// 面板中彼此独立的排列范围。ID 不受当前可见性影响。
enum PanelOrderScope: Hashable {
    case modules
    case metrics(MonitorKind)
    case battery(BatteryPageTab)

    var storageKey: String {
        switch self {
        case .modules: "modules"
        case .metrics(let kind): "metrics.\(kind.rawValue)"
        case .battery(let page): "metrics.battery.\(page.rawValue)"
        }
    }

    var moduleKind: MonitorKind? {
        switch self {
        case .modules: nil
        case .metrics(let kind): kind
        case .battery: .battery
        }
    }
}

enum PanelOrderCatalog {
    static let displayID = "display"
    static let supplyIDs = [
        "adapter-port", "pd-contract", "pd-tiers", "adapter-transports", "input-telemetry"
    ]

    /// 内存压力主值模式只替换展示名；排序身份仍归属设置中的压力槽。
    static func stableMetricID(kind: MonitorKind, displayedName: String) -> String {
        kind == .memory && displayedName == "usage" ? "pressure" : displayedName
    }

    static var scopes: [PanelOrderScope] {
        [.modules] + MonitorKind.allCases.compactMap { kind in
            kind == .battery || kind == .fan || kind == .bluetooth ? nil : .metrics(kind)
        } + [.battery(.flow), .battery(.health), .battery(.supply)]
    }

    static func ids(for scope: PanelOrderScope) -> [String] {
        switch scope {
        case .modules:
            return MonitorKind.allCases.map(\.id) + [displayID]
        case .metrics(let kind):
            return kind.availableMetrics.map(\.id)
        case .battery(let page):
            if page == .supply { return supplyIDs }
            let names = Set(page.metricNames)
            return MonitorKind.battery.availableMetrics.map(\.id)
                .filter { names.contains($0) && $0 != "power-flow" }
        }
    }

    static func defaultIDs(for scope: PanelOrderScope) -> [String] {
        if scope == .battery(.supply) { return supplyIDs }
        if scope == .modules { return ids(for: scope) }
        let kind = scope.moduleKind!
        let candidates = ids(for: scope)
        let source = kind == .network
            ? networkDetailMetricOrder.filter { candidates.contains($0) }
                + candidates.filter { !networkDetailMetricOrder.contains($0) }
            : candidates
        #if DISPLAY_CONTROL
        let mergesThermal = kind == .cpu
        #else
        let mergesThermal = false
        #endif
        let short = source.filter {
            !StaticMetricSizing.isFullRow(kind: kind, name: $0)
                && !(mergesThermal && $0 == "thermal-pressure")
        }
        let thermal = mergesThermal && source.contains("thermal-pressure")
            ? ["thermal-pressure"] : []
        let full = source.filter {
            StaticMetricSizing.isFullRow(kind: kind, name: $0)
                && !(mergesThermal && $0 == "thermal-pressure")
        }
        // 逐核展示替代 core-split 指标格时沿用同一个 ID；默认仍位于网格顶部。
        if kind == .cpu, candidates.contains("core-split") {
            return ["core-split"] + (short + thermal + full).filter { $0 != "core-split" }
        }
        return short + thermal + full
    }
}

/// 保存完整 ID 顺序，当前不可见项目仅在投影时过滤。
enum PanelOrderList {
    static func reconciled(_ stored: [String]?, defaults: [String]) -> [String] {
        guard let stored else { return defaults }
        var result: [String] = []
        var seen = Set<String>()
        for id in stored where seen.insert(id).inserted { result.append(id) }

        for (index, id) in defaults.enumerated() where !seen.contains(id) {
            let successors = defaults.dropFirst(index + 1)
            if let successor = successors.first(where: { seen.contains($0) }),
               let insertion = result.firstIndex(of: successor) {
                result.insert(id, at: insertion)
            } else if let predecessor = defaults[..<index].reversed().first(where: { seen.contains($0) }),
                      let insertion = result.firstIndex(of: predecessor) {
                result.insert(id, at: insertion + 1)
            } else {
                result.append(id)
            }
            seen.insert(id)
        }
        return result
    }

    static func visible(_ order: [String], available: [String]) -> [String] {
        let availableIDs = Set(available)
        return order.filter { availableIDs.contains($0) }
    }

    /// 在当前可见项目之间移动，但保存结果仍包含隐藏 ID。
    static func moved(_ fullOrder: [String], id: String, before target: String?, visible: [String]) -> [String]? {
        guard visible.contains(id), fullOrder.contains(id) else { return nil }
        if let target, (!visible.contains(target) || target == id) { return nil }
        var result = fullOrder
        result.removeAll { $0 == id }
        if let target {
            guard let index = result.firstIndex(of: target) else { return nil }
            result.insert(id, at: index)
        } else if let lastVisible = visible.reversed().first(where: { $0 != id }),
                  let index = result.firstIndex(of: lastVisible) {
            result.insert(id, at: index + 1)
        } else {
            result.append(id)
        }
        return result == fullOrder ? nil : result
    }
}
