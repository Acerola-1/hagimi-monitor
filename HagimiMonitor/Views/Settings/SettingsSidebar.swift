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
                Label(String(localized: "settings.sidebar.general"), systemImage: "gearshape")
                    .tag(SettingsRoute.general)
            }

            Section {
                ForEach(MonitorKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .tag(SettingsRoute.module(kind))
                }

                #if DISPLAY_CONTROL
                Label(String(localized: "settings.sidebar.display"), systemImage: "display")
                    .tag(SettingsRoute.displayModule)
                #endif
            }

            Section {
                Label(String(localized: "settings.sidebar.about"), systemImage: "info.circle")
                    .tag(SettingsRoute.about)
            }
        }
        .listStyle(.sidebar)
        .controlSize(.small)
        .font(.callout)
    }
}
