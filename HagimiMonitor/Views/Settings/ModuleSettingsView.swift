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
                // 「默认展开」融入「监测项目」卡:开关决定是否自动摊开,网格决定摊开后显示哪些项,
                // 一张卡承载「展开 →(下列)监测项目」的因果整体。
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

                SettingsDivider()

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

                    // 内存列表数据源(sysctl + proc_pidinfo)沙盒可用,双渠道均开放设置。
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
                }
            }

            // CPU 列表数据源沙盒可用(直连版走 ps,沙盒版走 TASKINFO 差分),
            // 双渠道均开放设置。
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

            // GPU 进程列表数据源为 IORegistry 只读属性(AGX user client 的
            // AppUsage),沙盒允许,双渠道均可用,故不加 DIRECT_DISTRIBUTION 门控。
            if kind == .gpu {
                SettingsGroup {
                    SettingsRow(title: String(localized: "settings.show-gpu-processes")) {
                        Toggle("", isOn: $settings.showGPUProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsDivider()

                    SettingsRow(title: String(localized: "settings.gpu.show-system-processes")) {
                        Toggle("", isOn: $settings.gpuShowSystemProcesses)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }

            // 存储列表依赖 proc_pid_rusage,沙盒下跨进程调用被策略拒绝,
            // App Store 版隐藏存储进程列表设置。
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

            // 网络列表依赖 nettop 私有通道,沙盒下不可用,App Store 版隐藏网络进程列表设置。
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

            // 功率流(Beta):双渠道均可用(数据源为 IORegistry 只读属性,沙盒允许),故不加 DIRECT_DISTRIBUTION 门控。
            if kind == .battery {
                SettingsGroup {
                    SettingsRow(
                        title: String(localized: "settings.battery.show-power-flow"),
                        subtitle: String(localized: "settings.battery.show-power-flow.subtitle")
                    ) {
                        HStack(spacing: 6) {
                            PowerFlowBetaBadge()
                            Toggle("", isOn: $settings.batteryShowPowerFlow)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
            }

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

/// 小号 Beta 胶囊徐章:用于标注实验性设置项(如功率流),与侧边栏 BetaBadge 同样式。
private struct PowerFlowBetaBadge: View {
    var body: some View {
        Text(String(localized: "settings.sidebar.beta-badge"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.15), in: Capsule())
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
#else
/// 显示器信息行设置页(App Store 渠道):无控制能力,仅面板可见性开关。
struct DisplayInfoSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.show-in-panel")) {
                    Toggle("", isOn: $settings.displayModuleVisible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }
}
#endif
