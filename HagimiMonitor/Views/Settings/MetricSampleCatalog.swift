import SwiftUI

/// 监测项目示例读数目录:每项给出与采样器产出格式一致的典型值,供设置页
/// 预览卡渲染。示例仅用于设置语境的形态演示,不进入面板数据链。
enum MetricSampleTone {
    /// 常规数值色(面板 valueText)。
    case value
    /// 档位「正常」绿,与面板 severity 着色口径一致。
    case calm
}

struct MetricSamplePart {
    let text: String
    /// 数值后缀弱化单位(如 "%"、"dBm"),与面板数值主角化拆分同款;
    /// 采样侧不标 unit 的指标(GPU/内存/存储字节数值等)整串渲染。
    var unit: String? = nil
    var tone: MetricSampleTone = .value
}

struct MetricSample {
    var parts: [MetricSamplePart]
    /// Wi-Fi 信号条点亮格数(nil=不渲染信号条)。
    var signalBars: Int? = nil
}

enum MetricSampleCatalog {
    /// 内存压力主指标模式下,面板「压力」槽位实际渲染使用率百分比,
    /// 示例值随模式切换;普通模式为档位文本。
    static func sample(for kind: MonitorKind, id: String, memoryPressureMode: Bool = false) -> MetricSample {
        switch (kind, id) {
        case (.cpu, "system"):
            return MetricSample(parts: [MetricSamplePart(text: "23", unit: "%")])
        case (.cpu, "user"):
            return MetricSample(parts: [MetricSamplePart(text: "45", unit: "%")])
        case (.cpu, "idle"):
            return MetricSample(parts: [MetricSamplePart(text: "32", unit: "%")])
        case (.cpu, "uptime"):
            return MetricSample(parts: [MetricSamplePart(text: uptimeText)])
        case (.cpu, "thermal-pressure"):
            // 面板中温度与热压力合并整行,双值并排且档位按 severity 着色;
            // 温度为直连版专属采样(与面板同门控),沙盒版只显示档位。
            var parts: [MetricSamplePart] = []
            #if DISPLAY_CONTROL
            parts.append(MetricSamplePart(text: "45", unit: "°C"))
            #endif
            parts.append(MetricSamplePart(text: thermalNormalText, tone: .calm))
            return MetricSample(parts: parts)
        case (.cpu, "core-split"):
            return MetricSample(parts: [MetricSamplePart(text: "82% / 35%")])
        case (.cpu, "process-count"):
            return MetricSample(parts: [MetricSamplePart(text: "412")])
        case (.gpu, "gpu-memory"):
            return MetricSample(parts: [MetricSamplePart(text: "5.2 GB")])
        case (.gpu, "allocated"):
            return MetricSample(parts: [MetricSamplePart(text: "4.8 GB")])
        case (.gpu, "render"):
            return MetricSample(parts: [MetricSamplePart(text: "23%")])
        case (.gpu, "tiler"):
            return MetricSample(parts: [MetricSamplePart(text: "12%")])
        case (.gpu, "clock-state"):
            return MetricSample(parts: [MetricSamplePart(text: "P3 77%")])
        case (.gpu, "throttle"):
            return MetricSample(parts: [MetricSamplePart(text: "23%")])
        case (.gpu, "power-cap"):
            return MetricSample(parts: [MetricSamplePart(text: "75%")])
        case (.memory, "used"):
            return MetricSample(parts: [MetricSamplePart(text: "12.4 GB")])
        case (.memory, "pressure"):
            return memoryPressureMode
                ? MetricSample(parts: [MetricSamplePart(text: "64%")])
                : MetricSample(parts: [MetricSamplePart(text: memoryNormalText, tone: .calm)])
        case (.memory, "swap-used"):
            return MetricSample(parts: [MetricSamplePart(text: "1.2 GB")])
        case (.memory, "total"):
            return MetricSample(parts: [MetricSamplePart(text: "32 GB")])
        case (.memory, "compressed"):
            return MetricSample(parts: [MetricSamplePart(text: "2.1 GB")])
        case (.memory, "memory-bandwidth"):
            return MetricSample(parts: [MetricSamplePart(text: "12.4", unit: "GB/s")])
        case (.storage, "used"):
            return MetricSample(parts: [MetricSamplePart(text: "380 GB")])
        case (.storage, "free"):
            return MetricSample(parts: [MetricSamplePart(text: "120 GB")])
        case (.storage, "total"):
            return MetricSample(parts: [MetricSamplePart(text: "512 GB")])
        case (.storage, "smart"):
            return MetricSample(parts: [MetricSamplePart(text: smartNormalText, tone: .calm)])
        case (.network, "ipv4"):
            return MetricSample(parts: [MetricSamplePart(text: "192.168.1.23")])
        case (.network, "ipv6"):
            return MetricSample(parts: [MetricSamplePart(text: "fe80::a1b2:9c3d")])
        case (.network, "public-ip"):
            return MetricSample(parts: [MetricSamplePart(text: "203.0.113.7")])
        case (.network, "wifi-rssi"):
            return MetricSample(parts: [MetricSamplePart(text: "-52", unit: "dBm")], signalBars: 3)
        case (.network, "gateway-latency"):
            return MetricSample(parts: [MetricSamplePart(text: "3", unit: "ms")])
        case (.network, "wifi-ssid"):
            return MetricSample(parts: [MetricSamplePart(text: "Home-5G")])
        case (.battery, "health"):
            return MetricSample(parts: [MetricSamplePart(text: "92", unit: "%")])
        case (.battery, "cycle-count"):
            return MetricSample(parts: [MetricSamplePart(text: "312 / 1000")])
        case (.battery, "cell-balance"):
            let rating = String(localized: "cell-balance.rating.excellent")
            return MetricSample(parts: [MetricSamplePart(text: "Δ1 mV (\(rating))")])
        case (.battery, "temperature"):
            return MetricSample(parts: [MetricSamplePart(text: "31", unit: "°C")])
        case (.battery, "power-loss"):
            return MetricSample(parts: [MetricSamplePart(text: "7", unit: "%")])
        case (.battery, "voltage"):
            return MetricSample(parts: [MetricSamplePart(text: "12.8", unit: "V")])
        case (.battery, "current"):
            return MetricSample(parts: [MetricSamplePart(text: "1240", unit: "mA")])
        case (.battery, "capacity"):
            return MetricSample(parts: [MetricSamplePart(text: "5210 / 5683", unit: "mAh")])
        case (.battery, "cell-qmax"):
            return MetricSample(parts: [MetricSamplePart(text: "5212 / 5208 / 5215", unit: "mAh")])
        case (.battery, "cell-resistance"):
            return MetricSample(parts: [MetricSamplePart(text: "34 / 35 / 33", unit: "mΩ")])
        case (.battery, "thermal-limit-seconds"):
            return MetricSample(parts: [MetricSamplePart(text: "12600", unit: "s")])
        case (.battery, "time-at-high-soc"):
            return MetricSample(parts: [MetricSamplePart(text: "156", unit: "h")])
        default:
            return MetricSample(parts: [MetricSamplePart(text: "--")])
        }
    }

