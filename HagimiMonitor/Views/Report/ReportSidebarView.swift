import AppKit
import SwiftUI

/// 报表左侧模块切换导航栏。
struct ReportSidebarView: View {
    @Binding var selectedModule: ReportNavigationModule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 分组 1：核心概览
            groupHeader(String(localized: "stats.r.navOverviewGroup", defaultValue: "总览"))
            sidebarButton(module: .overview)

            Divider()
                .padding(.vertical, 4)
                .opacity(0.4)

            // 分组 2：硬件监测
            groupHeader(String(localized: "stats.r.navMonitoringGroup", defaultValue: "监测数据"))
            sidebarButton(module: .cpu)
            sidebarButton(module: .gpu)
            sidebarButton(module: .memory)
            sidebarButton(module: .network)
            sidebarButton(module: .disk)
            sidebarButton(module: .power)
            sidebarButton(module: .thermal)

            Divider()
                .padding(.vertical, 4)
                .opacity(0.4)

            // 分组 3：分析与洞察
            groupHeader(String(localized: "stats.r.navAnalysisGroup", defaultValue: "分析与记录"))
            sidebarButton(module: .apps)
            sidebarButton(module: .events)
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
        .frame(width: 170)
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.35)
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

    private func sidebarButton(module: ReportNavigationModule) -> some View {
        ReportSidebarItem(
            module: module,
            isSelected: selectedModule == module,
            action: {
                selectedModule = module
            }
        )
    }
}

/// 侧边栏单个导航按钮：整行可点击，包含悬停动效与全尺寸命中区
private struct ReportSidebarItem: View {
    let module: ReportNavigationModule
    let isSelected: Bool
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

                Spacer(minLength: 0)
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
