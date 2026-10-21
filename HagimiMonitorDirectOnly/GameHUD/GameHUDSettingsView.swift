import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Game HUD 设置页:总开关 → 外观(样式/位置/背景透明度/局部预览)
/// → 监控项目 → 应用与游戏名单 → 已排除。
///
/// 名单以统一登记为唯一数据源:自动识别结果直接出现在启用名单,
/// 行内固定提供排除;黑名单独立成组,始终提供添加排除与逐行恢复。
/// 仅官网版提供游戏 HUD 设置。
struct GameHUDSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @StateObject private var model: GameHUDSettingsModel
    @State private var previewBackground: GameHUDPreviewBackground = .bright

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
            gameListGroup
                .id("gamehud-games")
            excludedGroup
                .id("gamehud-excluded")
        }
        .onAppear {
            model.onAppear()
        }
    }

    // MARK: - 总开关

    private var masterGroup: some View {
        SettingsGroup {
            SettingsRow(title: String(localized: "gamehud.settings.master-enabled")) {
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
                    .frame(width: 200)
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
                        .frame(width: 200)
                    }
                }

                SettingsDivider()
                transparencyRow
                SettingsDivider()
                transparencyHint
                previewBlock
            }
        }
    }

    private var transparencyRow: some View {
        SettingsRow(title: String(localized: "gamehud.appearance.transparency")) {
            HStack(spacing: 10) {
                Slider(
                    value: transparencyBinding,
                    in: 0...1,
                    step: GameHUDBackgroundAppearance.step
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

    /// 说明与恢复默认同排:恢复默认是文字按钮,不需要把操作藏进图标提示。
    private var transparencyHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(localized: "gamehud.appearance.transparency.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(String(localized: "gamehud.appearance.transparency.reset")) {
                settings.resetGameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .fixedSize()
            .disabled(isDefaultTransparency)
            .accessibilityLabel(Text(String(localized: "gamehud.appearance.transparency.reset")))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(String(localized: "gamehud.appearance.preview"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                previewBackgroundMenu
            }
            GameHUDAppearancePreview(
                style: settings.gameHUDPresentationStyle,
                transparency: settings.gameHUDBackgroundTransparency(for: settings.gameHUDPresentationStyle),
                background: previewBackground
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
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
        SettingsGroup(String(localized: "gamehud.settings.metrics")) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(GameHUDMetricCatalog.availableEntries()) { entry in
                    SettingsRow(title: String(localized: entry.titleKey)) {
                        Toggle("", isOn: metricBinding(entry.id))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel(Text(String(localized: entry.titleKey)))
                    }
                }
                SettingsDivider()
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "gamehud.settings.fps-availability"))
                    Text(String(localized: "gamehud.settings.cpu-power-availability"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
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

    // MARK: - 应用与游戏

    private var gameListGroup: some View {
        SettingsGroup(
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
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                let apps = settings.gameHUDRegistry.enabledApps
                if apps.isEmpty {
                    emptyState(String(localized: "gamehud.games.empty-state"))
                } else {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            SettingsDivider()
                        }
                        appRow(app, isExcluded: false)
                    }
                }
                feedbackLine
            }
        }
    }

    // MARK: - 已排除

    private var excludedGroup: some View {
        SettingsGroup(
            String(localized: "gamehud.excluded.title"),
            titleAccessory: {
                Button {
                    if let url = chooseApplication(
                        title: String(localized: "gamehud.excluded.add.panel-title")
                    ) {
                        model.addExclusion(at: url)
                    }
                } label: {
                    Label(String(localized: "gamehud.excluded.add"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(String(localized: "gamehud.excluded.add")))
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                let apps = settings.gameHUDRegistry.excludedApps
                if apps.isEmpty {
                    emptyState(String(localized: "gamehud.excluded.empty"))
                } else {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            SettingsDivider()
                        }
                        appRow(app, isExcluded: true)
                    }
                }
            }
        }
    }

    // MARK: - 行

    /// 图标 + 名称(紧邻标记)+ 下一行真实来源 + 固定行尾操作。
    /// 名称最多两行,来源一行;动作固定在行尾,不靠右键/悬停发现。
    private func appRow(_ app: GameHUDRegisteredApp, isExcluded: Bool) -> some View {
        let name = model.displayName(for: app)
        let available = model.packageURL(for: app) != nil
        return HStack(alignment: .center, spacing: 10) {
            Image(nsImage: model.icon(for: app))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .help(name)
                    if let badge = app.badge {
                        badgeView(badge)
                    }
                }
                Text(sourceLine(for: app, available: available))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(sourceLine(for: app, available: available))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionButton(for: app, isExcluded: isExcluded, name: name)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func badgeView(_ badge: GameHUDListBadge) -> some View {
        let title = String(localized: badge.titleKey)
        return Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Color.accentColor.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .fixedSize()
            .accessibilityLabel(Text(title))
    }

    private func actionButton(
        for app: GameHUDRegisteredApp,
        isExcluded: Bool,
        name: String
    ) -> some View {
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
                settings.setGameHUDBackgroundTransparency(newValue, for: settings.gameHUDPresentationStyle)
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
