import AppKit
import SwiftUI

struct MonitorPanelView: View {
    @ObservedObject var store: MonitorStore
    @Namespace private var glassNamespace
    @State private var expandedKinds: Set<MonitorKind> = []

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
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .glassEffectID("monitor-panel", in: glassNamespace)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .background(TransparentWindowBackground())
    }

    @ViewBuilder
    private func row(for module: MonitorModule) -> some View {
        switch module.kind {
        case .cpu:
            MetricGlassRow(
                module: module,
                detail: module.summary,
                samples: module.samples,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .gpu:
            MetricGlassRow(
                module: module,
                detail: module.summary,
                samples: module.samples,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .memory:
            MetricGlassRow(
                module: module,
                detail: module.summary,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .storage:
            MetricGlassRow(
                module: module,
                detail: module.summary,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .network:
            NetworkGlassRow(module: module)
        case .battery:
            BatteryGlassRow(
                module: module,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        }
    }

    private func toggleExpansion(for kind: MonitorKind) {
        withAnimation(.snappy(duration: 0.22, extraBounce: 0.03)) {
            if expandedKinds.contains(kind) {
                expandedKinds.remove(kind)
            } else {
                expandedKinds.insert(kind)
            }
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
    var details: [MonitorMetric] = []
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        VStack(spacing: 0) {
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

            if isExpanded, !details.isEmpty {
                MetricDetailGrid(metrics: details, tint: tint)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpansion?()
        }
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }
}

private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let tint: Color

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(tint.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, 28)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(metrics) { metric in
                    HStack(spacing: 6) {
                        Text(metric.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(metric.value)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
            .padding(.leading, 28)
        }
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
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

private struct BatteryGlassRow: View {
    let module: MonitorModule
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: powerSymbol)
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

                if hasBattery {
                    MetricPill(systemImage: "battery.100percent", text: module.summary)
                    MetricPill(systemImage: powerPillIcon, text: powerPillValue)
                } else {
                    MetricPill(systemImage: "powerplug", text: value("适配器"))
                    MetricPill(systemImage: "gauge.with.dots.needle.33percent", text: value("功耗"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if hasBattery && isExpanded {
                MetricDetailGrid(metrics: detailMetrics, tint: tint)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasBattery {
                toggleExpansion?()
            }
        }
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private var hasBattery: Bool {
        value("类型") == "电池"
    }

    private var isCharging: Bool {
        value("状态") == "充电中"
    }

    private var powerSymbol: String {
        guard hasBattery else {
            return "powerplug"
        }
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

    private var powerPillIcon: String {
        return "gauge.with.dots.needle.33percent"
    }

    private var powerPillValue: String {
        return value("功耗")
    }

    private var detailMetrics: [MonitorMetric] {
        let names = isConnectedToPower
            ? ["充电功率", "健康度", "循环数", "温度"]
            : ["健康度", "循环数", "温度"]

        return names.compactMap { name in
            guard let metric = module.metrics.first(where: { $0.name == name }) else {
                return nil
            }
            return metric
        }
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }

    private var isConnectedToPower: Bool {
        value("状态") != "电池供电"
    }
}

private struct TransparentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentBackgroundView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}

private final class TransparentBackgroundView: NSView {
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window, configuredWindow !== window else {
            return
        }

        configuredWindow = window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        var parent = superview
        while let current = parent {
            current.wantsLayer = true
            current.layer?.backgroundColor = NSColor.clear.cgColor
            parent = current.superview
        }
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