    /// 行头主值示例(面板 summary 形态):百分比模块为占用,网络为接口名,
    /// 风扇为最高转速,蓝牙为已连接设备数(与 MonitorStore 组装口径一致)。
    static func summary(for kind: MonitorKind, memoryPressureMode: Bool) -> MetricSample {
        switch kind {
        case .cpu:
            return MetricSample(parts: [MetricSamplePart(text: "12", unit: "%")])
        case .gpu:
            return MetricSample(parts: [MetricSamplePart(text: "8", unit: "%")])
        case .memory:
            return memoryPressureMode
                ? MetricSample(parts: [MetricSamplePart(text: memoryNormalText, tone: .calm)])
                : MetricSample(parts: [MetricSamplePart(text: "64", unit: "%")])
        case .storage:
            return MetricSample(parts: [MetricSamplePart(text: "74", unit: "%")])
        case .network:
            return MetricSample(parts: [MetricSamplePart(text: "Wi-Fi")])
        case .battery:
            return MetricSample(parts: [MetricSamplePart(text: "76", unit: "%")])
        case .fan, .bluetooth:
            // 无监测项目可勾的模块不渲染预览卡,行头示例仅作兜底。
            return MetricSample(parts: [MetricSamplePart(text: "--")])
        }
    }

    /// 行头示例曲线样本:平缓起伏的典型负载形态;内存压力模式的行尾曲线
    /// 复用同一形态(压力百分比历史同为 0~100 区间的平缓序列)。
    static let sparklineSamples: [Double] = [18, 26, 22, 34, 30, 45, 38, 52, 44, 40, 48, 42]

    /// 行头示例进度条占比(内存/存储):与 summary 百分比一致。
    static let memoryUsageFraction: Double = 0.64
    static let storageUsageFraction: Double = 0.74

    /// CPU 逐核示例(4P + 6E 拓扑):排列顺序与真实采样同构——按 CPU
    /// 逻辑索引序(M4 上能效核占 0-5 在前,性能核 6-9 在后),分组占用
    /// 均值与 P/E tile 显示值自洽(82% / 35%,与 core-split 示例同口径)。
    /// 预览不跑采样,以静态数据渲染真实 CPUCoresDetail。
    static let cpuCoreDetail: CPUCoreDetail = {
        let eUsages: [Double] = [35, 30, 40, 33, 36, 36]
        let pUsages: [Double] = [88, 76, 85, 79]
        var cores = eUsages.enumerated().map { offset, usage in
            CPUCoreLoad(index: offset, usage: usage, isPerformance: false)
        }
        cores += pUsages.enumerated().map { offset, usage in
            CPUCoreLoad(index: eUsages.count + offset, usage: usage, isPerformance: true)
        }
        let eAverage = eUsages.reduce(0, +) / Double(eUsages.count)
        let pAverage = pUsages.reduce(0, +) / Double(pUsages.count)
        return CPUCoreDetail(cores: cores, performanceUsage: pAverage, efficiencyUsage: eAverage)
    }()

