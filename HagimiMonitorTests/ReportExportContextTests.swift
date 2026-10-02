import Foundation
import Testing
@testable import HagimiMonitorDirect

/// X01 / X02：导出使用提交范围，范围边界与设置/原生报表同源；
/// HTML 侧不再自行用滚动小时窗口计算范围。
struct ReportExportContextTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    @MainActor
    @Test func committedExportRangeIsNilBeforeSnapshot() {
        let viewModel = NativeReportViewModel(recorder: nil)
        // 没有快照时不臆造范围，导出侧据此回退到模板默认。
        #expect(viewModel.committedExportRange() == nil)
    }

    @Test func weekExportBoundsMatchSettingsAndNativeReport() {
        let now = date("2026-10-01 18:00")
        // 三处必须给出同一起点：设置页窗口、原生报表、导出。
        let settingsStart = StatisticsOverviewRange.week.startOfDayWindow(from: now, calendar: calendar)
        let reportBounds = ReportTimeRange.week.bounds(now: now, calendar: calendar)
        let exportToday = calendar.startOfDay(for: now)
        let exportStart = calendar.date(byAdding: .day, value: -6, to: exportToday)!

        #expect(settingsStart == reportBounds.from)
        #expect(reportBounds.from == exportStart)
        #expect(reportBounds.to == now)
    }

    @Test func monthAndYearExportBoundsUseCalendarDays() {
        let now = date("2026-10-01 18:00")
        let month = ReportTimeRange.month.bounds(now: now, calendar: calendar)
        let year = ReportTimeRange.year.bounds(now: now, calendar: calendar)
        #expect(month.from == date("2026-09-02 00:00"))
        #expect(year.from == date("2025-10-02 00:00"))
    }

    @Test func rangesSpannedDoNotReuseRollingSeconds() {
        // 旧模板用 now - 7 × 86400，会落在 9 月 24 日 18:00。
        let now = date("2026-10-01 18:00")
        let rolling = now.addingTimeInterval(-7 * 86400)
        let natural = ReportTimeRange.week.bounds(now: now, calendar: calendar).from
        #expect(natural != rolling)
        #expect(natural == date("2026-09-25 00:00"))
    }

    @Test func committedRangeLabelFollowsSelectedRange() {
        // 标签直接来自范围模型，导出头部因此显示用户实际选择的范围名。
        #expect(ReportTimeRange.week.label == StatisticsOverviewRange.week.reportTimeRange.label)
        #expect(ReportTimeRange.month.label == StatisticsOverviewRange.month.reportTimeRange.label)
        #expect(ReportTimeRange.today.label == StatisticsOverviewRange.today.reportTimeRange.label)
    }
}
