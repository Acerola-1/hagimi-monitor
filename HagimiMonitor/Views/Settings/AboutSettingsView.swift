import AppKit
import OSLog
import SwiftUI

struct AboutSettingsView: View {
    @State private var updateChecker = UpdateChecker.shared
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
        switch updateChecker.state {
        case .idle:
            primaryButton(title: String(localized: "about.check-updates")) {
                Task { await updateChecker.checkForUpdates() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "about.checking"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            HStack(spacing: 8) {
                Text(String(localized: "about.up-to-date"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "about.check-again")) {
                    Task { await updateChecker.checkForUpdates() }
                }
                .compatibleButtonStyle()
            }

        case .updateAvailable(let latestVersion, _, let downloadURL, _):
            VStack(alignment: .trailing, spacing: 5) {
                Text(String(localized: "about.found") + latestVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                primaryButton(title: String(localized: "about.download-update")) {
                    NSWorkspace.shared.open(downloadURL)
                }
            }

        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(String(localized: "about.retry")) {
                    Task { await updateChecker.checkForUpdates() }
                }
                .compatibleButtonStyle()
            }
        }
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
