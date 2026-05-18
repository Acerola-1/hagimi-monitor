import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        TabView {
            GeneralSettingsPane(settings: settings)
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }

            ModuleSettingsPane(settings: settings)
                .tabItem {
                    Label("模块", systemImage: "square.grid.2x2")
                }

            AboutPane()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 480)
        .background(SettingsWindowTracker())
    }
}

// MARK: - General Settings

private struct GeneralSettingsPane: View {
    @ObservedObject var settings: MonitorSettings

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自启", isOn: $settings.launchAtLogin)
            }

            Section("外观") {
                Picker("主题", selection: $settings.themePreference) {
                    ForEach(AppThemePreference.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

// MARK: - Module Settings

private struct ModuleSettingsPane: View {
    @ObservedObject var settings: MonitorSettings
    #if DISPLAY_CONTROL
    @State private var isDisplaySettingsExpanded = false
    #endif

    var body: some View {
        Form {
            Section("模块") {
                ForEach(MonitorKind.allCases) { kind in
                    ModuleVisibilityRow(
                        title: kind.title,
                        systemImage: kind.symbol,
                        isOn: Binding(
                            get: { settings.isVisible(kind) },
                            set: { settings.setVisible($0, for: kind) }
                        )
                    )
                }

                #if DISPLAY_CONTROL
                DisplayModuleSettingsRow(
                    settings: settings,
                    isExpanded: $isDisplaySettingsExpanded
                )
                #endif
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct ModuleVisibilityRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
        }
    }
}

#if DISPLAY_CONTROL
private struct DisplayModuleSettingsRow: View {
    @ObservedObject var settings: MonitorSettings
    @Binding var isExpanded: Bool

    private let expansionAnimation = Animation.smooth(duration: 0.2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleVisibilityRow(
                title: "显示器",
                systemImage: "display",
                isOn: $settings.displayModuleVisible
            )

            Button {
                withAnimation(expansionAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))

                    Text("选项")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.leading, 28)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.leading, 6)

                    ModuleOptionToggle(
                        title: "内置显示器",
                        systemImage: "laptopcomputer",
                        isOn: $settings.showBuiltInDisplays
                    )

                    ModuleOptionToggle(
                        title: "亮度",
                        systemImage: "sun.max",
                        isOn: $settings.displayBrightnessControlEnabled
                    )

                    ModuleOptionToggle(
                        title: "音量",
                        systemImage: "speaker.wave.2",
                        isOn: $settings.displayVolumeControlEnabled
                    )

                    ModuleOptionToggle(
                        title: "对比度",
                        systemImage: "circle.lefthalf.filled",
                        isOn: $settings.displayContrastControlEnabled
                    )
                }
                .padding(.top, 8)
                .padding(.leading, 50)
                .transition(.settingsDisclosure)
            }
        }
        .animation(expansionAnimation, value: isExpanded)
    }
}

private struct ModuleOptionToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
                    .font(.subheadline)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
        }
    }
}

private extension AnyTransition {
    static var settingsDisclosure: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
        )
    }
}
#endif

private struct SettingsWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowTrackingView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }

        Task { @MainActor in
            SettingsWindowPresenter.register(window)
        }
    }
}

private final class SettingsWindowTrackingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        Task { @MainActor in
            SettingsWindowPresenter.register(window)
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)

            Text("HagimiMonitor")
                .font(.title2)
                .fontWeight(.semibold)

            Text("版本 1.0.0")
                .foregroundStyle(.secondary)

            Text("一只赛博猫作为视觉伴侣的 macOS 菜单栏硬件监控工具")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer()

            Link(destination: URL(string: "https://github.com")!) {
                Label("在 GitHub 上查看", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)

            Text("© 2026 Acerola")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
