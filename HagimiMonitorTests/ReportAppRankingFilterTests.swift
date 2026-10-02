import Foundation
import Testing
@testable import HagimiMonitorDirect

/// U04：完整已记录列表、可切换排序、搜索与清除、系统过滤，不受前八项限制。
struct ReportAppRankingFilterTests {
    private func item(
        _ key: String,
        name: String? = nil,
        value: Double,
        peak: Double? = nil
    ) -> ReportAppRankingItem {
        ReportAppRankingItem(
            id: key,
            appKey: key,
            name: name ?? key,
            value: value,
            peakValue: peak ?? value,
            valueText: "\(value)",
            tierHint: nil,
            iconData: nil
        )
    }

    @Test func moreThanEightAppsRemainAccessible() {
        let entries = (1...30).map { item("app\($0)", value: Double(31 - $0)) }
        let all = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: true, query: "", sortOrder: .value)
        // 数据层不再截断，30 个应用全部保留。
        #expect(all.count == 30)

        let collapsed = ReportAppRankingFilter.visible(entries: all, showsAll: false, focusedAppKey: nil)
        #expect(collapsed.count == 8)
        #expect(collapsed.first?.appKey == "app1")

        let expanded = ReportAppRankingFilter.visible(entries: all, showsAll: true, focusedAppKey: nil)
        #expect(expanded.count == 30)
        // 展开后能看到第 25 名之后的应用，这是此前 25 条截断无法做到的。
        #expect(expanded.last?.appKey == "app30")
    }

    @Test func focusedAppStaysVisibleWhenOutsideFirstPage() {
        let entries = (1...30).map { item("app\($0)", value: Double(31 - $0)) }
        let visible = ReportAppRankingFilter.visible(entries: entries, showsAll: false, focusedAppKey: "app27")
        #expect(visible.contains { $0.appKey == "app27" })
        #expect(visible.count == 8)
    }

    @Test func searchFiltersByNameAndKeyThenClearRestoresList() {
        let entries = [
            item("com.apple.Safari", name: "Safari", value: 10),
            item("com.apple.Xcode", name: "Xcode", value: 20),
            item("WindowServer", name: "WindowServer", value: 30),
        ]
        let searched = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: true, query: "xco", sortOrder: .value)
        #expect(searched.map(\.appKey) == ["com.apple.Xcode"])

        let cleared = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: true, query: "   ", sortOrder: .value)
        #expect(cleared.count == 3)
    }

    @Test func searchWithNoMatchesReturnsEmptyWithoutTouchingOrder() {
        let entries = [item("a", value: 1), item("b", value: 2)]
        let none = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: true, query: "zzz", sortOrder: .value)
        #expect(none.isEmpty)
    }

    @Test func systemFilterAppliesToSearchResults() {
        let entries = [
            item("com.apple.Safari", name: "Safari", value: 10),
            item("WindowServer", name: "WindowServer", value: 30),
        ]
        let userOnly = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: false, query: "", sortOrder: .value)
        #expect(userOnly.map(\.appKey) == ["com.apple.Safari"])

        let searched = ReportAppRankingFilter.apply(
            to: entries, includeSystemApps: false, query: "window", sortOrder: .value)
        #expect(searched.isEmpty)
    }

    @Test func expandedListRendersInBatchesButStaysComplete() {
        let entries = (1...400).map { item("app\($0)", value: Double(401 - $0)) }
        // 第一批：只渲染一个批次，不是全部。
        let firstBatch = ReportAppRankingFilter.visible(
            entries: entries, showsAll: true, focusedAppKey: nil,
            expandedLimit: ReportAppRankingFilter.renderBatch
        )
        #expect(firstBatch.count == ReportAppRankingFilter.renderBatch)

        // 未限制时返回全部：完整列表始终可访问。
        let all = ReportAppRankingFilter.visible(entries: entries, showsAll: true, focusedAppKey: nil)
        #expect(all.count == 400)

        // 批次推进后可见条目随之增长。
        let secondBatch = ReportAppRankingFilter.visible(
            entries: entries, showsAll: true, focusedAppKey: nil,
            expandedLimit: ReportAppRankingFilter.renderBatch * 2
        )
        #expect(secondBatch.count == ReportAppRankingFilter.renderBatch * 2)
    }

    @Test func focusedAppStaysVisibleWhileBatching() {
        let entries = (1...400).map { item("app\($0)", value: Double(401 - $0)) }
        // 深链目标在第 300 位，首批渲染也必须能看到它。
        let batch = ReportAppRankingFilter.visible(
            entries: entries, showsAll: true, focusedAppKey: "app300",
            expandedLimit: ReportAppRankingFilter.renderBatch
        )
        #expect(batch.contains { $0.appKey == "app300" })
        #expect(batch.count == ReportAppRankingFilter.renderBatch + 1)
    }

    @Test func renderBatchIsSmallEnoughForSmoothScrolling() {
        // 批次过大就失去分批的意义；过小则用户要频繁点击。
        #expect(ReportAppRankingFilter.renderBatch >= 20)
        #expect(ReportAppRankingFilter.renderBatch <= 100)
    }

    @Test func sortOrdersCoverValuePeakAndName() {
        let entries = [
            item("b", name: "Beta", value: 5, peak: 40),
            item("a", name: "Alpha", value: 20, peak: 25),
            item("c", name: "Gamma", value: 10, peak: 90),
        ]
        #expect(ReportAppRankingFilter.apply(to: entries, includeSystemApps: true, query: "", sortOrder: .value).map(\.appKey) == ["a", "c", "b"])
        #expect(ReportAppRankingFilter.apply(to: entries, includeSystemApps: true, query: "", sortOrder: .peak).map(\.appKey) == ["c", "b", "a"])
        #expect(ReportAppRankingFilter.apply(to: entries, includeSystemApps: true, query: "", sortOrder: .name).map(\.appKey) == ["a", "b", "c"])
    }
}
