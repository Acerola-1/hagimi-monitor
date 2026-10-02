import Foundation
import Testing
@testable import HagimiMonitorDirect

/// U01：从设置摘要进入报表必须携带范围、应用与指标，复用窗口提交新上下文；
/// 目标事件被删除时明确说明，而不是静默切换到别的应用。
struct StatisticsReportContextTests {
    @Test func contextCarriesRangeAnchorAndFocus() {
        let context = StatisticsReportContext(
            range: .week,
            anchor: .apps,
            appKey: "com.apple.Safari",
            metric: .memory
        )
        #expect(context.range == .week)
        #expect(context.anchor == .apps)
        #expect(context.appKey == "com.apple.Safari")
        #expect(context.metric == .memory)
        #expect(context.eventID == nil)
    }

    @Test func anchorOnlyInitializerKeepsBackwardCompatibility() {
        let context = StatisticsReportContext(anchor: .memory)
        #expect(context.anchor == .memory)
        #expect(context.range == nil)
        #expect(context.appKey == nil)
        #expect(context.metric == nil)
    }

    @Test func settingsRangeMapsToReportRangeWithoutChangingDay() {
        // 设置与报表必须给出同一自然日起点，不能一个是自然日、一个是滚动小时。
        #expect(StatisticsOverviewRange.today.reportTimeRange == .today)
        #expect(StatisticsOverviewRange.week.reportTimeRange == .week)
        #expect(StatisticsOverviewRange.month.reportTimeRange == .month)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = formatter.date(from: "2026-10-01 18:00")!

        // 设置页的数据窗口起点
        let settingsStart = StatisticsOverviewRange.week.startOfDayWindow(from: now, calendar: calendar)
        // 报表侧同名范围的起点
        let reportStart = StatisticsOverviewRange.week.reportTimeRange.bounds(now: now, calendar: calendar).from
        #expect(settingsStart == reportStart)
    }

    @MainActor
    @Test func applyingContextCommitsRangeModuleAndFocusBeforeLoading() {
        let viewModel = NativeReportViewModel(recorder: nil)
        viewModel.apply(StatisticsReportContext(
            range: .month,
            anchor: .apps,
            appKey: "com.apple.Safari",
            metric: .gpu
        ))
        // 无 recorder 时不会真正加载，但上下文必须已提交，保证标题与数据不会错配。
        #expect(viewModel.selectedRange == .month)
        #expect(viewModel.selectedModule == .apps)
        #expect(viewModel.focusedAppKey == "com.apple.Safari")
        #expect(viewModel.focusedMetric == .gpu)
        #expect(viewModel.focusedEventIsMissing == false)
    }

    @MainActor
    @Test func refreshKeepsRangeFocusAndRankingState() {
        let viewModel = NativeReportViewModel(recorder: nil)
        viewModel.apply(StatisticsReportContext(
            range: .month,
            anchor: .apps,
            appKey: "com.apple.Safari",
            metric: .memory,
            eventID: UUID()
        ))
        // 排行搜索/排序/展开属于用户上下文，刷新与模块切换都不应重置。
        viewModel.appSearchText = "saf"
        viewModel.appSortOrder = .peak
        viewModel.appsShowsAll = true
        viewModel.refreshCurrentReport()

        #expect(viewModel.selectedRange == .month)
        #expect(viewModel.selectedModule == .apps)
        #expect(viewModel.focusedAppKey == "com.apple.Safari")
        #expect(viewModel.appSearchText == "saf")
        #expect(viewModel.appSortOrder == .peak)
        #expect(viewModel.appsShowsAll)
    }

    @MainActor
    @Test func hardwareLoadingFlagStartsIdleAndStatisticsLoadingIsSeparate() {
        let viewModel = NativeReportViewModel(recorder: nil)
        // 硬件清单是第二阶段；初始状态不应声称正在加载硬件。
        #expect(viewModel.isHardwareLoading == false)
        // 统计加载与硬件加载是两个独立标记，不能共用一个 requestID 互相失效。
        #expect(viewModel.isLoading == true)
    }

    @MainActor
    @Test func contextWithoutEventClearsMissingRecordFlag() {
        let viewModel = NativeReportViewModel(recorder: nil)
        viewModel.apply(StatisticsReportContext(anchor: .apps, eventID: UUID()))
        // 无 recorder 时不会加载快照，但提交新上下文必须先清掉上一次的缺失判定，
        // 否则用户会看到上一个目标遗留的「记录不存在」。
        #expect(viewModel.focusedEventIsMissing == false)
    }

    @MainActor
    @Test func nilAnchorKeepsCurrentModuleButStillCommitsRange() {
        let viewModel = NativeReportViewModel(recorder: nil)
        viewModel.selectedModule = .memory
        viewModel.apply(StatisticsReportContext(range: .week))
        #expect(viewModel.selectedModule == .memory)
        #expect(viewModel.selectedRange == .week)
        #expect(viewModel.focusedAppKey == nil)
    }
}
