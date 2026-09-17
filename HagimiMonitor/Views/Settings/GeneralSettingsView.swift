import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    /// 外观组三个分段选择器的统一宽度:宽度由内容自适应时,各行段宽分布
    /// 不同(如「English」与「浅色」字宽差异)导致分段边界错开,视觉不对齐。
    private static let segmentedPickerWidth: CGFloat = 220

    /// 语言切换待重启提示:偏好与 AppleLanguages 覆写已同步写入,
    /// 仅提示用户重启(立即/稍后)以原子切换全部界面文案。
    @State private var showsLanguageRestartAlert = false

    var body: some View {
        SettingsPage {
            UsageCheckinCard(recorder: store.statisticsRecorder)

            SettingsGroup {
                SettingsRow(title: String(localized: "settings.launch-at-login")) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.quick-access")) {
                    QuickAccessShortcutRecorder()
                }
            }

            SettingsGroup(String(localized: "settings.appearance")) {
                SettingsRow(title: String(localized: "settings.language")) {
                    Picker(String(localized: "settings.language"), selection: $settings.languagePreference) {
                        ForEach(AppLanguagePreference.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .compatibleTabPickerStyle()
                    .frame(width: Self.segmentedPickerWidth)
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.theme")) {
                    Picker(String(localized: "settings.theme"), selection: $settings.themePreference) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .compatibleTabPickerStyle()
                    .frame(width: Self.segmentedPickerWidth)
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.color-scheme")) {
                    Picker(String(localized: "settings.color-scheme"), selection: $settings.colorSchemePreference) {
                        ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                            Text(colorScheme.title).tag(colorScheme)
                        }
                    }
                    .labelsHidden()
                    .compatibleTabPickerStyle()
                    .frame(width: Self.segmentedPickerWidth)
                }

                if #available(macOS 26, *) {
                    SettingsDivider()

                    // 功能仍在测试:整行锁定为不可用态,已保存的偏好原值
                    // 保留、不被改写,放开时移除 disabled 即恢复。
                    SettingsRow(
                        title: String(localized: "settings.liquid-glass"),
                        subtitle: String(localized: "settings.liquid-glass.subtitle")
                    ) {
                        Toggle("", isOn: $settings.liquidGlassEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(true)
                    }
                    .opacity(0.45)
                }
            }

            MenuBarDisplaySettingsSection(settings: settings, store: store)
        }
        .onChange(of: settings.languagePreference) { _, _ in
            showsLanguageRestartAlert = true
        }
        .alert(
            String(localized: "settings.language.restart.title"),
            isPresented: $showsLanguageRestartAlert
        ) {
            Button(String(localized: "settings.language.restart.later")) {}
            Button(String(localized: "settings.language.restart.now")) {
                relaunchApp()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(String(localized: "settings.language.restart.message"))
        }
    }

    /// 重新拉起自身并退出:AppleLanguages 覆写需整进程重启才原子生效
    /// (常驻视图树与 AppKit 菜单的既有文案不会跟随运行期切换)。
    /// 先拉起新进程再退出旧进程,菜单栏图标无肉眼可见的空窗。
    private func relaunchApp() {
        guard let executableURL = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executableURL
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            // 拉起失败(可执行文件被移动等极端情形)保留旧进程,
            // 用户手动重启同样生效,不打断当前会话。
        }
    }
}

/// 快速呼出快捷键录制器。
///
/// 完全自绘的按钮:点击由真正的 SwiftUI Button 驱动,录制通过本地事件监听实现,
/// 库只负责存储与全局注册。
private struct QuickAccessShortcutRecorder: View {
    @StateObject private var model = QuickAccessShortcutModel()

