import Foundation
import Testing
@testable import HagimiMonitorDirect

/// R03：应用日行与系统指标共用右开边界，结束日为零点时该日整天被排除。
struct StatisticsDayRangeTests {
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

    private func key(_ string: String) -> Int64 {
        StatisticsProcessStore.dayKey(date(string), calendar: calendar)
    }

    @Test func exclusiveEndAtMidnightExcludesThatWholeDay() {
        let range = StatisticsProcessStore.dayRange(
            from: date("2026-09-25 00:00"),
            to: date("2026-10-01 00:00"),
            calendar: calendar
        )
        #expect(range.fromDay == key("2026-09-25 00:00"))
        // 结束日 10 月 1 日零点表示区间不包含 10 月 1 日。
        #expect(range.toDayExclusive == key("2026-10-01 00:00"))
        #expect(range.contains(day: key("2026-09-30 12:00")))
        #expect(range.contains(day: key("2026-10-01 00:00")) == false)
    }

    @Test func midDayEndIncludesThatDayEntirely() {
        let range = StatisticsProcessStore.dayRange(
            from: date("2026-09-25 00:00"),
            to: date("2026-10-01 18:00"),
            calendar: calendar
        )
        // 结束点在 10 月 1 日中间时，10 月 1 日整天参与统计。
        #expect(range.contains(day: key("2026-10-01 09:00")))
        #expect(range.toDayExclusive == key("2026-10-02 00:00"))
    }

    @Test func singleDayRangeCoversOnlyThatDay() {
        let range = StatisticsProcessStore.dayRange(
            from: date("2026-10-01 00:00"),
            to: date("2026-10-02 00:00"),
            calendar: calendar
        )
        #expect(range.contains(day: key("2026-10-01 23:59")))
        #expect(range.contains(day: key("2026-09-30 12:00")) == false)
        #expect(range.contains(day: key("2026-10-02 00:00")) == false)
    }

    @Test func dayKeyIsCalendarBasedNotFixedSeconds() {
        // 跨夏令时的纽约：固定 86400 秒回推会落到前一天 23:00。
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let formatter = DateFormatter()
        formatter.calendar = ny
        formatter.timeZone = ny.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let afterDST = formatter.date(from: "2026-03-10 00:00")!
        let range = StatisticsProcessStore.dayRange(
            from: formatter.date(from: "2026-03-04 00:00")!,
            to: afterDST,
            calendar: ny
        )
        let march9 = formatter.date(from: "2026-03-09 12:00")!
        let march10 = formatter.date(from: "2026-03-10 00:00")!
        #expect(range.contains(day: StatisticsProcessStore.dayKey(march9, calendar: ny)))
        #expect(range.contains(day: StatisticsProcessStore.dayKey(march10, calendar: ny)) == false)
        #expect(range.toDayExclusive == StatisticsProcessStore.dayKey(march10, calendar: ny))
    }
}
