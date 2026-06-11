import SwiftUI

struct ModuleSettingsView: View {
    let kind: MonitorKind
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: "在面板中显示") {
                    Toggle("", isOn: Binding(
                        get: { settings.isVisible(kind) },
                        set: { settings.setVisible($0, for: kind) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            SettingsGroup("监测项目") {
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
            Text("最多选择 \(MonitorSettings.maximumEnabledMetricsPerKind) 项用于主面板展示。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack {
                Spacer()
                if #available(macOS 26, *) {
                    Button("重置默认值") {
                        settings.resetMetrics(for: kind)
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("重置默认值") {
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
                SettingsRow(title: "在面板中显示") {
                    Toggle("", isOn: $settings.displayModuleVisible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: "包含内置显示器") {
                    Toggle("", isOn: $settings.showBuiltInDisplays)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("控制项") {
                SettingsRow(title: "亮度") {
                    Toggle("", isOn: $settings.displayBrightnessControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: "音量") {
                    Toggle("", isOn: $settings.displayVolumeControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: "对比度") {
                    Toggle("", isOn: $settings.displayContrastControlEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}
#endif
