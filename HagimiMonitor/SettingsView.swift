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

    var body: some View {
        Form {
            ForEach(MonitorKind.allCases) { kind in
                Section {
                    Toggle(
                        kind.title,
                        systemImage: kind.symbol,
                        isOn: Binding(
                            get: { settings.isVisible(kind) },
                            set: { settings.setVisible($0, for: kind) }
                        )
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

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
