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
        #if DIRECT_DISTRIBUTION
        case disk
        case network
        #endif

        var id: String { rawValue }

        var label: String {
            switch self {
            case .cpu: return String(localized: "stats.r.kCpu", defaultValue: "CPU 消耗")
            case .memory: return String(localized: "stats.r.kMem", defaultValue: "内存占用")
            case .gpu: return String(localized: "stats.r.kGpu", defaultValue: "GPU 消耗")
            #if DIRECT_DISTRIBUTION
            case .disk: return String(localized: "stats.r.tabDisk", defaultValue: "磁盘读写")
            case .network: return String(localized: "stats.r.railNet", defaultValue: "网络流量")
            #endif
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

        return ReportCardView(
            title: String(localized: "stats.r.secAppsTitle", defaultValue: "应用活动排行"),
            icon: "app.badge.checkmark"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // 分类切换选择器：统一使用系统液态玻璃胶囊导航样式
                    ReportNavigationPicker(
                        title: "",
                        selection: $selectedTab
                    ) {
                        ForEach(AppRankingTab.allCases) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .fixedSize()

                    Spacer()

                    // R18: 数据作用域与聚合口径说明（自适应范围，今日不显示“整日聚合”）
                    Text(scopeNoticeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    // 包含系统应用开关（默认开启，靠右放置）
                    Toggle(isOn: $viewModel.includeSystemApps) {
                        Text(String(localized: "stats.report.includeSystemApps", defaultValue: "包含系统应用"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
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

    private var scopeNoticeText: String {
        if viewModel.selectedRange == .year {
            return String(localized: "stats.r.appsScopeNotice", defaultValue: "注：应用历史保留最多近 60 天，按整日汇总")
        } else if viewModel.isSingleDaySelected {
            return viewModel.selectedRange == .today
                ? String(localized: "stats.r.appsSampleNoticeToday", defaultValue: "注：数据源自每分钟前列采样，实时统计")
                : String(localized: "stats.r.appsSampleNoticeSingleDay", defaultValue: "注：数据源自每分钟前列采样，单日统计")
        } else {
            return String(localized: "stats.r.appsSampleNotice", defaultValue: "注：数据源自每分钟前列采样，按日汇总")
        }
    }

    private var currentEntries: [ReportAppRankingItem] {
        guard let apps = viewModel.rangeModel?.apps else { return [] }
        let rawList: [ReportAppRankingItem] = {
            switch selectedTab {
            case .cpu: return apps.cpuList
            case .memory: return apps.memList
            case .gpu: return apps.gpuList
            #if DIRECT_DISTRIBUTION
            case .disk: return apps.diskList
            case .network: return apps.netList
            #endif
            }
        }()

        let filtered = viewModel.includeSystemApps ? rawList : rawList.filter { !$0.isSystemApp }
        return Array(filtered.prefix(8))
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

                        Text(String(localized: "stats.r.alertCount \(alert.episodes.count)"))
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: 0xFF9500).opacity(0.15))
                            .foregroundStyle(Color(hex: 0xFF9500))
                            .clipShape(Capsule())

                        Text(String(localized: "stats.r.alertMaxDuration \(alert.maxDurationMinutes)"))
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
