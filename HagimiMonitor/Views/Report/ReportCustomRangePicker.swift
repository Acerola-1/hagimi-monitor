import SwiftUI

/// 现代流体范围日历选择器：纯 SwiftUI 实现连续范围选择、柔和胶囊连线与快速预设，摒弃老旧方块网格。
struct ReportCustomRangePicker: View {
    let selectedRange: ReportTimeRange
    @Binding var isPresented: Bool
    let onApply: (Date, Date) -> Void

    @State private var displayedMonth: Date
    @State private var draftFrom: Date
    @State private var draftTo: Date
    @State private var isSelectingRange: Bool = false
    @State private var hoveredDate: Date? = nil

    init(
        selectedRange: ReportTimeRange,
        isPresented: Binding<Bool>,
        onApply: @escaping (Date, Date) -> Void
    ) {
        self.selectedRange = selectedRange
        self._isPresented = isPresented
        self.onApply = onApply

        let bounds = Self.draftBounds(for: selectedRange, now: Date(), calendar: .current)
        self._draftFrom = State(initialValue: bounds.from)
        self._draftTo = State(initialValue: bounds.to)
        self._displayedMonth = State(initialValue: bounds.to)
    }

    private var calendar: Calendar { .current }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    var body: some View {
        VStack(spacing: 14) {
            // 1. 顶部月份导航与快捷预设
            headerView

            // 2. 星期表头与流体日期网格
            calendarGridView

            Divider()
                .opacity(0.4)

            // 3. 底部选区概览与操作按钮
            footerView
        }
        .padding(16)
        .frame(width: 310)
        .onAppear {
            synchronizeDraft()
        }
        .onChange(of: isPresented) { _, presented in
            if presented { synchronizeDraft() }
        }
    }

    // MARK: - 1. 顶部头部视图

    private var headerView: some View {
        VStack(spacing: 10) {
            // 月份导航条
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.primary.opacity(0.05)))

