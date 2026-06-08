import AppKit
import SwiftUI

enum SettingsTab: String {
    case general
    case modules
    case about
}

struct SettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @AppStorage(SettingsWindowPresenter.selectedTabDefaultsKey) private var selectedTab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane(settings: settings)
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }
                .tag(SettingsTab.general.rawValue)

            ModuleSettingsPane(settings: settings)
                .tabItem {
                    Label("模块", systemImage: "square.grid.2x2")
                }
                .tag(SettingsTab.modules.rawValue)

            AboutPane()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
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

                Picker("配色", selection: $settings.colorSchemePreference) {
                    ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                        Text(colorScheme.title).tag(colorScheme)
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
    @State private var updateChecker = UpdateChecker()

    private let releasesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases")!

    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "未知"
        }

        return version
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Image("AboutIcon")
                    .resizable()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 8)

                VStack(spacing: 4) {
                    Text("HagimiMonitor")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("版本 \(appVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("macOS 菜单栏硬件监控工具")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            updateCheckView

            Spacer()

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/Acerola-1/hagimi-monitor")!) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)

                Link(destination: releasesURL) {
                    Label("发布版本", systemImage: "shippingbox")
                }
                .buttonStyle(.bordered)
            }

            Text("© 2026 Acerola")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var updateCheckView: some View {
        switch updateChecker.state {
        case .idle:
            UpdateStatusPanel(
                symbol: "arrow.trianglehead.clockwise",
                tint: .accentColor,
                title: "检查更新",
                message: "从 GitHub Releases 获取最新版本。",
                primaryTitle: "检查更新",
                primarySystemImage: "arrow.trianglehead.clockwise",
                primaryAction: checkForUpdates
            )

        case .checking:
            UpdateStatusPanel(
                symbol: "clock",
                tint: .secondary,
                title: "正在检查",
                message: "正在连接 GitHub Releases。",
                isChecking: true
            )

        case .upToDate:
            UpdateStatusPanel(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: "已是最新版本",
                message: "当前版本 \(appVersion) 不需要更新。",
                primaryTitle: "再次检查",
                primarySystemImage: "arrow.trianglehead.clockwise",
                primaryAction: checkForUpdates
            )

        case .updateAvailable(let latestVersion, let publishedAt, let downloadURL, _):
            UpdateStatusPanel(
                symbol: "sparkles",
                tint: .orange,
                title: "发现新版本 \(latestVersion)",
                message: releaseMessage(publishedAt: publishedAt),
                primaryTitle: "下载更新",
                primarySystemImage: "arrow.down.circle",
                primaryAction: {
                    NSWorkspace.shared.open(downloadURL)
                }
            )

        case .failed(let message):
            UpdateStatusPanel(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "无法检查更新",
                message: message,
                primaryTitle: "重试",
                primarySystemImage: "arrow.trianglehead.clockwise",
                primaryAction: checkForUpdates,
                secondaryTitle: "打开发布页",
                secondarySystemImage: "safari",
                secondaryAction: {
                    NSWorkspace.shared.open(releasesURL)
                }
            )
        }
    }

    private func checkForUpdates() {
        Task { await updateChecker.checkForUpdates() }
    }

    private func releaseMessage(publishedAt: String?) -> String {
        guard let publishedAt,
              let date = ISO8601DateFormatter().date(from: publishedAt) else {
            return "可以前往 GitHub 下载并手动安装。"
        }

        return "发布于 \(date.formatted(date: .abbreviated, time: .omitted))，可以前往 GitHub 下载并手动安装。"
    }
}

private struct UpdateStatusPanel: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var isChecking = false
    var primaryTitle: String?
    var primarySystemImage: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondarySystemImage: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.14))

                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                if let primaryTitle, let primarySystemImage, let primaryAction {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isChecking)
                }

                if let secondaryTitle, let secondarySystemImage, let secondaryAction {
                    Button(action: secondaryAction) {
                        Label(secondaryTitle, systemImage: secondarySystemImage)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }
}
