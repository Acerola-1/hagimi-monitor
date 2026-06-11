import SwiftUI

enum SettingsRoute: Hashable {
    case general
    case module(MonitorKind)
    #if DISPLAY_CONTROL
    case displayModule
    #endif
    case about
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsRoute
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("常规", systemImage: "gearshape")
                    .tag(SettingsRoute.general)
            }

            Section("监控模块") {
                ForEach(MonitorKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .tag(SettingsRoute.module(kind))
                }

                #if DISPLAY_CONTROL
                Label("显示器", systemImage: "display")
                    .tag(SettingsRoute.displayModule)
                #endif
            }

            Section {
                Label("关于", systemImage: "info.circle")
                    .tag(SettingsRoute.about)
            }
        }
        .listStyle(.sidebar)
        .controlSize(.small)
        .font(.callout)
    }
}