    var body: some View {
        Button(action: model.toggleRecording) {
            content
                .frame(width: 168, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            model.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: model.isRecording ? 1.5 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if model.shortcut != nil, !model.isRecording {
                Button(action: model.clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(String(localized: "settings.quick-access.clear"))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isRecording)
        .animation(.easeInOut(duration: 0.15), value: model.shortcut)
        // 设置窗口关闭只 orderOut 不销毁视图树,onDisappear 不触发;录制中的本地
        // 按键监视器会一直吞掉全 app 按键、全局快捷键保持禁用。监听窗口关闭兜底拆除。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            model.stopRecording()
        }
        .onDisappear { model.stopRecording() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isRecording {
            HStack(spacing: 5) {
                // 提示：至少需要按住其中一个修饰键。
                HStack(spacing: 2) {
                    ShortcutKeyCap("⌃", compact: true)
                    ShortcutKeyCap("⌥", compact: true)
                    ShortcutKeyCap("⌘", compact: true)
                }
                .foregroundStyle(Color.accentColor)

                Text(String(localized: "settings.quick-access.recording"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        } else if let shortcut = model.shortcut {
            HStack(spacing: 3) {
                ForEach(Array(shortcut.description.enumerated()), id: \.offset) { _, symbol in
                    ShortcutKeyCap(String(symbol))
                }
            }
            .padding(.trailing, 16)
        } else {
            Text(String(localized: "settings.quick-access.record"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 快速呼出快捷键的录制状态与存储。
///
/// 录制期间临时禁用全局快捷键，避免用户正在按的组合直接触发面板开关。
@MainActor
private final class QuickAccessShortcutModel: ObservableObject {
    @Published private(set) var shortcut: KeyboardShortcuts.Shortcut?
    @Published private(set) var isRecording = false

    private let name = KeyboardShortcuts.Name.togglePinnedPanel
    private var monitor: Any?

    init() {
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        // 防止录制时按下当前组合直接触发面板。
        KeyboardShortcuts.disable(name)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        KeyboardShortcuts.enable(name)
    }

    func clear() {
        stopRecording()
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcut = nil
    }

    /// 处理录制期间的按键事件，返回 `nil` 表示已消费事件。
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifierKey = !flags.subtracting([.shift, .function]).isEmpty

        // Esc 取消录制。
        if event.keyCode == 53, flags.isEmpty {
            stopRecording()
            return nil
        }

        // 无修饰键的删除键清除已有快捷键。
        if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty {
            clear()
            return nil
        }

        // 至少需要一个 Command/Control/Option 修饰键，或为功能键（F1-F31）。
        let isFunctionKey: Bool = {
            guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value else {
                return false
            }
            return (0xF704...0xF71E).contains(scalar)
        }()
        guard hasModifierKey || isFunctionKey,
              let recorded = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }

        KeyboardShortcuts.setShortcut(recorded, for: name)
        shortcut = recorded
        stopRecording()
        return nil
    }
}

private struct ShortcutKeyCap: View {
    let symbol: String
    var compact: Bool

    init(_ symbol: String, compact: Bool = false) {
        self.symbol = symbol
        self.compact = compact
    }

    var body: some View {
        Text(symbol)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .frame(minWidth: compact ? 15 : 18, minHeight: compact ? 15 : 18)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: compact ? 3 : 4, style: .continuous))
    }
}

private struct MenuBarDisplaySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    var body: some View {
        SettingsGroup(String(localized: "settings.menu-bar")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "menu-bar-display.preview"))
                    .font(.body.weight(.medium))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Spacer(minLength: 0)

                        preview
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.55), in: Capsule())

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            SettingsDivider()

            SettingsRow(title: String(localized: "menu-bar-display.mode")) {
                Picker(String(localized: "menu-bar-display.mode"), selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .compatibleTabPickerStyle()
                .frame(width: 220)
            }

            if settings.menuBarDisplayMode == .metrics {
                SettingsDivider()

                SettingsRow(title: String(localized: "menu-bar-metric-layout.style")) {
                    Picker(String(localized: "menu-bar-metric-layout.style"), selection: $settings.menuBarMetricLayoutStyle) {
                        ForEach(MenuBarMetricLayoutStyle.allCases) { layoutStyle in
                            Text(layoutStyle.title).tag(layoutStyle)
                        }
                    }
                    .labelsHidden()
                    .compatibleTabPickerStyle()
                    .frame(width: 210)
                }

                SettingsDivider()

                SettingsRow(
                    title: String(localized: "menu-bar-display.metrics-title"),
                    subtitle: String(localized: "menu-bar-display.metrics-minimum")
                ) {
                    Text("\(settings.menuBarMetricKinds.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                Text(String(localized: "menu-bar-display.metrics-selected"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                selectedMetricsList(selectedMetricKinds)

                if !availableMetricKinds.isEmpty {
                    SettingsDivider()

                    Text(String(localized: "menu-bar-display.metrics-available"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(availableMetricKinds) { kind in
                            MenuBarMetricRow(
                                kind: kind,
                                isSelected: false,
                                isEnabled: true,
                                showsMoveButtons: false,
                                canMoveUp: false,
                                canMoveDown: false,
                                toggle: { settings.setMenuBarMetric(kind, selected: true) },
                                moveUp: {},
                                moveDown: {}
                            )

                            if kind != availableMetricKinds.last {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectableMetricKinds: [MenuBarMetricKind] {
        MenuBarMetricKind.userSelectableCases(hasFan: store.fanAvailable)
    }

    private var selectedMetricKinds: [MenuBarMetricKind] {
        settings.menuBarMetricKinds.filter { selectableMetricKinds.contains($0) }
    }

    private var availableMetricKinds: [MenuBarMetricKind] {
        selectableMetricKinds.filter { !settings.menuBarMetricKinds.contains($0) }
    }

    @ViewBuilder
    private func selectedMetricsList(_ kinds: [MenuBarMetricKind]) -> some View {
        let content = VStack(spacing: 0) {
            selectedMetricRows(kinds)
        }

        if #available(macOS 27.0, *) {
            content.reorderContainer(
                for: MenuBarMetricKind.self,
                itemID: \.self,
                isEnabled: kinds.count > 1
            ) { difference in
                reorderSelectedMetrics(difference)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func selectedMetricRows(_ kinds: [MenuBarMetricKind]) -> some View {
        if #available(macOS 27.0, *) {
            ForEach(kinds) { kind in
                selectedMetricRow(kind, showsMoveButtons: false, kinds: kinds)
            }
            .reorderable()
        } else {
            ForEach(kinds) { kind in
                selectedMetricRow(kind, showsMoveButtons: true, kinds: kinds)
            }
        }
    }

    private func selectedMetricRow(
        _ kind: MenuBarMetricKind,
        showsMoveButtons: Bool,
        kinds: [MenuBarMetricKind]
    ) -> some View {
        VStack(spacing: 0) {
            MenuBarMetricRow(
                kind: kind,
                isSelected: true,
                isEnabled: kinds.count > 1,
                showsMoveButtons: showsMoveButtons,
                canMoveUp: kinds.first != kind,
                canMoveDown: kinds.last != kind,
                toggle: { settings.setMenuBarMetric(kind, selected: false) },
                moveUp: { settings.moveMenuBarMetric(kind, direction: -1) },
                moveDown: { settings.moveMenuBarMetric(kind, direction: 1) }
            )

            if kind != kinds.last {
                SettingsDivider()
            }
        }
    }

    @available(macOS 27.0, *)
    private func reorderSelectedMetrics(
        _ difference: ReorderDifference<MenuBarMetricKind, ReorderableSingleCollectionIdentifier>
    ) {
        switch difference.destination.position {
        case .before(let destination):
            settings.reorderMenuBarMetrics(difference.sources, before: destination)
        case .end:
            settings.reorderMenuBarMetrics(difference.sources, before: nil)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if settings.menuBarDisplayMode == .ring {
            Image(nsImage: MenuBarComputeRingIcon.image(
                load: store.loadAnimator.displayedComputeLoad,
                darkMode: NSApp.effectiveAppearance.isDark,
                loadLevel: store.haloRingLoadLevel
            ))
            .resizable()
            // 与菜单栏里的实际图标同尺寸(21pt 画布,环本体 18pt)。
            .frame(width: 21, height: 21)
        } else {
            MenuBarMetricLabel(
                items: store.previewMenuBarMetricItems(),
                style: .preview,
                layoutStyle: settings.menuBarMetricLayoutStyle
            )
        }
    }
}

/// 菜单栏指标行:勾选态、图标、名称与(legacy fallback 下的已选项)上下排序手柄同处一行。
/// macOS 27 的已选项由容器级重排手势调整顺序,备选项只负责加入已选集合。
private struct MenuBarMetricRow: View {
    let kind: MenuBarMetricKind
    let isSelected: Bool
    /// 是否可切换:最后一个已选指标不可取消,备选指标始终可以加入。
    let isEnabled: Bool
    /// macOS 27 使用容器级原生重排;旧系统显示上下按钮作为 fallback。
    let showsMoveButtons: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let toggle: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 16, height: 16)

                    Image(systemName: kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEnabled ? .secondary : .tertiary)
                        .frame(width: 18)

                    Text(kind.title)
                        .font(.body)
                        .foregroundStyle(isEnabled ? .primary : .secondary)

                    Spacer(minLength: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if isSelected, showsMoveButtons {
                HStack(spacing: 6) {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveUp)
                    .accessibilityLabel(String(localized: "menu-bar-metric.move-up"))

                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveDown)
                    .accessibilityLabel(String(localized: "menu-bar-metric.move-down"))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

// MARK: - 使用打卡(默认折叠)

struct UsageCheckinCard: View {
    @ObservedObject var recorder: StatisticsRecorder
    @State private var showCheckin = false
    @State private var dayCoverage: [Int64: Double] = [:]

    var body: some View {
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
}
