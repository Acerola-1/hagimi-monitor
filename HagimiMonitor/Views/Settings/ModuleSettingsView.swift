import SwiftUI

struct ModuleSettingsView: View {
    let kind: MonitorKind
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.show-in-panel")) {
                    Toggle("", isOn: Binding(
                        get: { settings.isVisible(kind) },
                        set: { settings.setVisible($0, for: kind) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            SettingsGroup(String(localized: "settings.metrics")) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 0) {
                    ForEach(kind.availableMetrics) { metric in
                        let isSelected = settings.isMetricEnabled(metric.id, for: kind)
                        MetricSelectionRow(
                            title: metric.title,
                            isSelected: isSelected,
                            isEnabled: settings.canEnableMetric(metric.id, for: kind)
                        ) {
                            settings.setMetric(metric.id, enabled: !isSelected, for: kind)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                if #available(macOS 26, *) {
                    Button(String(localized: "settings.reset-defaults")) {
                        settings.resetMetrics(for: kind)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button(String(localized: "settings.reset-defaults")) {
                        settings.resetMetrics(for: kind)
                    }
                }
            }
        }
    }
}

private struct MetricSelectionRow: View {
    let title: String
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

                Text(title)
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

#if DISPLAY_CONTROL
struct DisplayModuleSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.show-in-panel")) {
                    Toggle("", isOn: $settings.displayModuleVisible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.include-built-in")) {
                    Toggle("", isOn: $settings.showBuiltInDisplays)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup(String(localized: "settings.controls")) {
                SettingsRow(title: String(localized: "settings.brightness")) {
                    Toggle("", isOn: $settings.displayBrightnessControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.volume")) {
                    Toggle("", isOn: $settings.displayVolumeControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.contrast")) {
                    Toggle("", isOn: $settings.displayContrastControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            MediaKeySettingsSection(
                settings: settings,
                permission: AccessibilityPermissionService.shared
            )

            SettingsTip(String(localized: "settings.display.ddc-note"))
        }
    }
}
#endif
