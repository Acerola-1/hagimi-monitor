import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Game HUD 设置页:总开关 → 外观(样式/位置/背景透明度/局部预览)
/// → 监控项目 → 统一应用名单(分段切换 + 默认折叠 + 原地展开)。
///
/// 名单以统一登记为唯一数据源:自动识别结果直接出现在启用名单,
/// 行内固定提供排除;通过分段切换统一查看「已启用 / 已排除」,
/// 超出 5 项默认折叠，点击底部按钮原地展开/收起，不引入二级弹窗。
/// 仅官网版提供游戏 HUD 设置。
struct GameHUDSettingsView: View {
    private static let inlinePreviewLimit = 5

    @ObservedObject var settings: MonitorSettings
    @StateObject private var model: GameHUDSettingsModel
    @State private var previewBackground: GameHUDPreviewBackground = .bright
    @State private var selectedListTab: GameHUDAppListTab = .enabled
    @State private var isListExpanded = false
    @State private var searchText = ""

    init(settings: MonitorSettings) {
        self.settings = settings
        _model = StateObject(wrappedValue: GameHUDSettingsModel(
            settings: settings,
            scanner: .shared
        ))
    }

    var body: some View {
        SettingsPage {
            masterGroup
                .id("gamehud-master")
            appearanceGroup
                .id("gamehud-appearance")
            metricGroup
                .id("gamehud-metrics")
            appListGroup
                .id("gamehud-games")
        }
        .onAppear {
            model.onAppear()
        }
        .onChange(of: selectedListTab) { _, _ in
            isListExpanded = false
            searchText = ""
        }
    }

    // MARK: - 总开关

