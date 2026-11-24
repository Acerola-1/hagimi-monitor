import AppKit
import SwiftUI

/// 报表左侧模块切换导航栏。
struct ReportSidebarView: View {
    @Binding var selectedModule: ReportNavigationModule
    var eventCount: Int = 0

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("settings.colorSchemePreference") private var colorPreference = MonitorColorSchemePreference.vibrant.rawValue

    private var palette: ReportPalette {
        ReportPalette(preference: MonitorColorSchemePreference(rawValue: colorPreference) ?? .vibrant, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 分组 1：概览（去掉重复组标题，与页头统一命名）
            sidebarButton(module: .overview, shortcutKey: "1")

            Divider()
                .padding(.vertical, 4)
                .opacity(0.4)

            // 分组 2：硬件监测
            groupHeader(String(localized: "stats.r.navMonitoringGroup", defaultValue: "监测数据"))
            sidebarButton(module: .cpu, shortcutKey: "2")
            sidebarButton(module: .gpu, shortcutKey: "3")
            sidebarButton(module: .memory, shortcutKey: "4")
            sidebarButton(module: .network, shortcutKey: "5")
            sidebarButton(module: .disk, shortcutKey: "6")
            sidebarButton(module: .power, shortcutKey: "7")
            sidebarButton(module: .thermal, shortcutKey: "8")

            Divider()
                .padding(.vertical, 4)
                .opacity(0.4)

            // 分组 3：分析与记录
            groupHeader(String(localized: "stats.r.navAnalysisGroup", defaultValue: "分析与记录"))
            sidebarButton(module: .apps, shortcutKey: "9")
            sidebarButton(module: .events, badgeCount: eventCount)
            sidebarButton(module: .insights)
            sidebarButton(module: .details)

            Divider()
                .padding(.vertical, 4)
                .opacity(0.4)

            // 分组 4：本机全景规格
            groupHeader(String(localized: "stats.r.navHardwareGroup", defaultValue: "硬件档案"))
            sidebarButton(module: .machine)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 174)
        .background {
            palette.sidebarFill
        }
        .overlay(alignment: .trailing) {
            Divider().opacity(0.3)
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func sidebarButton(
        module: ReportNavigationModule,
        badgeCount: Int = 0,
        shortcutKey: KeyEquivalent? = nil
    ) -> some View {
        let item = ReportSidebarItem(
            module: module,
            isSelected: selectedModule == module,
            badgeCount: badgeCount,
            action: {
                selectedModule = module
            }
        )
        if let shortcutKey {
            item.keyboardShortcut(shortcutKey, modifiers: .command)
        } else {
            item
        }
    }
}

/// 侧边栏单个导航按钮：整行可点击，包含悬停动效、可选计数徽章与全尺寸命中区
private struct ReportSidebarItem: View {
    let module: ReportNavigationModule
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: module.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.white : (isHovered ? Color.primary : .secondary))

                Text(module.label)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
