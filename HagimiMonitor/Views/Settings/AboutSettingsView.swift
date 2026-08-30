import AppKit
import OSLog
import SwiftUI

struct AboutSettingsView: View {
    #if DIRECT_DISTRIBUTION
    @ObservedObject private var updateService = UpdateService.shared
    #endif
    @State private var isExportingLogs = false
    @State private var logExportMessage: String?
    @State private var isShowingLicenses = false

    // 仅直接分发版使用:App Store 版不暴露 GitHub Releases 入口(见下方 SettingsRow 注释)。
    #if DIRECT_DISTRIBUTION
    private let releasesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/releases")!
    #endif
    private let issuesURL = URL(string: "https://github.com/Acerola-1/hagimi-monitor/issues")!
    private let xiaohongshuURL = URL(string: "https://www.xiaohongshu.com/user/profile/64a9325200000000110000a6")!

    // 各行附件统一使用相同宽度、左对齐,保证 Releases / 反馈按钮 / 导出日志 的左边缘对齐成一列。
    private let accessoryColumnWidth: CGFloat = 172

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
                // 发布版本入口仅在直接分发(GitHub)版显示。App Store 版不得引导用户
                // 前往 App 外(GitHub Releases)下载安装包——那里正是本 App 的免费分发页,
                // 在商店版内暴露会被判定为绕过 App Store(Guideline 3.1.1 / 2.3.1)。
                #if DIRECT_DISTRIBUTION
                SettingsRow(title: String(localized: "about.release-version")) {
                    Button {
                        NSWorkspace.shared.open(releasesURL)
                    } label: {
                        Label(String(localized: "Releases"), systemImage: "shippingbox")
                    }
                    .compatibleButtonStyle()
                    .frame(width: accessoryColumnWidth, alignment: .leading)
                }
                #endif

                SettingsRow(title: String(localized: "about.feedback")) {
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(issuesURL)
                        } label: {
                            Label("GitHub", systemImage: "exclamationmark.bubble")
                        }
                        .compatibleButtonStyle()

                        Button {
                            NSWorkspace.shared.open(xiaohongshuURL)
                        } label: {
                            Label(String(localized: "about.xiaohongshu"), systemImage: "heart.fill")
                        }
                        .compatibleButtonStyle()
                    }
                    .frame(width: accessoryColumnWidth, alignment: .leading)
                }

                SettingsRow(title: String(localized: "about.diagnostics"), subtitle: logExportMessage) {
                    exportLogsButton
                }

                // 开源软件声明:与诊断日志同款行样式,右侧按钮弹出第三方开源软件/素材列表。
                SettingsRow(title: String(localized: "about.open-source")) {
                    Button {
                        isShowingLicenses = true
                    } label: {
                        Label(String(localized: "about.open-source.view"), systemImage: "list.bullet.rectangle")
                    }
                    .compatibleButtonStyle()
                    .frame(width: accessoryColumnWidth, alignment: .leading)
                }

                SettingsRow(title: String(localized: "about.telemetry"), subtitle: String(localized: "about.telemetry.detail")) {
                    Toggle("", isOn: Binding(
                        get: { UsageReporter.shared.isEnabled },
                        set: { UsageReporter.shared.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            Text(String(localized: "© 2026 Acerola"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isShowingLicenses) {
            OpenSourceLicensesView(onClose: { isShowingLicenses = false })
        }
    }

    @ViewBuilder
    private var aboutHeader: some View {
        SettingsIconHeader(
            title: "HagimiMonitor",
            subtitle: String(localized: "about.version") + " \(appVersion)",
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
            primaryButton(title: updateButtonTitle) {
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
            .compatibleGlassLinkButtonStyle()
            .controlSize(.small)
        }
        #else
        EmptyView()
        #endif
    }

    #if DIRECT_DISTRIBUTION
    private var updateButtonTitle: String {
        guard let version = updateService.availableUpdateVersion else {
            return String(localized: "about.check-updates")
        }
        return String(localized: "about.update-to-version \(version)")
    }
    #endif

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
            } else {
                Label(label, systemImage: "doc.zipper")
            }
        }
        .disabled(isExportingLogs)
        .compatibleButtonStyle()
        .frame(width: accessoryColumnWidth, alignment: .leading)
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
        Button(title, action: action)
            .compatibleSystemGlassButtonStyle(prominent: true)
    }
}
