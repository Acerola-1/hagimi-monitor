import AppKit
import Charts
import SwiftUI

/// 报表通用 UI 辅助组件与格式化工具。
enum ReportUIHelper {
    // MARK: - 静态格式化器缓存（线程安全，消除每秒重复构造开销）

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return df
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }()

    // MARK: - 通用配色（对齐 MonitorPalette 语义）

    static let cpuColor = Color(hex: 0xEE7D32)
    static let peakColor = Color(hex: 0xF5A623)
    static let gpuColor = Color(hex: 0xA855F7)
    static let memoryColor = Color(hex: 0x1192E8)
    static let swapColor = Color(hex: 0x6366F1)
    static let networkDownColor = Color(hex: 0x0EA5E9)
    static let networkUpColor = Color(hex: 0x8B5CF6)
    static let diskReadColor = Color(hex: 0x10B981)
    static let diskWriteColor = Color(hex: 0x14B8A6)
    static let powerColor = Color(hex: 0xF59E0B)
    static let batteryColor = Color(hex: 0x10B981)
    static let thermalColor = Color(hex: 0xEF4444)

    // MARK: - 格式化函数

    static func formatDateShort(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func formatDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    static func formatTimeOnly(_ date: Date) -> String {
        timeOnlyFormatter.string(from: date)
    }

    static func formatBytesRate(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0 B/s" }
        let mbs = bytesPerSec / (1024 * 1024)
        if mbs >= 1024 {
            return String(format: "%.1f GB/s", mbs / 1024)
        } else if mbs >= 1 {
            return String(format: "%.1f MB/s", mbs)
        } else {
            let kbs = bytesPerSec / 1024
            if kbs >= 1 {
                return String(format: "%.1f KB/s", kbs)
            } else {
                return String(format: "%.0f B/s", bytesPerSec)
            }
        }
    }

    static func formatBytes(_ bytes: Double) -> String {
        guard bytes > 0 else { return "0 B" }
        let gb = bytes / (1024 * 1024 * 1024)
        if gb >= 1024 {
            return String(format: "%.2f TB", gb / 1024)
        } else if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            let mb = bytes / (1024 * 1024)
            if mb >= 1 {
                return String(format: "%.1f MB", mb)
            } else {
                return String(format: "%.0f KB", bytes / 1024)
            }
        }
    }

    static func formatHours(_ seconds: Double) -> String {
        let h = seconds / 3600.0
        if h >= 1.0 {
            return String(format: "%.1fh", h)
        } else {
            let m = seconds / 60.0
            return String(format: "%.0fm", m)
        }
    }

    // MARK: - 热状态语义映射（0~3 档位，禁止乘 100）

    static func thermalStateLabel(_ level: Double?) -> String {
        guard let level else { return "—" }
        if level < 0.5 {
            return String(localized: "stats.r.thermalNominal", defaultValue: "正常")
        } else if level < 1.5 {
            return String(localized: "stats.r.thermalFair", defaultValue: "中度")
        } else if level < 2.5 {
            return String(localized: "stats.r.thermalSerious", defaultValue: "严重")
        } else {
            return String(localized: "stats.r.thermalCritical", defaultValue: "紧急")
        }
    }

    static func formatThermalLevel(_ level: Double?) -> String {
        guard let level else { return "—" }
        let label = thermalStateLabel(level)
        return "\(label) (\(String(format: "%.1f", level)))"
    }

    // MARK: - 模板变量替换工具（解决 {v}、{time} 未插值上屏问题）

    static func interpolateTemplate(_ raw: String, replacements: [String: String]) -> String {
        var result = raw
        for (key, val) in replacements {
            result = result.replacingOccurrences(of: "{\(key)}", with: val)
        }
        return result
    }

    // MARK: - 二分查找最近数据行（O(log N)，杜绝鼠标移动全表线性扫描）

    static func findClosestRow(to date: Date, in rows: [StatisticsRow]) -> StatisticsRow? {
        guard !rows.isEmpty else { return nil }
        let target = Int64(date.timeIntervalSince1970)

        var low = 0
        var high = rows.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let midT = rows[mid].t
            if midT == target {
                return rows[mid]
            } else if midT < target {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        // 检查 low 和 high 两个边界点，取距离更近者
        let candidate1 = (low < rows.count) ? rows[low] : nil
        let candidate2 = (high >= 0) ? rows[high] : nil

        switch (candidate1, candidate2) {
        case let (c1?, c2?):
            return abs(c1.t - target) < abs(c2.t - target) ? c1 : c2
        case let (c1?, nil):
            return c1
        case let (nil, c2?):
            return c2
        default:
            return nil
        }
    }
}

/// 通用 KPI 卡片组件
struct ReportKpiCard: View {
    let title: String
    let value: String
    let caption: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

/// 图例组件
struct ReportLegendItem: View {
    let title: String
    let color: Color
    var isDashed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if isDashed {
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 4, height: 2)
                    Rectangle().fill(color).frame(width: 4, height: 2)
                }
            } else {
                Capsule().fill(color).frame(width: 12, height: 3)
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// 空数据占位组件
struct ReportEmptyPlaceholder: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// 5 阶负载分布通用展示卡片
struct ReportLoadDistributionCard: View {
    let distribution: ReportDistribution?
    let title: String
    var subtitle: String? = nil

    private let colors = [
        Color.secondary.opacity(0.4),
        Color(hex: 0x7A91B4),
        Color(hex: 0x34C759),
        Color(hex: 0xFF9500),
        Color(hex: 0xFF3B30)
    ]

    var body: some View {
        ReportCardView(
            title: title,
            subtitle: subtitle,
            icon: "chart.bar.xaxis"
        ) {
            if let dist = distribution, dist.hasData {
                VStack(spacing: 8) {
                    ForEach(dist.buckets, id: \.index) { bucket in
                        let color = colors[min(bucket.index, colors.count - 1)]
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)

                            Text(bucket.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                                .frame(width: 65, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.12))
                                    Capsule()
                                        .fill(color)
                                        .frame(width: max(4, geo.size.width * CGFloat(bucket.percent / 100.0)))
                                }
                            }
                            .frame(height: 8)

                            Text(String(format: "%.1f%%", bucket.percent))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 45, alignment: .trailing)

                            Text(bucket.hoursText)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .frame(height: 180)
            } else {
                ReportEmptyPlaceholder(text: String(localized: "stats.r.emptySection", defaultValue: "暂无负载分布数据"))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
