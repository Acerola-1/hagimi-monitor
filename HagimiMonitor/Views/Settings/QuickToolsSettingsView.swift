import SwiftUI

/// 设置「小工具」:控制面板底部工具入口的显隐与浮层中各工具磁贴的显隐。
/// 工具列表由 QuickToolKind 的 CaseIterable 驱动,新增工具只需补枚举 case
/// 与本地化,本页与浮层自动跟随,无需逐处改动。
struct QuickToolsSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.show-in-panel")) {
                    Toggle("", isOn: $settings.quickToolsVisible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            // 入口关闭后,工具显隐列表失去意义,直接隐藏(与模块页一致)。
            if settings.quickToolsVisible {
                SettingsGroup(String(localized: "settings.quick-tools.group")) {
                    ForEach(QuickToolKind.allCases, id: \.self) { kind in
                        SettingsRow(title: String(localized: kind.titleKey)) {
                            Toggle("", isOn: Binding(
                                get: { settings.isQuickToolVisible(kind) },
                                set: { settings.setQuickToolVisible($0, for: kind) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        if kind != QuickToolKind.allCases.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
        .animation(.default, value: settings.quickToolsVisible)
    }
}
