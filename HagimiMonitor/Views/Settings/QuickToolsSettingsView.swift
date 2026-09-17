import SwiftUI

/// 设置「小工具」:控制面板底部工具入口的显隐,以及各工具自己的参数。
/// 工具列表由 QuickToolKind 的 CaseIterable 驱动,新增工具只需补枚举 case
/// 与本地化,本页与浮层自动跟随。
///
/// 层级原则:每个工具各自成卡,参数只长在该工具自己的卡片里(不另起一个只
/// 服务单个工具的模块)。有参数的工具卡内折叠,默认收起、展开态不持久化。
struct QuickToolsSettingsView: View {
    @ObservedObject var settings: MonitorSettings

    /// 当前展开的工具;同一时刻只展开一个。不持久化——每次打开设置都从
    /// 收起态开始,行为可预期。
    @State private var expandedTool: QuickToolKind?

    var body: some View {
        SettingsPage {
            SettingsGroup {
                SettingsRow(title: String(localized: "settings.show-in-panel")) {
                    Toggle("", isOn: $settings.quickToolsVisible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            // 入口关闭后,工具列表失去意义,直接隐藏(与模块页一致)。
            if settings.quickToolsVisible {
                VStack(alignment: .leading, spacing: 9) {
                    SettingsGroupTitle(String(localized: "settings.quick-tools.group"))
                    VStack(spacing: 8) {
                        ForEach(QuickToolKind.allCases, id: \.self) { kind in
                            QuickToolCard(
                                settings: settings,
                                kind: kind,
                                isExpanded: expandedTool == kind,
                                onToggleExpansion: { toggleExpansion(of: kind) }
                            )
                        }
                    }
                }
            }
        }
        .animation(.default, value: settings.quickToolsVisible)
    }

    /// 展开/收起:与打卡卡同一条曲线(0.2s easeOut),箭头旋转与卡片高度同拍。
    private func toggleExpansion(of kind: QuickToolKind) {
        withAnimation(QuickToolCard.expansionAnimation) {
            expandedTool = expandedTool == kind ? nil : kind
        }
    }
}

/// 单个工具的设置卡片:图标 + 名称 + 行尾开关,有参数的工具在卡内展开参数。
///
/// 行头名称区(含展开箭头)整块可点,开关是它的兄弟节点——SwiftUI 里把开关塞进
/// 另一个按钮的 label 里,谁吃掉点击是不明确的(点开关连带展开、或点开关没反应,
/// 两种翻车方式都有)。箭头跟在名称后面而不是排到开关右侧:排右侧会把它右侧的
/// 宽度吃进布局,键盘锁定的开关就会被挤得比另外两张卡靠左,三个开关不在一条线上。
private struct QuickToolCard: View {
    @ObservedObject private var store = QuickToolsStore.shared
    @ObservedObject var settings: MonitorSettings
    let kind: QuickToolKind
    let isExpanded: Bool
    let onToggleExpansion: () -> Void

    static let expansionAnimation = Animation.easeOut(duration: 0.2)

    /// 卡片行内衬。子行按「内衬 + 图标 + 间距」缩进,与标题文字左对齐;
    /// 不用绝对值,图标尺寸变了子行跟着走。
    private static let rowPadding: CGFloat = 14
    private static let iconSize: CGFloat = 32
    private static let iconSpacing: CGFloat = 12
    private static var subRowLeading: CGFloat { rowPadding + iconSize + iconSpacing }

    var body: some View {
        SettingsCard {
            header
            if kind.hasParameters, isExpanded {
                parameters
            }
        }
        // 展开参数区即外接键盘清单变得可见的时刻:HID 扫描只在展开瞬间
        // 执行一次,清单不沿用页面打开以来的陈旧插拔状态。
        .onChange(of: isExpanded) { _, expanded in
            if expanded, kind == .keyboardLock {
                store.refreshKeyboardTopology()
            }
        }
    }

    // MARK: - 行头

    private var header: some View {
        HStack(spacing: Self.iconSpacing) {
            if kind.hasParameters {
                expandButton
            } else {
                headerLabel
            }
            trailingControl
        }
        .padding(.horizontal, Self.rowPadding)
        .padding(.vertical, 12)
    }

    private var expandButton: some View {
        Button(action: onToggleExpansion) {
            headerLabel {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StaticPressButtonStyle())
    }

    private var headerLabel: some View {
        headerLabel { EmptyView() }
    }

    private func headerLabel<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Self.iconSpacing) {
            iconTile
            Text(String(localized: kind.titleKey))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            trailing()
            Spacer(minLength: Self.iconSpacing)
        }
    }

    /// 与浮层磁贴同源的图标:设置里的这行和浮层里的那块磁贴一眼能对上。
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.accentColor.opacity(0.13))
            .frame(width: Self.iconSize, height: Self.iconSize)
            .overlay(
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
    }

    /// 行尾开关:统一控制「在浮层里显示这个磁贴」。
    /// 三张卡片的开关右内衬一致,整张卡只有一条控制列。
    @ViewBuilder
    private var trailingControl: some View {
        Toggle(String(localized: kind.titleKey), isOn: Binding(
            get: { settings.isQuickToolVisible(kind) },
            set: { settings.setQuickToolVisible($0, for: kind) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
    }

    // MARK: - 键盘锁定参数

    @ViewBuilder
    private var parameters: some View {
        SettingsDivider()
        externalKeyboardRow
        SettingsDivider()
        autoUnlockRow
    }

    /// 外接键盘预设偏好开关。副标题显示设备连接状态或「本机没有内置键盘」说明。
    /// 默认只锁定内置键盘(开关为关),开启后将同时拦截外接键盘。
    private var externalKeyboardRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.quick-tools.keyboard-lock.external"))
                    .font(.body)
                Text(externalKeyboardDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $settings.keyboardLockBlocksExternal)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.leading, Self.subRowLeading)
        .padding(.trailing, Self.rowPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    private var externalKeyboardDetail: String {
        guard store.hasBuiltInKeyboard else {
            return String(localized: "settings.quick-tools.keyboard-lock.no-built-in-keyboard")
        }
        let names = store.externalKeyboardNames
        guard !names.isEmpty else {
            return String(localized: "settings.quick-tools.keyboard-lock.no-external-keyboard")
        }
        return String(
            format: String(localized: "settings.quick-tools.keyboard-lock.connected-external-keyboards"),
            names.formatted(.list(type: .and))
        )
    }

    private var autoUnlockRow: some View {
        HStack(spacing: 16) {
            Text(String(localized: "settings.quick-tools.keyboard-lock.auto-unlock"))
                .font(.body)
            Spacer(minLength: 16)
            Picker("", selection: $settings.keyboardLockAutoUnlockMinutes) {
                ForEach(KeyboardLockController.autoUnlockMinuteOptions, id: \.self) { minutes in
                    Text(String(localized: "settings.quick-tools.keyboard-lock.auto-unlock.minutes \(minutes)"))
                        .tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.leading, Self.subRowLeading)
        .padding(.trailing, Self.rowPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}
