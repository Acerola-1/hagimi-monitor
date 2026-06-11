import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @State private var updateChecker = UpdateChecker()

    private let releasesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases")!
    private let repoURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor")!

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

            SettingsGroup {
                updateCheckView
            }

            SettingsGroup {
                SettingsRow(title: "源代码仓库") {
                    if #available(macOS 26, *) {
                        Button {
                            NSWorkspace.shared.open(repoURL)
                        } label: {
                            Label("GitHub", systemImage: "link")
                        }
                        .buttonStyle(.glass)
                    } else {
                        Link(destination: repoURL) {
                            Label("GitHub", systemImage: "link")
                        }
                    }
                }

                SettingsDivider()

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
        )
    }

    @ViewBuilder
    private var updateCheckView: some View {
        switch updateChecker.state {
        case .idle:
            SettingsRow(title: "检查更新", subtitle: "从 GitHub Releases 获取最新版本") {
                primaryButton(title: "检查更新") {
                    Task { await updateChecker.checkForUpdates() }
                }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查...")
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .upToDate:
            SettingsRow(title: "已是最新版本", subtitle: "当前版本 \(appVersion)") {
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

        case .updateAvailable(let latestVersion, let publishedAt, let downloadURL, _):
            SettingsRow(title: "发现新版本 \(latestVersion)", subtitle: releaseMessage(publishedAt: publishedAt)) {
                primaryButton(title: "下载更新") {
                    NSWorkspace.shared.open(downloadURL)
                }
            }

        case .failed(let message):
            SettingsRow(title: "无法检查更新", subtitle: message) {
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

    private func releaseMessage(publishedAt: String?) -> String {
        guard let publishedAt,
              let date = ISO8601DateFormatter().date(from: publishedAt) else {
            return "可以前往 GitHub 下载并手动安装"
        }

        return "发布于 \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
