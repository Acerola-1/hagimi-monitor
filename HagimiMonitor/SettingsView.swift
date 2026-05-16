import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: 180)

            Divider()

            SettingsDetailView(selection: selection, settings: settings)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 480)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                ForEach(SettingsSection.all) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            Spacer(minLength: 0)

            Divider()

            HStack(spacing: 0) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("退出应用")
            }
            .frame(height: 45)
        }
        .background(sidebarBackground)
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.black.opacity(0.025)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDetailView: View {
    let selection: SettingsSection
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selection.title)
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.top, 4)

                switch selection {
                case .general:
                    GeneralSettingsPane(settings: settings)
                case .module(let kind):
                    ModuleSettingsPane(kind: kind, settings: settings)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.opacity(0.64))
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        VStack(spacing: 14) {
            SettingsSectionCard {
                SettingsRow(title: "开机自启") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: "主题") {
                    Picker("", selection: $settings.themePreference) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: "关于项目") {
                    Button("打开") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct ModuleSettingsPane: View {
    let kind: MonitorKind
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        SettingsSectionCard {
            SettingsRow(title: "显示") {
                Toggle("", isOn: Binding(
                    get: { settings.isVisible(kind) },
                    set: { settings.setVisible($0, for: kind) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 2)
        .background(.regularMaterial, in: .rect(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            accessory
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 14)
    }
}
