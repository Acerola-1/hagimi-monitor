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
                ForEach(MonitorKind.userVisibleCases) { kind in
                    Label(kind.title, systemImage: kind.symbol)
                        .tag(SettingsRoute.module(kind))
                }

                #if DISPLAY_CONTROL
                HStack(spacing: 6) {
                    Label(String(localized: "settings.sidebar.display"), systemImage: "display")
                    BetaBadge()
                }
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

#if DISPLAY_CONTROL
private struct BetaBadge: View {
    var body: some View {
        Text(String(localized: "settings.sidebar.beta-badge"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}
#endif
