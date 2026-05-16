import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)

            Divider()

            SettingsDetailPane(selection: selection, settings: settings)
        }
        .frame(width: 600, height: 360)
        .background(.regularMaterial)
    }
}

private enum SettingsSection: Hashable, Identifiable {
    case general
    case module(MonitorKind)

    var id: String {
        switch self {
        case .general:
            "general"
        case .module(let kind):
            kind.id
        }
    }

    var title: String {
        switch self {
        case .general:
            "常规"
        case .module(let kind):
            kind.title
        }
    }

    var symbol: String {
        switch self {
        case .general:
            "gearshape"
        case .module(let kind):
            kind.symbol
        }
    }

    static let all: [SettingsSection] = [
        .general,
        .module(.cpu),
        .module(.gpu),
        .module(.memory),
        .module(.storage),
        .module(.network),
        .module(.battery)
    ]
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 42)

            VStack(spacing: 2) {
                ForEach(SettingsSection.all) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 10)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出应用")
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 164)
        .background(.bar)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 18, alignment: .center)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
    }
}

private struct SettingsDetailPane: View {
    let selection: SettingsSection
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Color.clear
                .frame(height: 18)

            Label(selection.title, systemImage: selection.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            switch selection {
            case .general:
                GeneralSettingsPane(settings: settings)
            case .module(let kind):
                ModuleSettingsPane(kind: kind, settings: settings)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        PreferenceGroup {
            PreferenceRow(title: "开机自启") {
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            PreferenceDivider()

            PreferenceRow(title: "主题") {
                Picker("", selection: $settings.themePreference) {
                    ForEach(AppThemePreference.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 214)
            }

            PreferenceDivider()

            PreferenceRow(title: "关于项目") {
                Button("打开") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                .controlSize(.small)
            }
        }
    }
}

private struct ModuleSettingsPane: View {
    let kind: MonitorKind
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        PreferenceGroup {
            PreferenceRow(title: "显示") {
                Toggle("", isOn: Binding(
                    get: { settings.isVisible(kind) },
                    set: { settings.setVisible($0, for: kind) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }
}

private struct PreferenceGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct PreferenceRow<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 18)

            accessory
        }
        .frame(minHeight: 42)
        .padding(.horizontal, 12)
    }
}

private struct PreferenceDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}
