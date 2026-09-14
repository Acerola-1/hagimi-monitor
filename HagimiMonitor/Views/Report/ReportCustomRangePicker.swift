import SwiftUI

/// 自定义报表范围选择器：一个原生日历配合起止端点切换，提交时使用自然日开区间。
struct ReportCustomRangePicker: View {
    private enum Endpoint: Hashable {
        case from
        case to
    }

    let selectedRange: ReportTimeRange
    @Binding var isPresented: Bool
    let onApply: (Date, Date) -> Void

    @State private var draftFrom: Date
    @State private var draftTo: Date
    @State private var endpoint: Endpoint = .from

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
    }

    private var calendar: Calendar { .current }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var activeDate: Binding<Date> {
        Binding(
            get: { endpoint == .from ? draftFrom : draftTo },
            set: { value in
                let normalized = min(calendar.startOfDay(for: value), today)
                if endpoint == .from {
                    draftFrom = normalized
                    if draftTo < normalized { draftTo = normalized }
                } else {
                    draftTo = normalized
                    if draftFrom > normalized { draftFrom = normalized }
                }
            }
        )
    }

    private var activeDateRange: ClosedRange<Date> {
        let earliest = calendar.date(byAdding: .year, value: -10, to: today)
            ?? Date(timeIntervalSince1970: 0)
        if endpoint == .from {
            return earliest...draftTo
        }
        return draftFrom...today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "stats.r.selectRange", defaultValue: "选择自定义时间范围"))
                    .font(.headline)
                Text(String(localized: "stats.r.customRangePending", defaultValue: "待应用范围"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(rangeSummary)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .accessibilityLabel(Text(String(localized: "stats.r.customRangePending", defaultValue: "待应用范围")))
            }

            ReportNavigationPicker(
                title: String(localized: "report.ui.dateEndpoint", defaultValue: "日期端点"),
                selection: $endpoint
            ) {
                Text(String(localized: "report.ui.from", defaultValue: "开始日期"))
                    .tag(Endpoint.from)
                Text(String(localized: "report.ui.to", defaultValue: "结束日期"))
                    .tag(Endpoint.to)
            }
            .accessibilityLabel(Text(String(localized: "report.ui.dateEndpoint", defaultValue: "日期端点")))

            DatePicker(
                endpoint == .from
                    ? String(localized: "report.ui.from", defaultValue: "开始日期")
                    : String(localized: "report.ui.to", defaultValue: "结束日期"),
                selection: activeDate,
                in: activeDateRange,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .accessibilityLabel(Text(
                endpoint == .from
                    ? String(localized: "report.ui.from", defaultValue: "开始日期")
                    : String(localized: "report.ui.to", defaultValue: "结束日期")
            ))

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
        .padding(16)
        .frame(width: 360)
        .onAppear {
            synchronizeDraft()
        }
        .onChange(of: isPresented) { _, presented in
            if presented { synchronizeDraft() }
        }
        .onChange(of: selectedRange) { _, _ in
            if isPresented { synchronizeDraft() }
        }
    }

    private var rangeSummary: String {
        "\(draftFrom.formatted(date: .abbreviated, time: .omitted)) – "
            + draftTo.formatted(date: .abbreviated, time: .omitted)
    }

    private func applyDraft() {
        let start = calendar.startOfDay(for: draftFrom)
        let endDay = calendar.startOfDay(for: min(draftTo, today))
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        onApply(start, end)
        isPresented = false
    }

    private func synchronizeDraft() {
        let bounds = Self.draftBounds(for: selectedRange, now: Date(), calendar: calendar)
        draftFrom = bounds.from
        draftTo = bounds.to
        endpoint = .from
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
