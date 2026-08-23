import SwiftUI

/// 设置侧栏「数据统计」:健康评分 + 范围总览卡 + 网页报表入口。
/// 存储占用与清理见独立的「存储管理」页(StorageSettingsView)。
/// 数据由 StatisticsRecorder 每分钟封口后发布,本视图只读展示。
struct StatisticsSettingsView: View {
    @ObservedObject var recorder: StatisticsRecorder
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedRange: StatisticsOverviewRange = .today
    /// 跳转存储管理页(入口收在本页底部,归属数据统计)。
    var openStorage: () -> Void = {}

    private var row: StatisticsRow? {
        recorder.rangeRows[selectedRange] ?? nil
    }

    var body: some View {
        SettingsPage {
            header

            if hasAnyData {
                SettingsGroup(String(localized: "stats.settings.overview"),
                              titleAccessory: { reportEntryButton }) {
                    rangePicker
                    healthCard
                    overviewGrid
                }
            } else {
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "stats.settings.empty-title"), systemImage: "hourglass")
                            .font(.body.weight(.medium))
                        Text(String(localized: "stats.settings.empty-body"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 无数据时总览组不显示,报表入口退回独立行兜底;有数据时入口已收进总览标题行。
            if !hasAnyData {
                SettingsGroup {
                    entryRow(
                        icon: "safari",
                        title: String(localized: "stats.settings.report-title"),
                        subtitle: nil,
                        action: { StatisticsReportFlow.open(recorder: recorder) }
                    )
                }
            }

            SettingsGroup {
                entryRow(
                    icon: "internaldrive",
                    title: String(localized: "settings.sidebar.storage"),
                    subtitle: nil,
                    action: openStorage
                )
            }

            SettingsTip(String(localized: "stats.settings.local-only"))
        }
    }

    // MARK: - 头部(默认折叠的使用打卡)

    @State private var showCheckin = false
    @State private var dayCoverage: [Int64: Double] = [:]

    private var header: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showCheckin.toggle() }
                if showCheckin { loadDayCoverage() }
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        )

                    Text(headerPrimary)
                        .font(.headline.weight(.semibold))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showCheckin ? -180 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(StaticPressButtonStyle())

            if showCheckin {
                checkinPanel
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerPrimary: String {
        if recorder.usageTotalDays > 0 {
            return String(localized: "stats.settings.checkin-total \(recorder.usageTotalDays)")
        }
        if recorder.recordDays > 0 {
            return String(localized: "stats.settings.record-days \(recorder.recordDays)")
        }
        return String(localized: "stats.settings.subtitle-empty")
    }

    /// 展开区:周列 × 星期行的使用打卡日历 + 起始日摘要。
    @ViewBuilder
    private var checkinPanel: some View {
        let calendar = Calendar.current
        let active = Set(recorder.usageActiveDays)
        let todayKey = StatisticsProcessStore.dayKey(Date(), calendar: calendar)
        // 周一起列,与报表打卡网格一致,不随 locale firstWeekday 变化。
        // Calendar.weekday 为 1-based(周日=1):周一回退 0 天,周日回退 6 天。
        let weekday = calendar.component(.weekday, from: Date())
        let monday = calendar.date(
            byAdding: .day, value: -((weekday + 5) % 7),
            to: calendar.startOfDay(for: Date()))!

        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // 懒加载周列:26 周 × 7 格一次性建齐会让展开/收起瞬间的视图
                    // 重建与头部同帧竞争,只建可见列,切换更顺滑。
                    LazyHStack(alignment: .top, spacing: 3) {
                        ForEach(0..<26, id: \.self) { weekIndex in
                            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex - 25, to: monday)!
                            VStack(spacing: 3) {
                                Text(monthLabel(for: weekStart, calendar: calendar))
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 10)
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    let date = calendar.date(byAdding: .day, value: dayIndex, to: weekStart)!
                                    let key = StatisticsProcessStore.dayKey(date, calendar: calendar)
                                    checkinCell(active: active.contains(key),
                                                hours: dayCoverage[key] ?? 0,
                                                isToday: key == todayKey)
                                }
                            }
                            .id(weekIndex)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    // 展开时滚到最后一列(今天所在周),不让用户从 26 周前开始翻。
                    // 延后到主线程帧末无动画定位:立即动画滚动会与展开切换竞争,产生跳动。
                    DispatchQueue.main.async {
                        proxy.scrollTo(25, anchor: .trailing)
                    }
                }
            }

            if recorder.usageFirstDay > 0 {
                Text(String(localized: "stats.settings.checkin-footer \(firstDayText) \(recorder.usageTotalDays)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 周列顶部月份标签:仅当该周跨入新月份时显示。
    private func monthLabel(for weekStart: Date, calendar: Calendar) -> String {
        let thisMonth = calendar.component(.month, from: weekStart)
        let prevMonth = calendar.component(.month, from: calendar.date(byAdding: .day, value: -7, to: weekStart)!)
        guard thisMonth != prevMonth else { return "" }
        return weekStart.formatted(.dateTime.month(.abbreviated))
    }

    /// 打卡格:未使用灰色;使用过按当日采样覆盖时长分四档深浅。
    private func checkinCell(active: Bool, hours: Double, isToday: Bool) -> some View {
        let opacity: Double = !active ? 0 : hours < 2 ? 0.35 : hours < 6 ? 0.6 : hours < 12 ? 0.85 : 1
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(active ? Color.accentColor.opacity(opacity) : Color.secondary.opacity(0.14))
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isToday ? 1 : 0)
            )
    }

    /// 展开时拉取日桶覆盖时长,供打卡格分档着色。
    /// 优先真实采样覆盖秒数(cover_s);迁移前的旧行回退帧数口径。
    private func loadDayCoverage() {
        recorder.storageBuckets(.day) { buckets in
            var map: [Int64: Double] = [:]
            let calendar = Calendar.current
            for bucket in buckets {
                let seconds = bucket.row.coverS ?? Double(bucket.row.n)
                map[StatisticsProcessStore.dayKey(bucket.start, calendar: calendar)] = seconds / 3600
            }
            dayCoverage = map
        }
    }

    private var firstDayText: String {
        let key = recorder.usageFirstDay
        let components = DateComponents(year: Int(key / 10_000), month: Int(key % 10_000 / 100), day: Int(key % 100))
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.year().month().day())
    }

    private var hasAnyData: Bool {
        StatisticsOverviewRange.allCases.contains { range in
            (recorder.rangeRows[range] ?? nil) != nil
        }
    }

    /// 总览标题行右侧的报表快捷入口:与总览内容同属一屏,不必滚动到底部找入口。
    private var reportEntryButton: some View {
        Button {
            StatisticsReportFlow.open(recorder: recorder)
        } label: {
            Label(String(localized: "stats.settings.report-details"), systemImage: "safari")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// 报表与存储管理入口共用的导航行:图标+标题(+可选副标题)+右箭头,视觉统一。
    @ViewBuilder
    private func entryRow(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 范围切换

    private var rangePicker: some View {
        HStack {
            Spacer(minLength: 0)
            Picker(String(localized: "stats.settings.overview"), selection: $selectedRange) {
                Text(String(localized: "stats.settings.range.today")).tag(StatisticsOverviewRange.today)
                Text(String(localized: "stats.settings.range.week")).tag(StatisticsOverviewRange.week)
                Text(String(localized: "stats.settings.range.month")).tag(StatisticsOverviewRange.month)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    // MARK: - 健康评分

    private var healthScore: StatisticsHealthScore.Result? {
        guard let row else { return nil }
        return StatisticsHealthScore.evaluate(rows: [row])
    }

    @ViewBuilder
    private var healthCard: some View {
        if let health = healthScore {
            HStack(spacing: 18) {
                scoreRing(health)

                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(health.dimensions) { dimension in
                            dimensionBadge(dimension)
                        }
                    }

                    if health.thermalCapped {
                        Label(String(localized: "stats.r.healthCapped"), systemImage: "flame")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private func scoreRing(_ health: StatisticsHealthScore.Result) -> some View {
        let tint = levelColor(health.level)
        let fraction = min(health.score / 100, 1)
        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 8)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.4), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * fraction)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int(health.score.rounded()))")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(health.level.title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.85))
            }
        }
        .frame(width: 76, height: 76)
    }

    /// 维度迷你卡:与总览 tile 同语言的圆角色块,内含维度名、应力值与进度条。
    private func dimensionBadge(_ dimension: StatisticsHealthScore.Dimension) -> some View {
        let tint = levelColor(dimension.level)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(dimension.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(dimension.rawText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: geo.size.width * dimension.stressShare)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.07 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.5)
        )
    }

    private func levelColor(_ level: StatisticsHealthScore.Level) -> Color {
        let dark = colorScheme == .dark
        switch level {
        case .excellent: return Color(hex: dark ? 0x34C759 : 0x2F9E64)
        case .good: return Color(hex: dark ? 0x64D2FF : 0x3BAFDA)
        case .fair: return Color(hex: dark ? 0xFFD60A : 0xD4A843)
        case .poor: return Color(hex: dark ? 0xFF9F0A : 0xE08E45)
        case .critical: return Color(hex: dark ? 0xFF6961 : 0xD94848)
        }
    }

    // MARK: - 总览格

    /// 总览卡模块配色:与网页报表同套模块主色,双主题各一档。
    private enum ModuleTint {
        static func cpu(_ dark: Bool) -> Color { Color(hex: dark ? 0xF97316 : 0xEA580C) }
        static func gpu(_ dark: Bool) -> Color { Color(hex: dark ? 0xA855F7 : 0x9333EA) }
        static func memory(_ dark: Bool) -> Color { Color(hex: dark ? 0x38BDF8 : 0x0284C7) }
        static func network(_ dark: Bool) -> Color { Color(hex: dark ? 0x2DD4BF : 0x0D9488) }
        static func disk(_ dark: Bool) -> Color { Color(hex: dark ? 0xD9A94A : 0xB45309) }
        static func power(_ dark: Bool) -> Color { Color(hex: dark ? 0x34D399 : 0x059669) }
    }

    private struct MetricLine {
        let label: String
        let systemImage: String?
        let value: String
    }

    private struct TileSpec {
        let title: String
        let icon: String
        let tint: Color
        let lines: [MetricLine]
    }

    private var tiles: [TileSpec] {
        let row = row
        let dark = colorScheme == .dark
        func line(_ label: String, icon: String? = nil, _ value: String) -> MetricLine {
            MetricLine(label: label, systemImage: icon, value: value)
        }
        func pct(_ v: Double?) -> String { v == nil ? "—" : String(format: "%.1f%%", v!) }
        return [
            TileSpec(title: String(localized: "stats.settings.k-cpu"), icon: "cpu", tint: ModuleTint.cpu(dark), lines: [
                line(String(localized: "stats.settings.avg"), pct(row?.cpuAvg)),
                line(String(localized: "stats.settings.peak-label"), pct(row?.cpuMax)),
            ]),
            TileSpec(title: String(localized: "stats.settings.k-gpu"), icon: "display", tint: ModuleTint.gpu(dark), lines: [
                line(String(localized: "stats.settings.avg"), pct(row?.gpuAvg)),
                line(String(localized: "stats.settings.peak-label"), pct(row?.gpuMax)),
            ]),
            TileSpec(title: String(localized: "stats.settings.k-mem"), icon: "memorychip", tint: ModuleTint.memory(dark), lines: [
                line(String(localized: "stats.settings.avg"), pct(row?.memPctAvg)),
                line(String(localized: "stats.settings.peak-label"), pct(row?.memPctMax)),
            ]),
            // 网络值带单位最长,只留箭头图标省宽度,保证单行不换行
            TileSpec(title: String(localized: "stats.settings.k-net"), icon: "network", tint: ModuleTint.network(dark), lines: [
                line("", icon: "arrow.down", bytes(row?.netDown)),
                line("", icon: "arrow.up", bytes(row?.netUp)),
            ]),
            TileSpec(title: String(localized: "stats.settings.k-disk"), icon: "internaldrive", tint: ModuleTint.disk(dark), lines: [
                line(String(localized: "stats.settings.read"), bytes(row?.diskRead)),
                line(String(localized: "stats.settings.write"), bytes(row?.diskWrite)),
            ]),
            // 桌面机型无电池,插电占比恒为常量无信息量;只保留整机平均功耗,
            // 标题用「系统负载」避免「功率/充电功率」歧义。
            TileSpec(title: String(localized: "stats.settings.k-load"), icon: "bolt", tint: ModuleTint.power(dark), lines: [
                line(String(localized: "stats.settings.avg"), watts(row?.powerAvg)),
            ]),
        ]
    }

    private var overviewGrid: some View {
        VStack(spacing: 10) {
            ForEach(0..<(tiles.count / 3), id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { column in
                        tile(tiles[rowIndex * 3 + column])
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func tile(_ spec: TileSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(spec.tint.opacity(0.16))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: spec.icon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(spec.tint)
                    )

                Text(spec.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(spec.lines.enumerated()), id: \.offset) { _, metric in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(spacing: 2) {
                        if let systemImage = metric.systemImage {
                            Image(systemName: systemImage)
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        if !metric.label.isEmpty {
                            Text(metric.label)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(metric.value)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        // 撑满行高:单行内容的格子(如系统负载)与两行格子同高同外观,顶对齐
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(spec.tint.opacity(colorScheme == .dark ? 0.07 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(spec.tint.opacity(0.14), lineWidth: 0.5)
        )
    }

    // MARK: - 格式化

    private func bytes(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
    }
}

/// 打卡卡展开按钮的专属样式:按下时标签外观完全静止。
/// 按钮标签内含高饱和渐变图标,系统按压反馈施加在其上会被放大成一次可见
/// 闪烁;展开/收起反馈由 chevron 旋转与高度动画承担,按钮本身不做视觉变化。
private struct StaticPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
