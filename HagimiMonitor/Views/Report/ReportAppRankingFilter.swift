import Foundation

/// 应用排行的过滤、搜索与排序规则。
nonisolated enum ReportAppRankingFilter: Sendable {

    enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case value
        case peak
        case name

        var id: String { rawValue }

        var label: String {
            switch self {
            case .value: return String(localized: "stats.report.sort.value", defaultValue: "按占用")
            case .peak: return String(localized: "stats.report.sort.peak", defaultValue: "按峰值")
            case .name: return String(localized: "stats.report.sort.name", defaultValue: "按名称")
            }
        }
    }

    /// 应用系统过滤、搜索与排序。
    ///
    /// - Parameter includeSystemApps: 是否保留系统进程。
    /// - Parameter query: 用户输入的搜索词；空串表示不筛选。
    static func apply(
        to entries: [ReportAppRankingItem],
        includeSystemApps: Bool,
        query: String,
        sortOrder: SortOrder
    ) -> [ReportAppRankingItem] {
        let systemFiltered = includeSystemApps ? entries : entries.filter { !$0.isSystemApp }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = trimmed.isEmpty
            ? systemFiltered
            : systemFiltered.filter {
                $0.name.lowercased().contains(trimmed) || $0.appKey.lowercased().contains(trimmed)
            }

        switch sortOrder {
        case .value:
            return searched.sorted { $0.value > $1.value }
        case .peak:
            return searched.sorted { $0.peakValue > $1.peakValue }
        case .name:
            return searched.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// 默认折叠时展示的条数。
    static let collapsedLimit = 8
    /// 展开后分批渲染的批次大小。
    static let renderBatch = 50

    /// 计算当前可见的排行条目，保证深链聚焦的目标应用始终可见。
    ///
    /// - Parameter expandedLimit: 展开后最多渲染多少条；nil 表示全部。
    static func visible(
        entries: [ReportAppRankingItem],
        showsAll: Bool,
        focusedAppKey: String?,
        expandedLimit: Int? = nil
    ) -> [ReportAppRankingItem] {
        if showsAll {
            guard let expandedLimit else { return entries }
            var limited = Array(entries.prefix(max(1, expandedLimit)))
            // 确保聚焦的应用始终处于可见列表中。
            if let focusedAppKey,
               !limited.contains(where: { $0.appKey == focusedAppKey }),
               let target = entries.first(where: { $0.appKey == focusedAppKey }) {
                limited.insert(target, at: 0)
            }
            return limited
        }
        var visible = Array(entries.prefix(collapsedLimit))
        if let focusedAppKey,
           !visible.contains(where: { $0.appKey == focusedAppKey }),
           let target = entries.first(where: { $0.appKey == focusedAppKey }) {
            visible.insert(target, at: 0)
            if visible.count > collapsedLimit { visible.removeLast() }
        }
        return visible
    }
}
