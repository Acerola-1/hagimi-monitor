import Foundation
import Testing
@testable import HagimiMonitorDirect

/// R01 / R02：预设范围使用本地自然日与右开边界，跨夏令时不靠固定 86400 秒。
struct ReportTimeRangeTests {
    /// 固定到上海时区，避免测试机器时区差异改变自然日边界。
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

    @Test func weekRangeStartsAtLocalMidnightSixDaysBeforeToday() {
        let now = date("2026-10-01 18:00")
        let (from, to) = ReportTimeRange.week.bounds(now: now, calendar: calendar)
        // 与设置页「近 7 日」同源：含今天在内的 7 个自然日。
        #expect(from == date("2026-09-25 00:00"))
        #expect(to == now)
    }

    @Test func monthRangeStartsTwentyNineDaysBeforeToday() {
        let now = date("2026-10-01 18:00")
        let (from, _) = ReportTimeRange.month.bounds(now: now, calendar: calendar)
        #expect(from == date("2026-09-02 00:00"))
    }

    @Test func yearRangeStartsThreeHundredSixtyFourDaysBeforeToday() {
        let now = date("2026-10-01 12:00")
        let (from, _) = ReportTimeRange.year.bounds(now: now, calendar: calendar)
        #expect(from == date("2025-10-02 00:00"))
    }

    @Test func todayRangeStartsAtMidnightAndEndsAtSnapshot() {
        let now = date("2026-10-01 18:00")
        let (from, to) = ReportTimeRange.today.bounds(now: now, calendar: calendar)
        #expect(from == date("2026-10-01 00:00"))
        #expect(to == now)
    }

    @Test func weekRangeIsNotARollingBlockOfFixedSeconds() {
        // 旧实现用 now-7*86400，会落在 9 月 24 日 18:00；自然日实现落在零点。
        let now = date("2026-10-01 18:00")
        let (from, _) = ReportTimeRange.week.bounds(now: now, calendar: calendar)
        let rolling = now.addingTimeInterval(-7 * 86400)
        // 固定秒数窗口从 9/24 18:00 起算；自然日实现从 9/25 00:00 起算，两者必须可区分。
        #expect(from != rolling)
        #expect(from == date("2026-09-25 00:00"))
    }

    @Test func customRangeKeepsExclusiveEndFromPicker() {
        let from = date("2026-09-20 00:00")
        let to = date("2026-09-26 00:00")   // 选择器提交的右开端点
        let bounds = ReportTimeRange.custom(from: from, to: to).bounds(now: date("2026-10-01 18:00"), calendar: calendar)
        #expect(bounds.from == from)
        #expect(bounds.to == to)
    }

    @Test func daylightSavingBoundaryUsesCalendarDaysNotFixedSeconds() {
        // 纽约 3 月 8 日进入夏令时（23 小时）。固定秒数会在切换日落偏一小时。
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = ny
        formatter.timeZone = ny.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = formatter.date(from: "2026-03-10 12:00")!

        let (from, _) = ReportTimeRange.week.bounds(now: now, calendar: ny)
        let components = ny.dateComponents([.year, .month, .day, .hour, .minute], from: from)
        // 无论中间是否经历 23 小时的一天，起点都应是本地零点。
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.day == 4)
    }

    @Test func weekRangeCrossesMonthBoundaryBackIntoPreviousMonth() {
        let now = date("2026-03-03 09:00")
        let (from, _) = ReportTimeRange.week.bounds(now: now, calendar: calendar)
        // 含今天在内的 7 个自然日应回溯到 2 月 25 日，而不是 2 月 24 日 09:00。
        #expect(from == date("2026-02-25 00:00"))
    }

    @Test func weekRangeCrossesYearBoundary() {
        let now = date("2026-01-02 09:00")
        let (from, _) = ReportTimeRange.week.bounds(now: now, calendar: calendar)
        #expect(from == date("2025-12-27 00:00"))
    }

    @Test func rangeBoundsRemainRightOpenAfterDayNormalization() {
        let now = date("2026-10-01 18:00")
        for range in [ReportTimeRange.today, .week, .month, .year] {
            let (from, to) = range.bounds(now: now, calendar: calendar)
            #expect(from < to, "范围 \(range) 的起点必须早于终点")
        }
    }
}
