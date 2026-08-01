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
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updateService = UpdateService.shared
    #endif

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
                    Label(String(localized: "settings.sidebar.display"), systemImage: "slider.horizontal.below.rectangle")
                    BetaBadge()
                }
                .tag(SettingsRoute.displayModule)
                #endif
            }

            Section {
                #if DIRECT_DISTRIBUTION
                HStack(spacing: 6) {
                    Label(String(localized: "settings.sidebar.about"), systemImage: "info.circle")
                    if updateService.availableUpdateVersion != nil {
                        UpdateAvailableBadge()
                    }
                }
                .tag(SettingsRoute.about)
                #else
                Label(String(localized: "settings.sidebar.about"), systemImage: "info.circle")
                    .tag(SettingsRoute.about)
                #endif
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

#if DIRECT_DISTRIBUTION
private struct UpdateAvailableBadge: View {
    var body: some View {
        Text(String(localized: "settings.sidebar.new-badge"))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.orange.opacity(0.15), in: Capsule())
    }
}
#endif
