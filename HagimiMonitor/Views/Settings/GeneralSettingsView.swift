import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.launch-at-login")) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.quick-access")) {
                    QuickAccessShortcutRecorder()
                }
            }

            SettingsGroup(String(localized: "settings.appearance")) {
                SettingsRow(title: String(localized: "settings.theme")) {
                    Picker(String(localized: "settings.theme"), selection: $settings.themePreference) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(title: String(localized: "settings.color-scheme")) {
                    Picker(String(localized: "settings.color-scheme"), selection: $settings.colorSchemePreference) {
                        ForEach(MonitorColorSchemePreference.allCases) { colorScheme in
                            Text(colorScheme.title).tag(colorScheme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            MenuBarDisplaySettingsSection(settings: settings, store: store)
        }
    }
}

/// 快速呼出快捷键录制器。
///
/// 旧实现将一个不透明的占位层盖在库自带的原生 `NSSearchField` 上，
/// 既与面板风格不一致，又依赖点击穿透，经常点不动。
/// 现在改为完全自绘的按钮：点击由真正的 SwiftUI Button 驱动，
/// 录制通过本地事件监听实现，库只负责存储与全局注册。
private struct QuickAccessShortcutRecorder: View {
    @StateObject private var model = QuickAccessShortcutModel()

    var body: some View {
        Button(action: model.toggleRecording) {
            content
                .frame(width: 168, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            model.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: model.isRecording ? 1.5 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if model.shortcut != nil, !model.isRecording {
                Button(action: model.clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(String(localized: "settings.quick-access.clear"))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isRecording)
        .animation(.easeInOut(duration: 0.15), value: model.shortcut)
        .onDisappear { model.stopRecording() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isRecording {
            HStack(spacing: 5) {
                // 提示：至少需要按住其中一个修饰键。
                HStack(spacing: 2) {
                    ShortcutKeyCap("⌃", compact: true)
                    ShortcutKeyCap("⌥", compact: true)
                    ShortcutKeyCap("⌘", compact: true)
                }
                .foregroundStyle(Color.accentColor)

                Text(String(localized: "settings.quick-access.recording"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
        } else if let shortcut = model.shortcut {
            HStack(spacing: 3) {
                ForEach(Array(shortcut.description.enumerated()), id: \.offset) { _, symbol in
                    ShortcutKeyCap(String(symbol))
                }
            }
            .padding(.trailing, 16)
        } else {
            Text(String(localized: "settings.quick-access.record"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 快速呼出快捷键的录制状态与存储。
///
/// 录制期间临时禁用全局快捷键，避免用户正在按的组合直接触发面板开关。
@MainActor
private final class QuickAccessShortcutModel: ObservableObject {
    @Published private(set) var shortcut: KeyboardShortcuts.Shortcut?
    @Published private(set) var isRecording = false

    private let name = KeyboardShortcuts.Name.togglePinnedPanel
    private var monitor: Any?

    init() {
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        // 防止录制时按下当前组合直接触发面板。
        KeyboardShortcuts.disable(name)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        KeyboardShortcuts.enable(name)
    }

    func clear() {
        stopRecording()
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcut = nil
    }

    /// 处理录制期间的按键事件，返回 `nil` 表示已消费事件。
    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifierKey = !flags.subtracting([.shift, .function]).isEmpty

        // Esc 取消录制。
        if event.keyCode == 53, flags.isEmpty {
            stopRecording()
            return nil
        }

        // 无修饰键的删除键清除已有快捷键。
        if event.keyCode == 51 || event.keyCode == 117, flags.isEmpty {
            clear()
            return nil
        }

        // 至少需要一个 Command/Control/Option 修饰键，或为功能键（F1-F31）。
        let isFunctionKey: Bool = {
            guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value else {
                return false
            }
            return (0xF704...0xF71E).contains(scalar)
        }()
        guard hasModifierKey || isFunctionKey,
              let recorded = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            return nil
        }

        KeyboardShortcuts.setShortcut(recorded, for: name)
        shortcut = recorded
        stopRecording()
        return nil
    }
}

private struct ShortcutKeyCap: View {
    let symbol: String
    var compact: Bool

    init(_ symbol: String, compact: Bool = false) {
        self.symbol = symbol
        self.compact = compact
    }

    var body: some View {
        Text(symbol)
            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            .frame(minWidth: compact ? 15 : 18, minHeight: compact ? 15 : 18)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: compact ? 3 : 4, style: .continuous))
    }
}

private struct MenuBarDisplaySettingsSection: View {
    @ObservedObject var settings: MonitorSettings
    @ObservedObject var store: MonitorStore

    var body: some View {
        SettingsGroup(String(localized: "settings.menu-bar")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "menu-bar-display.preview"))
                    .font(.body.weight(.medium))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Spacer(minLength: 0)

                        preview
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.55), in: Capsule())

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            SettingsDivider()

            SettingsRow(title: String(localized: "menu-bar-display.mode")) {
                Picker(String(localized: "menu-bar-display.mode"), selection: $settings.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            if settings.menuBarDisplayMode == .metrics {
                SettingsDivider()

                SettingsRow(title: String(localized: "menu-bar-metric-layout.style")) {
                    Picker(String(localized: "menu-bar-metric-layout.style"), selection: $settings.menuBarMetricLayoutStyle) {
                        ForEach(MenuBarMetricLayoutStyle.allCases) { layoutStyle in
                            Text(layoutStyle.title).tag(layoutStyle)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                SettingsDivider()

                SettingsRow(
                    title: String(localized: "menu-bar-display.metrics-title"),
                    subtitle: String(localized: "menu-bar-display.metrics-limit")
                ) {
                    Text("\(settings.menuBarMetricKinds.count)/\(MenuBarMetricKind.maximumSelectionCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                VStack(spacing: 0) {
                    ForEach(MenuBarMetricKind.allCases) { kind in
                        MenuBarMetricSelectionRow(
                            kind: kind,
                            isSelected: settings.isMenuBarMetricSelected(kind),
                            isEnabled: settings.canSelectMenuBarMetric(kind)
                        ) {
                            settings.setMenuBarMetric(kind, selected: !settings.isMenuBarMetricSelected(kind))
                        }

                        if kind != MenuBarMetricKind.allCases.last {
                            SettingsDivider()
                        }
                    }
                }

                SettingsDivider()

                VStack(spacing: 0) {
                    ForEach(settings.menuBarMetricKinds) { kind in
                        MenuBarMetricOrderRow(
                            kind: kind,
                            canMoveUp: settings.menuBarMetricKinds.first != kind,
                            canMoveDown: settings.menuBarMetricKinds.last != kind,
                            moveUp: { settings.moveMenuBarMetric(kind, direction: -1) },
                            moveDown: { settings.moveMenuBarMetric(kind, direction: 1) }
                        )

                        if kind != settings.menuBarMetricKinds.last {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if settings.menuBarDisplayMode == .ring {
            Image(nsImage: MenuBarComputeRingIcon.image(
                load: store.loadAnimator.displayedComputeLoad,
                darkMode: NSApp.effectiveAppearance.isDark,
                loadLevel: store.haloRingLoadLevel
            ))
            .resizable()
            .frame(width: 18, height: 18)
        } else {
            MenuBarMetricLabel(
                items: store.previewMenuBarMetricItems(),
                style: .preview,
                layoutStyle: settings.menuBarMetricLayoutStyle
            )
        }
    }
}

private struct MenuBarMetricSelectionRow: View {
    let kind: MenuBarMetricKind
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 16, height: 16)

                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)
                    .frame(width: 18)

                Text(kind.title)
                    .font(.body)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct MenuBarMetricOrderRow: View {
    let kind: MenuBarMetricKind
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        SettingsRow(title: kind.title) {
            HStack(spacing: 6) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
            }
            .buttonStyle(.bordered)
        }
    }
}
