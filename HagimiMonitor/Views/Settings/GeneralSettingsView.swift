import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.launch-at-login")) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup(String(localized: "settings.appearance")) {
                SettingsRow(title: String(localized: "settings.theme")) {
                    Picker(String(localized: "settings.theme"), selection: $settings.themePreference) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.color-scheme")) {
                    Picker(String(localized: "settings.color-scheme"), selection: $settings.colorSchemePreference) {
                        ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                            Text(colorScheme.title).tag(colorScheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            MenuBarDisplaySettingsSection(settings: settings, store: store)
        }
    }
}

private struct MenuBarDisplaySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    var body: some View {
        SettingsGroup(String(localized: "settings.menu-bar")) {
            SettingsRow(title: String(localized: "menu-bar-display.mode")) {
                Picker(String(localized: "menu-bar-display.mode"), selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            SettingsDivider()

            SettingsRow(title: String(localized: "menu-bar-display.preview")) {
                if settings.menuBarDisplayMode == .ring {
                    Image(nsImage: MenuBarComputeRingIcon.image(
                        load: store.displayedComputeLoad,
                        darkMode: NSApp.effectiveAppearance.isDark,
                        loadLevel: store.haloRingLoadLevel
                    ))
                    .resizable()
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.55), in: Capsule())
                } else {
                    MenuBarMetricLabel(items: store.previewMenuBarMetricItems())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                }
            }

            if settings.menuBarDisplayMode == .metrics {
                SettingsRow(
                    title: String(localized: "menu-bar-display.metrics-title"),
                    subtitle: String(localized: "menu-bar-display.metrics-limit")
                ) {
                    Text("\(settings.menuBarMetricKinds.count)/\(MenuBarMetricKind.maximumSelectionCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                VStack(spacing: 0) {
                    ForEach(MenuBarMetricKind.allCases) { kind in
                        MenuBarMetricSelectionRow(
                            kind: kind,
                            isSelected: settings.isMenuBarMetricSelected(kind),
                            isEnabled: settings.canSelectMenuBarMetric(kind)
                        ) {
                            settings.setMenuBarMetric(kind, selected: !settings.isMenuBarMetricSelected(kind))
                        }

                        if kind != MenuBarMetricKind.allCases.last {
                            SettingsDivider()
                        }
                    }
                }

                SettingsDivider()

                VStack(spacing: 0) {
                    ForEach(settings.menuBarMetricKinds) { kind in
                        MenuBarMetricOrderRow(
                            kind: kind,
                            canMoveUp: settings.menuBarMetricKinds.first != kind,
                            canMoveDown: settings.menuBarMetricKinds.last != kind,
                            moveUp: { settings.moveMenuBarMetric(kind, direction: -1) },
                            moveDown: { settings.moveMenuBarMetric(kind, direction: 1) }
                        )

                        if kind != settings.menuBarMetricKinds.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }
}

private struct MenuBarMetricSelectionRow: View {
    let kind: MenuBarMetricKind
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct MenuBarMetricOrderRow: View {
    let kind: MenuBarMetricKind
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        SettingsRow(title: kind.title) {
            HStack(spacing: 6) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.bordered)
        }
    }
}
