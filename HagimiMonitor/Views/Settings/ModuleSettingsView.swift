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

                // 模块隐藏后「显示方式/默认展开」无意义,随 moduleOptions 一起隐藏。
                if settings.isVisible(kind) {
                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.display-style")) {
                        Picker(String(localized: "settings.display-style"), selection: Binding(
                            get: { settings.isCardStyle(kind) ? ModuleDisplayStyle.card : .list },
                            set: { settings.setCardStyle($0 == .card, for: kind) }
                        )) {
                            Text(String(localized: "settings.display-style.list")).tag(ModuleDisplayStyle.list)
                            Text(String(localized: "settings.display-style.card")).tag(ModuleDisplayStyle.card)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    // 卡片内容常显,「默认展开」对其无意义:隐藏开关但不清除持久值,
                    // 切回列表行即恢复生效。
                    if !settings.isCardStyle(kind) {
                        SettingsDivider()

                        SettingsRow(
                            title: String(localized: "settings.expand-by-default"),
                            subtitle: String(localized: "settings.expand-by-default.subtitle")
                        ) {
                            Toggle("", isOn: Binding(
                                get: { settings.isExpandedByDefault(kind) },
                                set: { settings.setExpandedByDefault($0, for: kind) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                    }
                }
            }

            // 模块关闭后，下方的指标 / 进程 / 重置等选项都失去意义，直接隐藏。
            if settings.isVisible(kind) {
                moduleOptions
            }
        }
        .animation(.default, value: settings.isVisible(kind))
    }

    @ViewBuilder
    private var moduleOptions: some View {
            SettingsGroup(String(localized: "settings.metrics")) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 0) {
                    ForEach(availableMetrics) { metric in
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

            if kind == .memory {
                SettingsGroup {
                    SettingsRow(title: String(localized: "settings.memory.primary-metric")) {
                        Picker(String(localized: "settings.memory.primary-metric"), selection: $settings.memoryPrimaryMetric) {
                            ForEach(MemoryPrimaryMetricPreference.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    SettingsDivider()

                    // App Store 沙盒版无法采样他进程,隐藏进程列表相关设置。
                    #if DIRECT_DISTRIBUTION
                    SettingsRow(title: String(localized: "settings.show-memory-processes")) {
                        Toggle("", isOn: $settings.showMemoryProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.memory.show-system-processes")) {
                        Toggle("", isOn: $settings.memoryShowSystemProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    #endif
                }
            }

            // App Store 沙盒版无法采样他进程,隐藏 CPU 进程列表设置。
            #if DIRECT_DISTRIBUTION
            if kind == .cpu {
                SettingsGroup {
                    SettingsRow(title: String(localized: "settings.show-cpu-processes")) {
                        Toggle("", isOn: $settings.showCPUProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.cpu.show-system-processes")) {
                        Toggle("", isOn: $settings.cpuShowSystemProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            #endif

            // App Store 沙盒版无法采样他进程,隐藏存储进程列表设置。
            #if DIRECT_DISTRIBUTION
            if kind == .storage {
                SettingsGroup {
                    SettingsRow(title: String(localized: "settings.show-disk-processes")) {
                        Toggle("", isOn: $settings.showDiskProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.disk.show-system-processes")) {
                        Toggle("", isOn: $settings.diskShowSystemProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            #endif

            // App Store 沙盒版无法采样网络他进程,隐藏网络进程列表设置。
            #if DIRECT_DISTRIBUTION
            if kind == .network {
                SettingsGroup {
                    SettingsRow(title: String(localized: "settings.show-network-processes")) {
                        Toggle("", isOn: $settings.showNetworkProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.network.show-system-processes")) {
                        Toggle("", isOn: $settings.networkShowSystemProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
            #endif

            if #available(macOS 26, *) {
                Button(String(localized: "settings.reset-defaults")) {
                    settings.resetMetrics(for: kind)
                }
                .compatibleButtonStyle()
            } else {
                Button(String(localized: "settings.reset-defaults")) {
                    settings.resetMetrics(for: kind)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
    }

    /// 监测项目列表与面板实际显示保持一致:压力模式下面板里「压力」槽位
    /// 实际显示「使用率」,列表同步换名;开关仍存储在 pressure id 上,
    /// 两种模式共用同一槽位状态,来回切换不丢设置。
    private var availableMetrics: [MetricSwitch] {
        guard kind == .memory, settings.memoryPrimaryMetric == .pressure else {
            return kind.availableMetrics
        }
        return kind.availableMetrics.map { metric in
            metric.id == "pressure"
                ? MetricSwitch(id: metric.id, title: String(localized: "metric.memory.usage"), isDefault: metric.isDefault)
                : metric
        }
    }
}

/// 设置页分段选择器的 UI 局部枚举:存储层仍是 cardStyleKinds 集合(见 MonitorSettings)。
private enum ModuleDisplayStyle: Hashable {
    case list
    case card
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

                if settings.displayModuleVisible {
                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.include-built-in")) {
                        Toggle("", isOn: $settings.showBuiltInDisplays)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: String(localized: "settings.expand-by-default"),
                        subtitle: String(localized: "settings.expand-by-default.subtitle")
                    ) {
                        Toggle("", isOn: $settings.displayControlsExpandedByDefault)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }

            // 模块关闭后，下方的控制项 / 媒体键 / 说明都失去意义，直接隐藏。
            if settings.displayModuleVisible {
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
        .animation(.default, value: settings.displayModuleVisible)
    }
}
#endif