                Spacer()

                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .disabled(isCurrentOrFutureMonth)
                .opacity(isCurrentOrFutureMonth ? 0.3 : 1.0)
            }

            // 快捷预设芯片条
            HStack(spacing: 6) {
                presetChip(title: String(localized: "stats.r.rToday"), days: 0)
                presetChip(title: String(localized: "report.ui.yesterday", defaultValue: "昨天"), days: -1)
                presetChip(title: String(localized: "stats.r.rWeek"), days: 7)
                presetChip(title: String(localized: "stats.r.rMonth"), days: 30)
                thisMonthChip
            }
        }
    }

    private var isCurrentOrFutureMonth: Bool {
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let displayedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return false
        }
        return displayedMonthStart >= currentMonthStart
    }

    private func changeMonth(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = next
        }
    }

    // MARK: - 快捷预设芯片

    private func presetChip(title: String, days: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if days == 0 {
                    draftFrom = today
                    draftTo = today
                } else if days == -1 {
                    let y = calendar.date(byAdding: .day, value: -1, to: today) ?? today
                    draftFrom = y
                    draftTo = y
                } else {
                    let from = calendar.date(byAdding: .day, value: -days + 1, to: today) ?? today
                    draftFrom = from
                    draftTo = today
                }
                displayedMonth = today
                isSelectingRange = false
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }

    private var thisMonthChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
                draftFrom = startOfMonth
                draftTo = today
                displayedMonth = today
                isSelectingRange = false
            }
        } label: {
            Text(String(localized: "report.ui.thisMonth", defaultValue: "本月"))
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. 星期与流体日期网格

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var calendarGridView: some View {
        let days = computeMonthDays()
        return VStack(spacing: 6) {
            // 星期表头
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)

            // 日期单元格网格 (7 列)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(days) { item in
                    dayCellView(item: item)
                }
            }
        }
    }

    private func dayCellView(item: MonthDayItem) -> some View {
        let isToday = calendar.isDateInToday(item.date)
        let isFuture = item.date > today
        let activeRange = currentActiveRange
        let isStart = calendar.isDate(item.date, inSameDayAs: activeRange.from)
        let isEnd = calendar.isDate(item.date, inSameDayAs: activeRange.to)
        let isInRange = item.date >= activeRange.from && item.date <= activeRange.to
        let isSingleDay = calendar.isDate(activeRange.from, inSameDayAs: activeRange.to)

        return ZStack {
            // 连续流体区间色块
            if isInRange && !isSingleDay && item.isCurrentMonth {
                rangeBandBackground(isStart: isStart, isEnd: isEnd)
            }

            // 日期圆形按钮与文字
            Circle()
                .fill(isStart || isEnd ? Color.accentColor : Color.clear)
                .frame(width: 26, height: 26)
                .overlay {
                    if isToday && !isStart && !isEnd {
                        Circle()
                            .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.2)
                    }
                }

            Text("\(item.dayNumber)")
                .font(.system(size: 11, weight: (isStart || isEnd || isToday) ? .semibold : .regular))
                .foregroundStyle(
                    (isStart || isEnd) ? Color.white :
                    isFuture ? Color.secondary.opacity(0.25) :
                    !item.isCurrentMonth ? Color.secondary.opacity(0.25) :
                    isToday ? Color.accentColor :
                    Color.primary
                )
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.isCurrentMonth && !isFuture else { return }
            selectDate(item.date)
        }
        .onHover { isHovered in
            if isHovered && isSelectingRange && item.isCurrentMonth && !isFuture {
                hoveredDate = item.date
            } else if !isHovered && hoveredDate == item.date {
                hoveredDate = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ReportUIHelper.formatDateShort(item.date))
        .accessibilityAddTraits(item.isCurrentMonth && !isFuture ? .isButton : [])
        .accessibilityValue(isStart ? String(localized: "stats.r.rangeStart", defaultValue: "起始日期") : (isEnd ? String(localized: "stats.r.rangeEnd", defaultValue: "结束日期") : (isInRange ? String(localized: "stats.r.rangeSelected", defaultValue: "已选") : "")))
    }

    private func rangeBandBackground(isStart: Bool, isEnd: Bool) -> some View {
        let bandColor = Color.accentColor.opacity(isSelectingRange ? 0.12 : 0.18)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                if isStart {
                    path.addRect(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
                } else if isEnd {
                    path.addRect(CGRect(x: 0, y: 0, width: w / 2, height: h))
                } else {
                    path.addRect(CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            .fill(bandColor)
        }
    }

    private var currentActiveRange: (from: Date, to: Date) {
        if isSelectingRange, let hovered = hoveredDate {
            let start = min(draftFrom, hovered)
            let end = max(draftFrom, hovered)
            return (start, end)
        }
        return (min(draftFrom, draftTo), max(draftFrom, draftTo))
    }

    private func selectDate(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if !isSelectingRange {
                draftFrom = date
                draftTo = date
                isSelectingRange = true
            } else {
                if date < draftFrom {
                    draftTo = draftFrom
                    draftFrom = date
                } else {
                    draftTo = date
                }
                isSelectingRange = false
                hoveredDate = nil
            }
        }
    }

    // MARK: - 3. 底部选区概览与操作按钮

    private var footerView: some View {
        VStack(spacing: 8) {
            // 已选范围指示
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(rangeSummary)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(dayCount) \(String(localized: "report.ui.days", defaultValue: "天"))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            HStack {
                Button(String(localized: "report.ui.cancel", defaultValue: "取消")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "report.ui.apply", defaultValue: "应用")) {
                    applyDraft()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var dayCount: Int {
        let from = min(draftFrom, draftTo)
        let to = max(draftFrom, draftTo)
        return (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }

    private var rangeSummary: String {
        let from = min(draftFrom, draftTo)
        let to = max(draftFrom, draftTo)
        return "\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))"
    }

    private func applyDraft() {
        let start = calendar.startOfDay(for: min(draftFrom, draftTo))
        let endDay = calendar.startOfDay(for: min(max(draftFrom, draftTo), today))
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        onApply(start, end)
        isPresented = false
    }

    private func synchronizeDraft() {
        let bounds = Self.draftBounds(for: selectedRange, now: Date(), calendar: calendar)
        draftFrom = bounds.from
        draftTo = bounds.to
        displayedMonth = bounds.to
        isSelectingRange = false
        hoveredDate = nil
    }

    // MARK: - 日历数学解算

    private struct MonthDayItem: Identifiable {
        var id: Date { date }
        let date: Date
        let dayNumber: Int
        let isCurrentMonth: Bool
    }

    private func computeMonthDays() -> [MonthDayItem] {
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let numDays = calendar.range(of: .day, in: .month, for: firstDay)?.count else {
            return []
        }

        var result: [MonthDayItem] = []
        let firstWeekdayComponent = calendar.component(.weekday, from: firstDay)
        let leadingDaysCount = (firstWeekdayComponent - calendar.firstWeekday + 7) % 7

        if leadingDaysCount > 0,
           let prevMonth = calendar.date(byAdding: .month, value: -1, to: firstDay),
           let prevMonthDays = calendar.range(of: .day, in: .month, for: prevMonth)?.count {
            for i in 0..<leadingDaysCount {
                let dayNum = prevMonthDays - leadingDaysCount + 1 + i
                if let d = calendar.date(byAdding: .day, value: -(leadingDaysCount - i), to: firstDay) {
                    result.append(MonthDayItem(date: d, dayNumber: dayNum, isCurrentMonth: false))
                }
            }
        }

        for day in 1...numDays {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                result.append(MonthDayItem(date: d, dayNumber: day, isCurrentMonth: true))
            }
        }

        let trailingDaysCount = (7 - (result.count % 7)) % 7
        if trailingDaysCount > 0 {
            for i in 1...trailingDaysCount {
                if let d = calendar.date(byAdding: .day, value: numDays - 1 + i, to: firstDay) {
                    result.append(MonthDayItem(date: d, dayNumber: i, isCurrentMonth: false))
                }
            }
        }

        return result
    }

    private static func draftBounds(
        for range: ReportTimeRange,
        now: Date,
        calendar: Calendar
    ) -> (from: Date, to: Date) {
        let today = calendar.startOfDay(for: now)
        let bounds = range.bounds(now: now, calendar: calendar)
        let from = calendar.startOfDay(for: bounds.from)
        let rawTo: Date
        if case .custom(_, let exclusiveTo) = range {
            let exclusiveDay = calendar.startOfDay(for: exclusiveTo)
            rawTo = calendar.date(byAdding: .day, value: -1, to: exclusiveDay) ?? exclusiveDay
        } else {
            rawTo = calendar.startOfDay(for: bounds.to)
        }
        let to = min(rawTo, today)
        return (min(from, to), to)
    }
}
