import AppKit
import SwiftUI
import Charts

struct MonitorPanelView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @Namespace private var glassNamespace
    @State private var expandedKinds: Set<MonitorKind> = []

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 6) {
                // Header: Live 脉冲点 + 时间
                header(theme: theme)

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
                        SettingsWindowPresenter.open(openSettings)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 2)
            }
            .padding(10)
            .frame(width: 320)
            .background(.clear)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .glassEffectID("monitor-panel", in: glassNamespace)
        .background(TransparentWindowBackground())
    }

    private func header(theme: MonitorPanelTheme) -> some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.liveDot)
                    .frame(width: 5, height: 5)
                    .symbolEffect(.pulse, options: .repeating.speed(0.8))

                Text("SYSTEM · LIVE")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(theme.captionText)
            }

            Spacer()

            Text(timeString)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.captionText)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
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

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Metric Row

private struct MetricGlassRow: View {
    let module: MonitorModule
    let detail: String
    var samples: [Double] = []
    var details: [MonitorMetric] = []
    var isExpanded = false
    var toggleExpansion: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // 图标：保持原版紧凑 18px
                Image(systemName: module.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                // 标签 + 数值紧随其后（用户反馈：CPU: 37%）
                Text("\(module.kind.title):")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // 右侧：趋势图 / 进度条
                trailingView(theme: theme)
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
        .glassEffect(.regular.tint(theme.glassTint(for: tint)), in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func trailingView(theme: MonitorPanelTheme) -> some View {
        switch module.kind {
        case .cpu, .gpu:
            if !samples.isEmpty {
                SparklineChart(samples: samples, tint: tint)
                    .frame(width: 56, height: 18)
            }
        case .memory, .storage:
            ProgressMeter(value: module.value, tint: tint, theme: theme)
                .frame(width: 56, height: 3)
        case .network, .battery:
            EmptyView()
        }
    }
}

// MARK: - Detail Grid

private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.separator(for: tint))
                .frame(height: 1)
                .padding(.leading, 28)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(metrics) { metric in
                    HStack(spacing: 6) {
                        Text(metric.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.captionText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(metric.value)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
            .padding(.leading, 28)
        }
    }
}

// MARK: - Network Row

private struct NetworkGlassRow: View {
    let module: MonitorModule
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text("网络:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            Text(module.summary)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.valueText)
                .lineLimit(1)

            Spacer(minLength: 8)

            MetricPill(systemImage: "arrow.up", text: value("上传"))
            MetricPill(systemImage: "arrow.down", text: value("下载"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(theme.glassTint(for: tint)), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

// MARK: - Battery Row

private struct BatteryGlassRow: View {
    let module: MonitorModule
    var isExpanded = false
    var toggleExpansion: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        module.kind.paletteTint
    }

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: powerSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .symbolEffect(.variableColor.iterative, isActive: isCharging)

                Text("电源:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(module.summary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if hasBattery {
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
        .glassEffect(.regular.tint(theme.glassTint(for: tint)), in: .rect(cornerRadius: 14, style: .continuous))
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

// MARK: - Sparkline Chart (Swift Charts 渐变填充)

private struct SparklineChart: View {
    let samples: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(samples.suffix(24).enumerated()), id: \.offset) { i, v in
            AreaMark(
                x: .value("t", i),
                y: .value("v", v / 100)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                .linearGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("t", i),
                y: .value("v", v / 100)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(.init(lineWidth: 1.2, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .chartPlotStyle { $0.background(.clear) }
    }
}

// MARK: - Progress Meter (渐变进度条)

private struct ProgressMeter: View {
    let value: Double
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.trackFill)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(1, max(0, value / 100)))
            }
        }
    }
}

// MARK: - Transparent Window Background

private struct TransparentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentBackgroundView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class TransparentBackgroundView: NSView {
    private weak var configuredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window, configuredWindow !== window else { return }

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

// MARK: - Metric Pill

private struct MetricPill: View {
    let systemImage: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MonitorPanelTheme(colorScheme: colorScheme)

        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .frame(width: 72, alignment: .trailing)
    }
}

// MARK: - Theme

private struct MonitorPanelTheme {
    let colorScheme: ColorScheme

    var isDark: Bool {
        colorScheme == .dark
    }

    var primaryText: Color {
        isDark ? Color.white.opacity(0.94) : Color.primary
    }

    var valueText: Color {
        isDark ? Color.white.opacity(0.82) : Color.secondary
    }

    var secondaryText: Color {
        isDark ? Color.white.opacity(0.72) : Color.secondary
    }

    var captionText: Color {
        isDark ? Color.white.opacity(0.52) : Color.black.opacity(0.36)
    }

    func glassTint(for tint: Color) -> Color {
        tint.opacity(isDark ? 0.16 : 0.08)
    }

    func separator(for tint: Color) -> Color {
        tint.opacity(isDark ? 0.28 : 0.18)
    }

    var trackFill: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var liveDot: Color {
        Color(red: 0.30, green: 0.85, blue: 0.50)
    }
}

// MARK: - Color Extensions

private extension MonitorKind {
    var paletteTint: Color {
        switch self {
        case .cpu:
            return Color(hex: 0xFF6B4A)
        case .gpu:
            return Color(hex: 0xA855F7)
        case .memory:
            return Color(hex: 0x38BDF8)
        case .storage:
            return Color(hex: 0x34D399)
        case .network:
            return Color(hex: 0xFBBF24)
        case .battery:
            return Color(hex: 0x4ADE80)
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
