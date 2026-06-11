import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        Form {
            Section {
                Toggle("开机自启", isOn: $settings.launchAtLogin)
            }

            Section("外观") {
                Picker("主题", selection: $settings.themePreference) {
                    ForEach(AppThemePreference.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }

                Picker("配色", selection: $settings.colorSchemePreference) {
                    ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                        Text(colorScheme.title).tag(colorScheme)
                    }
                }
            }

            Section("菜单栏") {
                Picker("负载环", selection: $settings.ringSource) {
                    ForEach(HaloRingSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
