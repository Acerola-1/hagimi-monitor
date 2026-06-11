import AppKit
import SwiftUI

struct AboutSettingsView: View {
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
        SettingsPage {
            SettingsGroup {
                aboutHeader
            }

            Spacer(minLength: 0)

            SettingsGroup {
                SettingsRow(title: "发布版本") {
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
            subtitle: "版本 \(appVersion)",
            footnote: "macOS 菜单栏硬件监控",
            imageName: "AboutIcon"
        ) {
            updateAccessory
        }
    }

    @ViewBuilder
    private var updateAccessory: some View {
        switch updateChecker.state {
        case .idle:
            primaryButton(title: "检查更新") {
                Task { await updateChecker.checkForUpdates() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            HStack(spacing: 8) {
                Text("已是最新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if #available(macOS 26, *) {
                    Button("再次检查") {
                        Task { await updateChecker.checkForUpdates() }
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("再次检查") {
                        Task { await updateChecker.checkForUpdates() }
                    }
                }
            }

        case .updateAvailable(let latestVersion, _, let downloadURL, _):
            VStack(alignment: .trailing, spacing: 5) {
                Text("发现 \(latestVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                primaryButton(title: "下载更新") {
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
                    Button("重试") {
                        Task { await updateChecker.checkForUpdates() }
                    }
                    .buttonStyle(.glass)
                } else {
                    Button("重试") {
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
