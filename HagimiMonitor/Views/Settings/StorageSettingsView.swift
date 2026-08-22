import SwiftUI

/// 设置「数据统计 → 存储管理」:本地数据占用可视化与清理。
/// 从数据统计页底部入口进入,点击返回按钮回到数据统计。
struct StorageSettingsView: View {
    @ObservedObject var recorder: StatisticsRecorder
    @Environment(\.colorScheme) private var colorScheme
    /// 返回数据统计页。
    var onBack: () -> Void = {}

    @State private var pendingDeleteDays: Int?
    @State private var confirmClearAll = false
    @State private var confirmClearReport = false
    @State private var busy = false

    private var info: StatisticsRecorder.StorageInfo? { recorder.storageInfo }

    /// 监控数据 = 统计库 + 进程库,合并展示,用户不需要区分两者。
    private var monitorBytes: Int64 {
        (info?.databaseBytes ?? 0) + (info?.appStatsBytes ?? 0)
    }

    var body: some View {
        SettingsPage {
            backButton

            header

            SettingsGroup {
                ringCard
            }

            SettingsGroup(String(localized: "stats.storage.categories")) {
                categoryRow(
                    title: String(localized: "stats.settings.storage-data"),
                    bytes: monitorBytes,
                    detail: String(localized: "stats.storage.category-data-desc")
                ) {
                    Menu {
                        ForEach([30, 90, 180, 365], id: \.self) { days in
                            Button(String(localized: "stats.settings.cleanup-before-days \(days)")) {
                                pendingDeleteDays = days
                            }
                        }
                    } label: {
                        Text(String(localized: "stats.settings.cleanup-choose"))
                    }
                    .fixedSize()
                }

                SettingsDivider()

                categoryRow(
                    title: String(localized: "stats.settings.storage-report"),
                    bytes: info?.reportBytes ?? 0,
                    detail: String(localized: "stats.storage.category-report-desc"),
                    disabled: (info?.reportBytes ?? 0) == 0
                ) {
                    Button(role: .destructive) {
                        confirmClearReport = true
                    } label: {
                        Text(String(localized: "stats.storage.clear"))
                    }
                    .fixedSize()
                }
            }

            SettingsGroup(String(localized: "stats.storage.danger-zone")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "stats.settings.cleanup-all"))
                            .font(.body.weight(.medium))
                        Text(String(localized: "stats.settings.cleanup-all-subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Text(String(localized: "stats.settings.cleanup-all-button"))
                            .foregroundStyle(.red)
                    }
                    .fixedSize()
                    .disabled(busy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .confirmationDialog(
            Text(String(localized: "stats.settings.cleanup-before")),
            isPresented: Binding(
                get: { pendingDeleteDays != nil },
                set: { if !$0 { pendingDeleteDays = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                performDeleteBefore()
            } label: {
                Text(String(localized: "stats.settings.cleanup-confirm-button"))
            }
            Button(String(localized: "stats.settings.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "stats.settings.cleanup-before-confirm \(pendingDeleteDays ?? 0)"))
        }
        .confirmationDialog(
            Text(String(localized: "stats.settings.cleanup-all")),
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                run { recorder.deleteAllData(completion: $0) }
            } label: {
                Text(String(localized: "stats.settings.cleanup-confirm-button"))
            }
            Button(String(localized: "stats.settings.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "stats.settings.cleanup-all-confirm"))
        }
        .confirmationDialog(
            Text(String(localized: "stats.storage.clear-report")),
            isPresented: $confirmClearReport,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                run { recorder.clearReportCache(completion: $0) }
            } label: {
                Text(String(localized: "stats.settings.cleanup-confirm-button"))
            }
            Button(String(localized: "stats.settings.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "stats.storage.clear-report-confirm"))
        }
    }

    // MARK: - 返回

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(String(localized: "settings.sidebar.statistics"))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.bottom, -8)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "internaldrive")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "settings.sidebar.storage"))
                    .font(.headline.weight(.semibold))
                Text(String(localized: "stats.storage.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 环形构成图

    private var ringColors: (monitor: Color, report: Color) {
        let dark = colorScheme == .dark
        return (Color.accentColor, Color(hex: dark ? 0xD9A94A : 0xB45309))
    }

    @ViewBuilder
    private var ringCard: some View {
        let colors = ringColors
        let segments: [StorageRing.Segment] = [
            StorageRing.Segment(id: "monitor", bytes: monitorBytes, color: colors.monitor),
            StorageRing.Segment(id: "report", bytes: info?.reportBytes ?? 0, color: colors.report),
        ]

        VStack(spacing: 18) {
            StorageRing(
                segments: segments,
                centerTop: byteCount(info?.totalBytes ?? 0),
                centerBottom: ringCaption
            )
            .padding(.top, 10)

            HStack(spacing: 18) {
                legend(dot: colors.monitor, label: String(localized: "stats.settings.storage-data"), bytes: monitorBytes)
                legend(dot: colors.report, label: String(localized: "stats.settings.storage-report"), bytes: info?.reportBytes ?? 0)
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// 中心副标题:占磁盘容量比例 + 记录条数。
    private var ringCaption: String {
        guard let info, info.totalBytes > 0 else {
            return String(localized: "stats.storage.empty")
        }
        var parts: [String] = []
        if let capacity = diskCapacity, capacity > 0 {
            let percent = Double(info.totalBytes) / Double(capacity) * 100
            parts.append(String(localized: "stats.storage.ring-caption \(String(format: "%.1f%%", percent))"))
        }
        parts.append(String(localized: "stats.settings.storage-rows \(info.minuteCount + info.hourCount + info.dayCount)"))
        return parts.joined(separator: " · ")
    }

    private var diskCapacity: Int64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()))?[.systemSize] as? Int64
    }

    private func legend(dot: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot.opacity(0.9))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(byteCount(bytes))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 分类卡

    private func categoryRow<Action: View>(
        title: String,
        bytes: Int64,
        detail: String,
        disabled: Bool = false,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(byteCount(bytes))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            action()
                .disabled(disabled || busy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - 动作

    /// 统一 busy 包装:后台删除完成后回主线程刷新。
    private func run(_ operation: (@escaping () -> Void) -> Void) {
        busy = true
        operation {
            busy = false
        }
    }

    private func performDeleteBefore() {
        guard let days = pendingDeleteDays else { return }
        pendingDeleteDays = nil
        // 日历运算失败时宁可「什么都不删」也不能回退到当前时刻——
        // 那会把 DELETE WHERE t < now 变成清空全部历史。
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        run { recorder.deleteData(before: cutoff, completion: $0) }
    }

    // MARK: - 格式化

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// 存储构成环形图:各类数据按占比描边,中心展示总占用。
private struct StorageRing: View {
    struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    let segments: [Segment]
    let centerTop: String
    let centerBottom: String

    private var total: Int64 { max(segments.reduce(0) { $0 + $1.bytes }, 1) }

    /// 预计算各段起止比例(ViewBuilder 内不能累加状态)。
    private var arcs: [(id: String, from: Double, to: Double, color: Color)] {
        var result: [(String, Double, Double, Color)] = []
        var cursor = 0.0
        for segment in segments where segment.bytes > 0 {
            let fraction = Double(segment.bytes) / Double(total)
            result.append((segment.id, cursor, cursor + fraction, segment.color))
            cursor += fraction
        }
        return result
    }

    var body: some View {
        let gap: Double = arcs.count > 1 ? 0.01 : 0
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.10), lineWidth: 20)

            ForEach(arcs, id: \.id) { arc in
                Circle()
                    .trim(from: arc.from + gap / 2, to: max(arc.from + gap / 2, arc.to - gap / 2))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 4) {
                Text(centerTop)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(centerBottom)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 178, height: 178)
    }
}
