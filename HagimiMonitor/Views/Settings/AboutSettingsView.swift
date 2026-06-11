import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @State private var updateChecker = UpdateChecker()

    private let releasesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases")!

    private var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "about.unknown")
        }

        return version
    }

    var body: some View {
        SettingsPage {
            SettingsGroup {
                aboutHeader
            }

            Spacer(minLength: 0)

            SettingsGroup {
                SettingsRow(title: String(localized: "about.release-version")) {
                    if #available(macOS 26, *) {
                        Button {
                            NSWorkspace.shared.open(releasesURL)
                        } label: {
                            Label("Releases", systemImage: "shippingbox")
                        }
                        .buttonStyle(.glass)
                    } else {
                        Link(destination: releasesURL) {
                            Label("Releases", systemImage: "shippingbox")
                        }
                    }
                }
            }

            Text("© 2026 Acerola")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
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
                if #available(macOS 26, *) {
                    Button(String(localized: "about.check-again")) {
                        Task { await updateChecker.checkForUpdates() }
                    }
                    .buttonStyle(.glass)
                } else {
                    Button(String(localized: "about.check-again")) {
                        Task { await updateChecker.checkForUpdates() }
                    }
                }
            }

        case .updateAvailable(let latestVersion, _, let downloadURL, _):
            VStack(alignment: .trailing, spacing: 5) {
                Text(String(localized: "about.found") + " \(latestVersion)")
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
                if #available(macOS 26, *) {
                    Button(String(localized: "about.retry")) {
                        Task { await updateChecker.checkForUpdates() }
                    }
                    .buttonStyle(.glass)
                } else {
                    Button(String(localized: "about.retry")) {
                        Task { await updateChecker.checkForUpdates() }
                    }
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
