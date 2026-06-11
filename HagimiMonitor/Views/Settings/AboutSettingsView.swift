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
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HagimiMonitor")
                            .font(.headline)

                        Text("版本 \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }

            Section {
                updateCheckView
            }

            Section {
                Link(destination: URL(string: "https://github.com/Acerola-1/hagimi-monitor")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: releasesURL) {
                    Label("发布版本", systemImage: "shippingbox")
                }
            }

            Section {
                Text("© 2026 Acerola")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateCheckView: some View {
        switch updateChecker.state {
        case .idle:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("检查更新")
                        .font(.body)
                    Text("从 GitHub Releases 获取最新版本")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新") {
                    Task { await updateChecker.checkForUpdates() }
                }
            }

        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查...")
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .upToDate:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已是最新版本")
                        .font(.body)
                    Text("当前版本 \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("再次检查") {
                    Task { await updateChecker.checkForUpdates() }
                }
            }

        case .updateAvailable(let latestVersion, let publishedAt, let downloadURL, _):
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本 \(latestVersion)")
                        .font(.body)
                    Text(releaseMessage(publishedAt: publishedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("下载更新") {
                    NSWorkspace.shared.open(downloadURL)
                }
                .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("无法检查更新")
                        .font(.body)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重试") {
                    Task { await updateChecker.checkForUpdates() }
                }
            }
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
