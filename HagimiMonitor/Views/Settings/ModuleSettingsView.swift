import SwiftUI

struct ModuleSettingsView: View {
    let kind: MonitorKind
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        Form {
            Section {
                Toggle("在面板中显示", isOn: Binding(
                    get: { settings.isVisible(kind) },
                    set: { settings.setVisible($0, for: kind) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

#if DISPLAY_CONTROL
struct DisplayModuleSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        Form {
            Section {
                Toggle("在面板中显示", isOn: $settings.displayModuleVisible)
                Toggle("包含内置显示器", isOn: $settings.showBuiltInDisplays)
            }

            Section("控制项") {
                Toggle("亮度", isOn: $settings.displayBrightnessControlEnabled)
                Toggle("音量", isOn: $settings.displayVolumeControlEnabled)
                Toggle("对比度", isOn: $settings.displayContrastControlEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
#endif
