import AppKit
import SwiftUI

struct MonitorPanelView: View {
    @ObservedObject var store: MonitorStore
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 6) {
                ForEach(store.modules) { module in
                    row(for: module)
                        .glassEffectID("metric-\(module.kind.id)", in: glassNamespace)
                }

                HStack(spacing: 8) {
                    Button {
                        openActivityMonitor()
                    } label: {
                        Label("活动监视器", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 2)
            }
            .padding(10)
            .frame(width: 320)
            .background(.clear)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .glassEffectID("monitor-panel", in: glassNamespace)
        }
    }

    @ViewBuilder
    private func row(for module: MonitorModule) -> some View {
        switch module.kind {
        case .cpu:
            MetricGlassRow(module: module, detail: module.summary, samples: module.samples)
        case .gpu:
            MetricGlassRow(module: module, detail: module.summary, samples: module.samples)
        case .memory:
            MetricGlassRow(module: module, detail: module.summary)
        case .storage:
            MetricGlassRow(module: module, detail: module.summary)
        case .network:
            NetworkGlassRow(module: module)
        case .battery:
            BatteryGlassRow(module: module)
        }
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

private struct MetricGlassRow: View {
    let module: MonitorModule
    let detail: String
    var samples: [Double] = []

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.kind.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 70, alignment: .leading)

            Spacer(minLength: 8)

            if !samples.isEmpty {
                Sparkline(samples: samples, tint: tint)
                    .frame(width: 56, height: 18)
            }

            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14))
    }
}

private struct NetworkGlassRow: View {
    let module: MonitorModule

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text("网络: \(module.summary)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            MetricPill(systemImage: "arrow.up", text: value("上传"))
            MetricPill(systemImage: "arrow.down", text: value("下载"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14))
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

private struct BatteryGlassRow: View {
    let module: MonitorModule

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: batterySymbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 18)
                .symbolEffect(.variableColor.iterative, isActive: isCharging)

            Text(module.kind.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            MetricPill(systemImage: "battery.100percent", text: module.summary)
            MetricPill(systemImage: "bolt.fill", text: value("功耗"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14))
    }

    private var isCharging: Bool {
        value("状态") == "充电中"
    }

    private var batterySymbol: String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        switch module.value {
        case 76...100:
            return "battery.100percent"
        case 51..<76:
            return "battery.75percent"
        case 26..<51:
            return "battery.50percent"
        case 11..<26:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

private struct MetricPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: 72, alignment: .trailing)
    }
}

private struct Sparkline: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }

        return samples.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
            let y = size.height - CGFloat(min(100, max(0, value)) / 100) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

private extension MonitorKind {
    var paletteTint: Color {
        switch self {
        case .cpu:
            return Color(hex: 0xFF7A45)
        case .gpu:
            return Color(hex: 0xB57BFF)
        case .memory:
            return Color(hex: 0x4DA3FF)
        case .storage:
            return Color(hex: 0x32C896)
        case .network:
            return Color(hex: 0x5AC8FA)
        case .battery:
            return Color(hex: 0x34C759)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