    /// 功率流示例模块:插电充电场景。status/battery-flow/adapter 的键与
    /// 值语义与 BatterySampler 产出同口径(PowerFlowDiagram 按同一组键
    /// 读取流向与瓦数),电量取 module.value。
    static let powerFlowModule: MonitorModule = MonitorModule(
        kind: .battery,
        context: nil,
        value: 76,
        summary: "76%",
        metrics: [
            MonitorMetric(name: MonitorMetricKey.type, value: "battery"),
            MonitorMetric(name: "status", value: "charging"),
            MonitorMetric(name: "adapter", value: "96 W", numericValue: 96, unit: " W"),
            MonitorMetric(name: "power", value: "18.3 W", numericValue: 18.3, unit: " W"),
            MonitorMetric(name: "power-in", value: "42.5 W", numericValue: 42.5, unit: " W"),
            MonitorMetric(name: "battery-flow", value: "24.2 W", numericValue: 24.2, unit: " W"),
            MonitorMetric(name: "time-remaining", value: "45", numericValue: 45),
            MonitorMetric(name: "pd-contract", value: "20V/3.25A/65W"),
            MonitorMetric(name: "pd-tiers", value: "5/9/15/20V"),
            MonitorMetric(name: "adapter-port", value: "USB-C 4"),
            MonitorMetric(name: "adapter-transports", value: "USB2·DP"),
            MonitorMetric(name: "input-telemetry", value: "20.12 V · 2.11 A"),
            MonitorMetric(name: "not-charging-reason", value: "0", numericValue: 0),
            MonitorMetric(name: "charging-allowed", value: "1", numericValue: 1)
        ],
        samples: sparklineSamples
    )

    /// 排名页示例：五个应用行（图标留空，预览用占位图标渲染）。
    /// 瓦数形态与 `ProcessEnergySampler` 同口径（同用户可读进程的实测平均功率）。
    static let appEnergyRankingShares: [ProcessEnergyShare] = [
        ProcessEnergyShare(pid: 1, name: "Xcode", icon: nil, share: 0.34, watts: 1.86),
        ProcessEnergyShare(pid: 2, name: "Safari", icon: nil, share: 0.26, watts: 1.42),
        ProcessEnergyShare(pid: 3, name: "Music", icon: nil, share: 0.18, watts: 0.98),
        ProcessEnergyShare(pid: 4, name: "Photos", icon: nil, share: 0.12, watts: 0.65),
        ProcessEnergyShare(pid: 5, name: "Notes", icon: nil, share: 0.07, watts: 0.38)
    ]

    /// 运行时长示例与采样器同参格式化(abbreviated、最多两单位),
    /// 保证中英文语境下的示例形态一致。
    private static let uptimeText: String = {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: 13 * 86400 + 4 * 3600) ?? "13d"
    }()

    private static let thermalNormalText = String(localized: "thermal-pressure.normal")
    private static let memoryNormalText = String(localized: "memory-pressure.normal")
    private static let smartNormalText = String(localized: "storage-smart.verified")
}

/// 面板明细格复刻:trackFill 内衬 + 标签左 / mono bold 数值右,单位弱化、
/// 档位着色、信号条形态与面板明细格一致。
struct MetricPreviewTile: View {
    let kind: MonitorKind
    let id: String
    let title: String
    /// 内存压力主指标模式:「压力」槽位示例在两种模式下取不同形态。
    let memoryPressureMode: Bool
    let palette: MonitorPalette

    private var sample: MetricSample {
        MetricSampleCatalog.sample(for: kind, id: id, memoryPressureMode: memoryPressureMode)
    }

    var body: some View {
        HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
            Text(title)
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(palette.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)

            sampleView(sample)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.trackFill))
    }

    @ViewBuilder
    private func sampleView(_ sample: MetricSample) -> some View {
        HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
            if let signalBars = sample.signalBars {
                WifiSignalBars(level: signalBars)
            }
            ForEach(Array(sample.parts.enumerated()), id: \.offset) { _, part in
                partView(part)
            }
        }
    }

    private func partView(_ part: MetricSamplePart) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(part.text)
                .monitorPanelMonoFont(.footnote, weight: .bold)
                .foregroundStyle(color(for: part.tone))
                .lineLimit(1)
            if let unit = part.unit {
                Text(unit)
                    .monitorPanelCaptionFont(.footnote)
                    .foregroundStyle(palette.captionText)
                    .fixedSize()
            }
        }
    }

    private func color(for tone: MetricSampleTone) -> Color {
        switch tone {
        case .value:
            return palette.valueText
        case .calm:
            return palette.severityTint(for: .calm)
        }
    }
}
