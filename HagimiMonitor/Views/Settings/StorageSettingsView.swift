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

    /// 监控数据有效值 = 统计库 + 进程库在用数据页(含未合并 WAL),合并展示;
    /// 表结构页/空闲页等固定开销在环形图中单列归入系统数据。
    private var monitorBytes: Int64 {
        info?.monitorDataBytes ?? 0
    }

    var body: some View {
        SettingsPage {
            backButton

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
                    .compatibleSystemGlassButtonStyle()
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
                    .compatibleSystemGlassButtonStyle()
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
                    .compatibleSystemGlassButtonStyle()
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

    @State private var backHovered = false

    private var backButton: some View {
        Button(action: onBack) {
            CompatibleGlassContainer(spacing: 0) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(backHovered ? Color.primary : Color.secondary)
                    .frame(width: 30, height: 30)
                    .compatibleLiquidSurface(
                        tint: Color.secondary.opacity(backHovered ? 0.14 : 0.07),
                        in: Circle(),
                        style: .liquidInteractive
                    ) {
                        Color.secondary.opacity(backHovered ? 0.16 : 0.09)
                    }
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .onHover { backHovered = $0 }
    }

    // MARK: - 环形构成图

    private var ringColors: (monitor: Color, report: Color, fixed: Color) {
        let dark = colorScheme == .dark
        return (
            // QQ 存储环同款青蓝 × 紫罗兰两主色,深色模式提亮一档;
            // 系统段用带蓝调的板岩灰,保持与主色的同一色彩家族。
            Color(hex: dark ? 0x38BDFF : 0x00A5EF),
            Color(hex: dark ? 0xCA92F8 : 0xB066E8),
            Color(hex: dark ? 0x94A0AE : 0x9AA5B3)
        )
    }

    @ViewBuilder
    private var ringCard: some View {
        let colors = ringColors
        let segments: [StorageRing.Segment] = [
            StorageRing.Segment(id: "monitor", bytes: monitorBytes, color: colors.monitor),
            StorageRing.Segment(id: "report", bytes: info?.reportBytes ?? 0, color: colors.report),
            StorageRing.Segment(id: "fixed", bytes: info?.systemBytes ?? 0, color: colors.fixed),
        ]

        VStack(spacing: 16) {
            StorageRing(
                segments: segments,
                centerTop: byteCount(info?.totalBytes ?? 0),
                centerBottom: ringCaption
            )

            HStack(spacing: 14) {
                legend(dot: colors.monitor, label: String(localized: "stats.settings.storage-data"), bytes: monitorBytes)
                legend(dot: colors.report, label: String(localized: "stats.settings.storage-report"), bytes: info?.reportBytes ?? 0)
                legend(dot: colors.fixed, label: String(localized: "stats.storage.system"), bytes: info?.systemBytes ?? 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    /// 中心副标题:占磁盘容量比例与记录条数分行排布,居中叠在环心。
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
        return parts.joined(separator: "\n")
    }

    private var diskCapacity: Int64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()))?[.systemSize] as? Int64
    }

    private func legend(dot: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(byteCount(bytes))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.8))
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
/// 描边以路径为中心渲染,会在 frame 外溢出 lineWidth/2,故组件自带外层
/// padding 把溢出吃进布局边界,宿主无需为此预留间隙。
private struct StorageRing: View {
    struct Segment: Identifiable {
        let id: String
        let bytes: Int64
        let color: Color
    }

    let segments: [Segment]
    let centerTop: String
    let centerBottom: String

    /// "29.5 MB" → (数值大字, 单位小字);ByteCountFormatter 的空格分隔约定,
    /// 拆不出两段(如 "0 字节")时整体按数值渲染。
    private var centerValue: (value: String, unit: String?) {
        let parts = centerTop.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (centerTop, nil) }
        return (parts[0], parts[1])
    }

    private static let lineWidth: CGFloat = 18

    /// 段间以平头端面 + 统一间隙分隔,接缝是一条干净的切线;
    /// 圆头帽会让后段叠压前段末端形成异色瘤点,不适合多段构成环。
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
        // 间隙按线宽折算成约 3pt 的弧长,多段时保持恒定观感。
        let gap: Double = arcs.count > 1 ? 3.0 / (2 * .pi * 82) : 0
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: Self.lineWidth)

            ForEach(arcs, id: \.id) { arc in
                Circle()
                    .trim(from: arc.from + gap / 2, to: max(arc.from + gap / 2, arc.to - gap / 2))
                    .stroke(
                        // 角向渐变让每段沿走向由浅入深,与页内健康评分环同语言;
                        // 渐变起点透明度抬高,避免段起点发灰与段终点形成明度断崖。
                        AngularGradient(
                            colors: [arc.color.opacity(0.75), arc.color],
                            center: .center,
                            startAngle: .degrees(360 * arc.from),
                            endAngle: .degrees(360 * arc.to)
                        ),
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(centerValue.value)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit = centerValue.unit {
                        Text(unit)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(centerBottom)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 164, height: 164)
        .padding(Self.lineWidth / 2 + 5)
    }
}
