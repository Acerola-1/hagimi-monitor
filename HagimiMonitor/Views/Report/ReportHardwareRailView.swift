import AppKit
import Combine
import SwiftUI

/// 监控模块右栏硬件规格与实时状态卡片。
struct ReportHardwareRailView: View {
    let moduleId: String
    let meta: ReportMeta?
    let hardware: HardwareInventory?
    @ObservedObject var liveSource: ReportLiveHardwareSource

    private static let liveRowKeys: [String: [String]] = [
        "cpu": ["hwLiveCpuUsage", "hwLiveThermal", "hwLiveProcessCount", "hwLiveIdle"],
        "gpu": ["hwLiveGpuUsage", "hwLiveGpuMemory", "hwLiveRenderer", "hwLiveTiler"],
        "memory": ["hwLiveMemUsed", "hwLiveCompressed", "hwLiveSwap", "hwLivePressure"],
        "network": ["hwLiveDownload", "hwLiveUpload", "hwLiveSignal"],
        "disk": ["hwLiveDiskUsed", "hwLiveDiskFree", "hwLiveDiskRead", "hwLiveDiskWrite"],
        "power": ["hwLiveBatteryLevel", "hwLiveBatteryState", "hwLiveBatteryTemp"]
    ]

    var body: some View {
        let liveReadings = liveSource.liveReadings
        VStack(alignment: .leading, spacing: 14) {
            // 卡片头部：规格档案标题与机型
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "stats.r.hwCardTitle", defaultValue: "硬件规格与档案"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if let device = meta?.deviceName, !device.isEmpty {
                    Text(device)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 2)

            // 静态硬件规格分组
            let groups = hardware?.rails[moduleId] ?? []
            if !groups.isEmpty {
                ForEach(groups, id: \.id) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name.resolve(hwText))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 4) {
                            ForEach(Array(group.facts.enumerated()), id: \.offset) { _, fact in
                                HStack {
                                    Text(fact.label.resolve(hwText))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    Text(fact.value ?? "—")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(fact.value != nil ? .primary : .tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    Divider()
                        .opacity(0.4)
                }
            } else {
                Text(String(localized: "stats.r.hwNoData", defaultValue: "暂无当前模块硬件规格"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            // 实时运行状态分组
            if let keys = Self.liveRowKeys[moduleId], !keys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(String(localized: "stats.r.hwLiveGroup", defaultValue: "运行状态"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // 实时绿点指示标
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(String(localized: "stats.r.hwLiveTag", defaultValue: "实时"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }

                    VStack(spacing: 4) {
                        ForEach(keys, id: \.self) { key in
                            let label = hwText(key)
                            let val = liveReadings[key]
                            HStack {
                                Text(label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(val ?? "—")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(val != nil ? .primary : .tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .frame(width: 300)
    }
}
