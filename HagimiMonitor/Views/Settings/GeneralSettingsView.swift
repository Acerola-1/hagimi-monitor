import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: "开机自启", subtitle: "登录后自动打开 HagimiMonitor") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("外观") {
                SettingsRow(title: "主题") {
                    Picker("主题", selection: $settings.themePreference) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsDivider()

                SettingsRow(title: "配色") {
                    Picker("配色", selection: $settings.colorSchemePreference) {
                        ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                            Text(colorScheme.title).tag(colorScheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup("菜单栏") {
                SettingsRow(title: "负载环") {
                    Picker("负载环", selection: $settings.ringSource) {
                        ForEach(HaloRingSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}
