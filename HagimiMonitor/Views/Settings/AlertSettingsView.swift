import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// 异常警报设置子页：通知总开关（含系统授权引导）→ 分项警报开关 → 忽略的应用白名单。
struct AlertSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    let onBack: () -> Void

    @ObservedObject private var notificationDelegate = AlertNotificationDelegate.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var backHovered = false

    private var palette: MonitorPalette {
        MonitorPalette(preference: settings.colorSchemePreference, colorScheme: colorScheme)
    }

    var body: some View {
        SettingsPage {
            headerBar
            masterGroup

            if settings.alertNotificationsEnabled {
                categoriesGroup
            }

            ignoredAppsGroup
        }
        .animation(.default, value: settings.alertNotificationsEnabled)
        .onAppear {
            notificationDelegate.refreshAuthorizationStatus()
        }
    }

    // MARK: - 顶部返回栏

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(backHovered ? Color.primary : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.secondary.opacity(backHovered ? 0.16 : 0.09)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { backHovered = $0 }
            .accessibilityLabel(Text(String(localized: "stats.alerts.back")))

            Text(String(localized: "stats.alerts.title"))
                .font(.title3.weight(.semibold))

            Spacer()
        }
    }

    // MARK: - 总开关与权限状态

    private var masterGroup: some View {
        SettingsGroup {
            SettingsRow(
                title: String(localized: "stats.settings.notifications"),
                subtitle: String(localized: "stats.settings.notifications.detail")
            ) {
                Toggle(String(localized: "stats.settings.notifications"), isOn: $settings.alertNotificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if settings.alertNotificationsEnabled, notificationDelegate.authorizationStatus == .denied {
                SettingsDivider()

                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.severityTint(for: .warning))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "stats.alerts.permission-denied.title"))
                            .font(.callout.weight(.medium))
                        Text(String(localized: "stats.alerts.permission-denied.detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button(String(localized: "stats.alerts.permission-denied.open")) {
                        openNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - 分项警报开关

    private var categoriesGroup: some View {
        SettingsGroup(String(localized: "stats.alerts.categories.title")) {
            SettingsRow(
                title: String(localized: "stats.alerts.memory.title"),
                subtitle: String(localized: "stats.alerts.memory.detail")
            ) {
                Toggle(String(localized: "stats.alerts.memory.title"), isOn: $settings.alertMemoryPressureEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: String(localized: "stats.alerts.thermal.title"),
                subtitle: String(localized: "stats.alerts.thermal.detail")
            ) {
                Toggle(String(localized: "stats.alerts.thermal.title"), isOn: $settings.alertThermalPressureEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: String(localized: "stats.alerts.apps.title"),
                subtitle: String(localized: "stats.alerts.apps.detail")
            ) {
                Toggle(String(localized: "stats.alerts.apps.title"), isOn: $settings.alertHighLoadAppEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    // MARK: - 忽略的应用白名单

    private var ignoredAppsGroup: some View {
        SettingsGroup(
            String(localized: "stats.alerts.ignored.title"),
            titleAccessory: {
                addIgnoredAppMenu
            }
        ) {
            if settings.alertIgnoredApps.isEmpty {
                Text(String(localized: "stats.alerts.ignored.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(settings.alertIgnoredApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            SettingsDivider()
                        }
                        ignoredAppRow(app)
                    }
                }
            }
        }
    }

    private var addIgnoredAppMenu: some View {
        let candidates = runningCandidateApps()
        return Menu {
            if !candidates.isEmpty {
                Section(String(localized: "stats.alerts.ignored.running-section")) {
                    ForEach(candidates) { app in
                        Button(app.displayName) {
                            settings.addIgnoredAlertApp(app)
                        }
                    }
                }
                Divider()
            }
            Button(String(localized: "stats.alerts.ignored.choose-app")) {
                chooseApplication()
            }
        } label: {
            Label(String(localized: "stats.alerts.ignored.add"), systemImage: "plus")
        }
        .fixedSize()
        .controlSize(.small)
    }

    private func ignoredAppRow(_ app: AlertIgnoredApp) -> some View {
        HStack(spacing: 10) {
            ignoredAppIcon(for: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .help(app.displayName)

                if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(String(localized: "stats.alerts.ignored.remove")) {
                settings.removeIgnoredAlertApp(id: app.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func ignoredAppIcon(for app: AlertIgnoredApp) -> some View {
        if let image = resolveAppIcon(for: app) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else {
            Image(systemName: app.displayName == "WindowServer" ? "display" : "app.dashed")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    // MARK: - 辅助

    private func resolveAppIcon(for app: AlertIgnoredApp) -> NSImage? {
        if let bundleID = app.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "") == app.displayName
        }) {
            return running.icon
        }
        return nil
    }

    private func runningCandidateApps() -> [AlertIgnoredApp] {
        let selfBundleID = Bundle.main.bundleIdentifier
        var seen: Set<String> = []
        var candidates: [AlertIgnoredApp] = []
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            if let selfBundleID, running.bundleIdentifier == selfBundleID { continue }
            guard let item = AlertIgnoredApp.from(runningApp: running) else { continue }
            guard !settings.isAlertAppIgnored(appKey: item.id, name: item.displayName) else { continue }
            if seen.insert(item.id).inserted {
                candidates.append(item)
            }
        }
        return candidates.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "stats.alerts.ignored.choose-title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let app = AlertIgnoredApp.from(bundleURL: url) else { return }
        settings.addIgnoredAlertApp(app)
    }

    private func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
