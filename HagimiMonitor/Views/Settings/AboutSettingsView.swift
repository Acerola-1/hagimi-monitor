import AppKit
import OSLog
import SwiftUI

struct AboutSettingsView: View {
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updateService = UpdateService.shared
    #endif
    @State private var isExportingLogs = false
    @State private var logExportMessage: String?

    private let releasesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases")!
    private let issuesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/issues")!
    private let twitterURL = URL(string: "https://x.com/Acerola64175279")!

    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "about.unknown")
        }

        return version
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                aboutHeader
            }

            Spacer(minLength: 0)

            SettingsGroup {
                SettingsRow(title: String(localized: "about.release-version")) {
                    Button {
                        NSWorkspace.shared.open(releasesURL)
                    } label: {
                        Label("Releases", systemImage: "shippingbox")
                            .frame(width: 120, alignment: .leading)
                    }
                    .compatibleButtonStyle()
                }

                SettingsRow(title: String(localized: "about.feedback")) {
                    Button {
                        NSWorkspace.shared.open(issuesURL)
                    } label: {
                        Label("Issue", systemImage: "exclamationmark.bubble")
                            .frame(width: 120, alignment: .leading)
                    }
                    .compatibleButtonStyle()
                }

                SettingsRow(title: String(localized: "about.follow")) {
                    Button {
                        NSWorkspace.shared.open(twitterURL)
                    } label: {
                        Label("X / Twitter", systemImage: "at")
                            .frame(width: 120, alignment: .leading)
                    }
                    .compatibleButtonStyle()
                }

                SettingsRow(title: String(localized: "about.diagnostics"), subtitle: logExportMessage) {
                    exportLogsButton
                }
            }

            Text("© 2026 Acerola")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .padding(.top, 22)
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var aboutHeader: some View {
        SettingsIconHeader(
            title: "HagimiMonitor",
            subtitle: String(localized: "about.version") + " \(appVersion)",
            footnote: String(localized: "about.footnote"),
            imageName: "AboutIcon"
        ) {
            updateAccessory
        }
    }

    @ViewBuilder
    private var updateAccessory: some View {
        // 更新入口按分发渠道拆分:仅直接分发(GitHub)版内置检查更新逻辑;
        // App Store 版的更新完全交由 App Store 管理,此处不显示任何更新入口
        // (亦符合 App Store 审核要求:不得在 App 内引导用户去 App 外下载安装)。
        #if DIRECT_DISTRIBUTION
        VStack(alignment: .trailing, spacing: 6) {
            // 主入口:Sparkle 自更新。点击后由 Sparkle 接管——弹出带更新日志的窗口、
            // App 内下载校验、替换并重启,全程无需用户离开 App。
            primaryButton(title: String(localized: "about.check-updates")) {
                updateService.checkForUpdates()
            }
            .disabled(!updateService.canCheckForUpdates)

            // 兜底副入口(始终显示):网络不佳、Sparkle 下载不动时,让用户跳转浏览器
            // 到 GitHub Releases 手动下载安装包。
            Button {
                NSWorkspace.shared.open(releasesURL)
            } label: {
                Text(String(localized: "about.download-from-github"))
                    .font(.caption)
            }
            .buttonStyle(.link)
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var exportLogsButton: some View {
        let label = isExportingLogs
            ? String(localized: "about.exporting-logs")
            : String(localized: "about.export-logs")

        Button {
            exportLogs()
        } label: {
            if isExportingLogs {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 120, alignment: .leading)
            } else {
                Label(label, systemImage: "doc.zipper")
                    .frame(width: 120, alignment: .leading)
            }
        }
        .disabled(isExportingLogs)
        .compatibleButtonStyle()
    }

    private func exportLogs() {
        guard !isExportingLogs else { return }
        isExportingLogs = true
        logExportMessage = nil
        AppLogStore.shared.info("Diagnostics export requested", category: "settings")

        Task {
            do {
                let url = try AppLogExporter().export()
                AppLogStore.shared.info("Diagnostics export succeeded: \(url.lastPathComponent)", category: "settings")
                await MainActor.run {
                    isExportingLogs = false
                    logExportMessage = String(localized: "about.export-logs-done")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                AppLogger.diagnostics.error("Diagnostics export failed: \(String(describing: error), privacy: .public)")
                AppLogStore.shared.error("Diagnostics export failed: \(error.localizedDescription)", category: "settings")
                await MainActor.run {
                    isExportingLogs = false
                    logExportMessage = String(localized: "about.export-logs-failed")
                }
            }
        }
    }

    @ViewBuilder
    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        if #available(macOS 26, *) {
            Button(title, action: action)
                .buttonStyle(.glassProminent)
        } else {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