    private var masterGroup: some View {
        SettingsGroup {
            SettingsRow(
                title: String(localized: "gamehud.settings.master-enabled"),
                subtitle: model.statusSubtitle
            ) {
                Toggle("", isOn: $settings.gameHUDMasterEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(Text(String(localized: "gamehud.settings.master-enabled")))
            }
        }
    }

    // MARK: - 外观

    private var appearanceGroup: some View {
        SettingsGroup(String(localized: "gamehud.appearance.title")) {
            VStack(spacing: 0) {
                SettingsRow(title: String(localized: "gamehud.settings.presentation-style")) {
                    Picker(
                        String(localized: "gamehud.settings.presentation-style"),
                        selection: $settings.gameHUDPresentationStyle
                    ) {
                        Text(String(localized: "gamehud.style.top-strip")).tag(GameHUDPresentationStyle.topStrip)
                        Text(String(localized: "gamehud.style.card")).tag(GameHUDPresentationStyle.card)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                if settings.gameHUDPresentationStyle == .card {
                    SettingsDivider()
                    SettingsRow(title: String(localized: "gamehud.settings.layout")) {
                        Picker(
                            String(localized: "gamehud.layout.side"),
                            selection: $settings.gameHUDSidePreference
                        ) {
                            Text(String(localized: "gamehud.layout.top-left")).tag(GameHUDSide.topLeft)
                            Text(String(localized: "gamehud.layout.top-right")).tag(GameHUDSide.topRight)
                            Text(String(localized: "gamehud.layout.bottom-left")).tag(GameHUDSide.bottomLeft)
                            Text(String(localized: "gamehud.layout.bottom-right")).tag(GameHUDSide.bottomRight)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                SettingsDivider()
                transparencyRow
                SettingsDivider()
                previewBlock
            }
        }
    }

    private var transparencyRow: some View {
        SettingsRow(title: String(localized: "gamehud.appearance.transparency")) {
            HStack(spacing: 10) {
                // 使用连续滑杆并在绑定中按 1% 量化，避免 macOS 刻度滑杆在紧凑宽度下画出锯齿灰条。
                Slider(
                    value: transparencyBinding,
                    in: 0...1
                )
                .frame(minWidth: 110, maxWidth: 190)
                .accessibilityLabel(Text(String(localized: "gamehud.appearance.transparency")))
                .accessibilityValue(Text(transparencyPercentText))

                Text(transparencyPercentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(String(localized: "gamehud.appearance.preview"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(String(localized: "gamehud.appearance.transparency.reset")) {
                    settings.resetGameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
                .disabled(isDefaultTransparency)
                .accessibilityLabel(Text(String(localized: "gamehud.appearance.transparency.reset")))

                previewBackgroundMenu
            }
            GameHUDAppearancePreview(
                style: settings.gameHUDPresentationStyle,
                transparency: settings.gameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle),
                background: previewBackground
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var previewBackgroundMenu: some View {
        Menu {
            ForEach(GameHUDPreviewBackground.allCases) { background in
                Button {
                    previewBackground = background
                } label: {
                    if background == previewBackground {
                        Label(
                            String(localized: background.titleKey),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(String(localized: background.titleKey))
                    }
                }
            }
        } label: {
            Text(String(localized: "gamehud.appearance.preview.background \(String(localized: previewBackground.titleKey))"))
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text(String(localized: "gamehud.appearance.preview.background.accessibility")))
    }

    // MARK: - 监控项目

    private var metricGroup: some View {
        let grouped = GameHUDMetricCatalog.groupedAvailableEntries()
        let availableCount = grouped.reduce(0) { $0 + $1.entries.count }
        let selectedCount = GameHUDMetricCatalog.readableIDs(from: settings.gameHUDEnabledMetricIDs).count
        return SettingsGroup(
            String(localized: "gamehud.settings.metrics"),
            titleAccessory: {
                Text(String(localized: "gamehud.settings.metrics.count \(selectedCount) \(availableCount)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(grouped.enumerated()), id: \.element.section.id) { sectionIndex, group in
                    if sectionIndex > 0 {
                        SettingsDivider()
                    }
                    Text(String(localized: group.section.titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 11)
                        .padding(.bottom, 4)

                    ForEach(group.entries) { entry in
                        SettingsRow(title: String(localized: entry.titleKey)) {
                            Toggle("", isOn: metricBinding(entry.id))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .accessibilityLabel(Text(String(localized: entry.titleKey)))
                        }
                    }
                }
                SettingsDivider()
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    if selectedCount == 0 {
                        Text(String(localized: "gamehud.settings.metrics.empty-hint"))
                            .foregroundStyle(.orange)
                    }
                    if !model.isFPSProbeAvailable {
                        Text(String(localized: "gamehud.settings.fps-probe-unavailable"))
                    }
                    Text(String(localized: "gamehud.settings.fps-availability"))
                    Text(String(localized: "gamehud.settings.cpu-power-availability"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
    }

    private func metricBinding(_ id: GameHUDMetricID) -> Binding<Bool> {
        Binding(
            get: { settings.gameHUDEnabledMetricIDs.contains(id) },
            set: { settings.setGameHUDMetric(id, enabled: $0) }
        )
    }

    // MARK: - 应用与游戏名单(分段切换 + 默认折叠 + 原地展开)

    private var appListGroup: some View {
        let enabledApps = settings.gameHUDRegistry.enabledApps
        let excludedApps = settings.gameHUDRegistry.excludedApps
        let activeApps = selectedListTab == .enabled ? enabledApps : excludedApps
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredApps = query.isEmpty ? activeApps : filterApps(activeApps, query: query)
        let canCollapse = query.isEmpty && activeApps.count > Self.inlinePreviewLimit
        let visibleApps = (canCollapse && !isListExpanded)
            ? Array(filteredApps.prefix(Self.inlinePreviewLimit))
            : filteredApps

        return SettingsGroup(
            String(localized: "gamehud.games.title"),
            titleAccessory: {
                HStack(spacing: 8) {
                    if model.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel(Text(String(localized: "gamehud.games.scanning")))
                    }
                    Button {
                        model.rescan()
                    } label: {
                        Label(String(localized: "gamehud.games.rescan"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                    .accessibilityLabel(Text(String(localized: "gamehud.games.rescan")))

                    if selectedListTab == .enabled {
                        Button {
                            if let url = chooseApplication(
                                title: String(localized: "gamehud.games.add-app.panel-title")
                            ) {
                                model.addApplication(at: url)
                            }
                        } label: {
                            Label(String(localized: "gamehud.games.add-app"), systemImage: "plus")
                        }
                        .accessibilityLabel(Text(String(localized: "gamehud.games.add-app")))
                    } else {
                        Button {
                            if let url = chooseApplication(
                                title: String(localized: "gamehud.excluded.add.panel-title")
                            ) {
                                model.addExclusion(at: url)
                            }
                        } label: {
                            Label(String(localized: "gamehud.excluded.add"), systemImage: "plus")
                        }
                        .accessibilityLabel(Text(String(localized: "gamehud.excluded.add")))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Picker(
                        String(localized: "gamehud.games.title"),
                        selection: $selectedListTab
                    ) {
                        Text(String(localized: "gamehud.list.tab.enabled \(enabledApps.count)"))
                            .tag(GameHUDAppListTab.enabled)
                        Text(String(localized: "gamehud.list.tab.excluded \(excludedApps.count)"))
                            .tag(GameHUDAppListTab.excluded)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    Spacer(minLength: 8)

                    if activeApps.count > Self.inlinePreviewLimit || !searchText.isEmpty {
                        inlineSearchField
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                SettingsDivider()

                if activeApps.isEmpty {
                    emptyState(
                        selectedListTab == .enabled
                            ? String(localized: "gamehud.games.empty-state")
                            : String(localized: "gamehud.excluded.empty")
                    )
                } else if visibleApps.isEmpty {
                    emptyState(String(localized: "gamehud.list.search.empty"))
                } else {
                    ForEach(Array(visibleApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            SettingsDivider()
                        }
                        GameHUDAppRow(
                            app: app,
                            isExcluded: selectedListTab == .excluded,
                            model: model
                        )
                    }
                    if canCollapse {
                        SettingsDivider()
                        expandToggleRow(totalCount: activeApps.count)
                    }
                }

                feedbackLine
            }
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "gamehud.list.search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "gamehud.list.search.clear")))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 200)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func expandToggleRow(totalCount: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isListExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(
                    isListExpanded
                        ? String(localized: "gamehud.list.collapse")
                        : String(localized: "gamehud.list.expand-all \(totalCount)")
                )
                .font(.callout.weight(.medium))
                Image(systemName: isListExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func filterApps(_ apps: [GameHUDRegisteredApp], query: String) -> [GameHUDRegisteredApp] {
        apps.filter { app in
            let name = model.displayName(for: app)
            if name.localizedCaseInsensitiveContains(query) { return true }
            if app.bundleID.localizedCaseInsensitiveContains(query) { return true }
            if let source = app.primarySource,
               String(localized: source.titleKey).localizedCaseInsensitiveContains(query) {
                return true
            }
            return false
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private var feedbackLine: some View {
        if let feedback = model.feedback {
            SettingsDivider()
            Text(feedback.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    // MARK: - 工具

    private var transparencyBinding: Binding<Double> {
        Binding(
            get: {
                settings.gameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle)
            },
            set: { newValue in
                let quantized = (newValue / GameHUDBackgroundAppearance.step).rounded() * GameHUDBackgroundAppearance.step
                settings.setGameHUDBackgroundTransparency(quantized, for: settings.gameHUDPresentationStyle)
            }
        )
    }

    private var transparencyPercentText: String {
        let percent = GameHUDBackgroundAppearance.percent(
            settings.gameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle),
            for: settings.gameHUDPresentationStyle
        )
        return "\(percent)%"
    }

    private var isDefaultTransparency: Bool {
        settings.gameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle)
            == GameHUDBackgroundAppearance.defaultTransparency(for: settings.gameHUDPresentationStyle)
    }

    private func chooseApplication(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}

// MARK: - 应用名单分段与行视图

private enum GameHUDAppListTab: String, CaseIterable, Identifiable {
    case enabled
    case excluded

    var id: String { rawValue }
}

/// 紧凑应用行：24pt 图标 + 名称与标记 + 来源 + 固定行尾操作，复用于设置页预览与管理弹窗。
private struct GameHUDAppRow: View {
    let app: GameHUDRegisteredApp
    let isExcluded: Bool
    @ObservedObject var model: GameHUDSettingsModel

    var body: some View {
        let name = model.displayName(for: app)
        let available = model.packageURL(for: app) != nil
        let source = sourceLine(for: app, available: available)
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: model.icon(for: app))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(name)
                    if let badge = app.badge {
                        badgeView(badge)
                    }
                }
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(source)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(name: name)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func badgeView(_ badge: GameHUDListBadge) -> some View {
        let title = String(localized: badge.titleKey)
        return Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Color.accentColor.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .fixedSize()
            .accessibilityLabel(Text(title))
    }

    private func actionButton(name: String) -> some View {
        let title = isExcluded
            ? String(localized: "gamehud.excluded.remove")
            : String(localized: "gamehud.games.exclude")
        let accessibility = isExcluded
            ? String(localized: "gamehud.excluded.remove.accessibility \(name)")
            : String(localized: "gamehud.games.exclude.accessibility \(name)")
        return Button(title) {
            if isExcluded {
                model.removeExclusion(app)
            } else {
                model.exclude(app)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(Text(accessibility))
    }

    private func sourceLine(for app: GameHUDRegisteredApp, available: Bool) -> String {
        var parts: [String] = []
        if let source = app.primarySource {
            parts.append(String(localized: source.titleKey))
        } else if app.manualOrigin != nil {
            parts.append(String(localized: "gamehud.games.source.manual"))
        }
        if parts.isEmpty {
            parts.append(String(localized: "gamehud.games.source.unrecognized"))
        }
        if !available {
            parts.append(String(localized: "gamehud.games.package-missing"))
        }
        return parts.joined(separator: " · ")
    }
}
