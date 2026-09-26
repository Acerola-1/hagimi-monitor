import SwiftUI
import UniformTypeIdentifiers

/// Game HUD 设置页:总开关 → 监控项目 → 游戏名单 → 左右布局。
/// 状态区明确区分「允许自动显示」与「当前正在显示」,受控增强说明
/// 仅官网版出现(spec:Game HUD 设置页)。
struct GameHUDSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    /// 会话状态由 AppDelegate 持有的协调器提供(与浮窗同源)。
    @State private var newGameBundleID = ""
    /// 扫描器(常驻单例,设置页观察其发布)。
    @ObservedObject private var scanner = GameHUDGameScanner.shared

    var body: some View {
        SettingsPage {
            headerGroup
            metricGroup
            gameListGroup
        }
        .onAppear {
            rescan()
            screenCapturePermission.activatePolling()
        }
        .onDisappear {
            screenCapturePermission.deactivatePolling()
        }
    }

    // MARK: - 总开关、布局与老游戏测帧强化

    private var headerGroup: some View {
        SettingsGroup {
            SettingsRow(title: String(localized: "gamehud.settings.master-enabled")) {
                Toggle("", isOn: $settings.gameHUDMasterEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(title: String(localized: "gamehud.settings.layout")) {
                Picker(String(localized: "gamehud.layout.side"), selection: $settings.gameHUDSidePreference) {
                    Text(String(localized: "gamehud.layout.top-left")).tag(GameHUDSide.topLeft)
                    Text(String(localized: "gamehud.layout.top-right")).tag(GameHUDSide.topRight)
                    Text(String(localized: "gamehud.layout.bottom-left")).tag(GameHUDSide.bottomLeft)
                    Text(String(localized: "gamehud.layout.bottom-right")).tag(GameHUDSide.bottomRight)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            SettingsDivider()
            screenCapturePermissionRow
        }
    }

    // MARK: - 监控项目

    private var metricGroup: some View {
        SettingsGroup(String(localized: "gamehud.settings.metrics")) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(GameHUDMetricCatalog.availableEntries()) { entry in
                    SettingsRow(title: String(localized: entry.titleKey)) {
                        Toggle("", isOn: metricBinding(entry.id))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    /// 屏幕录制授权行(FPS/1% Low 数据源):未授权显示「去授权」按钮,
    /// 已授权显示已完成状态。与键盘锁定的引导交互同型。
    @ObservedObject private var screenCapturePermission = ScreenCapturePermissionService.shared

    @ViewBuilder
    private var screenCapturePermissionRow: some View {
        if screenCapturePermission.isTrusted {
            SettingsRow(
                title: String(localized: "gamehud.permission.screencapture"),
                subtitle: String(localized: "gamehud.permission.screencapture.granted")
            ) {
                EmptyView()
            }
        } else {
            SettingsRow(
                title: String(localized: "gamehud.permission.screencapture"),
                subtitle: String(localized: "gamehud.permission.screencapture.hint")
            ) {
                Button(String(localized: "gamehud.permission.grant")) {
                    screenCapturePermission.presentGuide()
                }
            }
        }
    }

    private func metricBinding(_ id: GameHUDMetricID) -> Binding<Bool> {
        Binding(
            get: { settings.gameHUDEnabledMetricIDs.contains(id) },
            set: { settings.setGameHUDMetric(id, enabled: $0) }
        )
    }

    // MARK: - 游戏名单(自动发现为主)

    /// 名单页:以扫描到的游戏为主体(自动发现),每项带应用图标与来源;
    /// 失效条目(磁盘上已找不到对应 .app)标 `!` 提示用户排除;
    /// 未收录的发现项提供逐个「添加」;手动添加输入框降为列表末尾的辅助入口。
    /// 「重新扫描」挂在分组标题右侧。
    private var gameListGroup: some View {
        // 自动采纳:扫描结果全部视为已启用,用户只提供排除。
        // customGames 里扫不到的条目 = 手动添加后应用被删/移动,标失效。
        let excluded = settings.gameHUDExcludedGames
        let discovered = scanner.discoveredGames
        let active = discovered.filter { !excluded.contains($0.bundleID) }
        let stale = Set(settings.gameHUDCustomGames).subtracting(discovered.map(\.bundleID)).sorted()
        let excludedVisible = excluded.sorted()
        return SettingsGroup(String(localized: "gamehud.settings.games"), titleAccessory: {
            HStack(spacing: 6) {
                if scanner.isScanning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button {
                    scanner.invalidate()
                    rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "gamehud.discovered.rescan"))
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                if active.isEmpty && stale.isEmpty {
                    Text(String(localized: "gamehud.games.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }

                // 已启用(用户名单命中扫描结果):icon + 名字 + 来源。
                if !active.isEmpty {
                    Text(String(localized: "gamehud.games.active-header"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    ForEach(active) { game in
                        discoveredRow(game: game)
                    }
                }

                // 失效条目:用户名单里有,但磁盘上扫不到了。
                if !stale.isEmpty {
                    Text(String(localized: "gamehud.games.stale-header"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    ForEach(stale, id: \.self) { bundleID in
                        staleRow(bundleID: bundleID)
                    }
                }

                // 已排除(排除名单里能对上扫描结果的显示来源,对不上的只显示 ID)。
                if !excludedVisible.isEmpty {
                    Text(String(localized: "gamehud.games.excluded-header"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    ForEach(excludedVisible, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .contextMenu {
                                    Button(String(localized: "gamehud.games.remove-exclusion")) {
                                        settings.removeGameHUDExcludedGame(bundleID)
                                    }
                                }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }
                }

                // 手动添加:兜底入口,浏览选 .app 自动读 bundle ID;
                // 扫描覆盖不到的(小众安装位置)用。
                HStack(spacing: 8) {
                    Button(String(localized: "gamehud.games.browse")) {
                        browseAndAddGame()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    /// 扫描命中行:icon + 名字 + 来源,右侧「注入启动」(Direct)与排除。
    private func discoveredRow(game: GameHUDDiscoveredGame) -> some View {
        HStack {
            Image(nsImage: appIcon(for: game))
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(sourceLabel(game.source))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "gamehud.games.exclude")) {
                settings.excludeGameHUDGame(game.bundleID)
            }
        }
        .padding(.horizontal, 14)
    }


    /// 失效行:名单里有但扫不到,名前 `!` 提示,提供排除动作。
    private func staleRow(bundleID: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(bundleID)
                    .font(.caption)
                    .lineLimit(1)
                Text(String(localized: "gamehud.games.stale-hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "gamehud.games.remove")) {
                settings.removeGameHUDCustomGame(bundleID)
                rescan()
            }
        }
        .padding(.horizontal, 14)
    }

    /// 应用图标: Spotlight 来源直接读 .app;Steam/Epic 来源按记录的路径;
    /// 都没有则退回通用可执行图标。
    private func appIcon(for game: GameHUDDiscoveredGame) -> NSImage {
        if let url = game.executableURL {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if icon.size != .zero {
                return icon
            }
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func sourceLabel(_ source: GameHUDDiscoveredGame.Source) -> String {
        switch source {
        case .steam: String(localized: "gamehud.scanner.source.steam")
        case .epic: String(localized: "gamehud.scanner.source.epic")
        case .spotlight: String(localized: "gamehud.scanner.source.spotlight")
        }
    }

    /// 浏览选择 .app 读取 bundle ID 加入名单(用户手动兜底)。
    private func browseAndAddGame() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        settings.addGameHUDCustomGame(bundleID)
        rescan()
    }

    /// 首次出现时扫描;扫描在后台队列做,避免阻塞设置页首帧。
    private func rescan() {
        if settings.gameHUDMasterEnabled {
            scanner.startMonitoring()
        }
        scanner.rescanNow()
    }
}
