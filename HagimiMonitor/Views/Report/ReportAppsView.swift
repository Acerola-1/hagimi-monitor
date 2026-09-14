import AppKit
import SwiftUI

/// 应用排行与高负载告警视图：支持 CPU/内存/GPU/网络分类排行、应用图标原生呈现与精准兜底、活跃档位提示与告警事件列表。
struct ReportAppsView: View {
    @ObservedObject var viewModel: NativeReportViewModel
    @State private var selectedTab: AppRankingTab = .cpu

    enum AppRankingTab: String, CaseIterable, Identifiable {
        case cpu
        case memory
        case gpu
        case network

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cpu: return String(localized: "stats.r.kCpu", defaultValue: "CPU 占用")
            case .memory: return String(localized: "stats.r.kMem", defaultValue: "内存占用")
            case .gpu: return String(localized: "stats.r.kGpu", defaultValue: "GPU 占用")
            case .network: return String(localized: "stats.r.railNet", defaultValue: "网络流量")
            }
        }
    }

    var body: some View {
        // R19: 本模块无 HardwareRail 契约，采用全宽布局
        VStack(spacing: 16) {
            // 1. 分类选择与排行列表卡片
            rankingCard

            // 2. 高负载告警卡片（若有告警记录）
            if let alerts = viewModel.rangeModel?.apps.highLoadAlerts, !alerts.isEmpty {
                alertsCard(alerts: alerts)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 1. 应用排行卡片

    private var rankingCard: some View {
        let entries = currentEntries
        let isLongRange = (viewModel.selectedRange == .year)

        return ReportCardView(
            title: String(localized: "stats.r.secAppsTitle", defaultValue: "应用活动排行"),
            icon: "app.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // 分类切换选择器
                    Picker("", selection: $selectedTab) {
                        ForEach(AppRankingTab.allCases) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    Spacer()

                    // R18: 数据作用域提示
                    if isLongRange {
                        Text(String(localized: "stats.r.appsScopeNotice", defaultValue: "注：应用历史保留最多近 60 天"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if entries.isEmpty {
                    ReportEmptyPlaceholder(text: String(localized: "stats.r.emptyApps", defaultValue: "所选范围内无应用采样明细"))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, app in
                            appRow(index: index + 1, app: app)
                            if index < entries.count - 1 {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentEntries: [ReportAppRankingItem] {
        guard let apps = viewModel.rangeModel?.apps else { return [] }
        switch selectedTab {
        case .cpu: return apps.cpuList
        case .memory: return apps.memList
        case .gpu: return apps.gpuList
        case .network: return apps.netList
        }
    }

    private func appRow(index: Int, app: ReportAppRankingItem) -> some View {
        HStack(spacing: 12) {
            // 序号
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(index <= 3 ? Color.primary : Color.secondary)
                .frame(width: 18, alignment: .trailing)

            // 图标（原生 NSImage 渲染，支持缓存与无泄漏清理，R13: 精准兜底符号）
            appIconView(appKey: app.appKey, data: app.iconData)

            // 应用名与 Bundle ID (R23: 弹性宽度防挤压)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(app.appKey)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: 300, alignment: .leading)

            // 档位提示说明
            if let hint = app.tierHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 主指标数值
            Text(app.valueText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 原生图标渲染与契约兜底 (R13)

    private func appIconView(appKey: String, data: Data?) -> some View {
        Group {
            if let image = ReportIconProvider.shared.icon(forAppKey: appKey, data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                let symbol = ReportIconProvider.shared.fallbackSymbol(forAppKey: appKey)
                Image(systemName: symbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - 2. 告警事件列表卡片 (R16 & R21: 真实只读告警语义)

    private func alertsCard(alerts: [ReportHighLoadAppGroup]) -> some View {
        ReportCardView(
            title: String(localized: "stats.r.alertsTitle", defaultValue: "高负载告警记录"),
            icon: "exclamationmark.triangle.fill"
        ) {
            VStack(spacing: 8) {
                ForEach(alerts) { alert in
                    HStack(spacing: 10) {
                        appIconView(appKey: alert.appKey, data: alert.iconData)

                        Text(alert.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("告警 \(alert.episodes.count) 次")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: 0xFF9500).opacity(0.15))
                            .foregroundStyle(Color(hex: 0xFF9500))
                            .clipShape(Capsule())

                        Text("持续至多 \(alert.maxDurationMinutes)m")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let start = alert.earliestStart {
                            Text(ReportUIHelper.formatDateTime(start))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
