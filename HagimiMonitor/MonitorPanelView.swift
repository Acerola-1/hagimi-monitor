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
        let theme = MonitorPanelTheme(
            palette: MonitorPalette(
                preference: store.settings.colorSchemePreference,
                colorScheme: colorScheme
            )
        )

        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 6) {
                // Header: Live 脉冲点 + 时间
                header(theme: theme)

                ForEach(store.modules) { module in
                    row(for: module, theme: theme)
                        .glassEffectID("metric-\(module.kind.id)", in: glassNamespace)
                }

                #if DISPLAY_CONTROL
                if store.settings.displayModuleVisible {
                    DisplayControlsSection(settings: store.settings)
                        .glassEffectID("display-controls", in: glassNamespace)
                }
                #endif

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
            .frame(width: MonitorConstants.panelWidth)
            .background(.clear)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: MonitorConstants.panelCornerRadius, style: .continuous))
        .glassEffectID("monitor-panel", in: glassNamespace)
        .background(TransparentWindowBackground(colorSchemeOverride: store.settings.themePreference.colorScheme))
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
    private func row(for module: MonitorModule, theme: MonitorPanelTheme) -> some View {
        switch module.kind {
        case .cpu:
            MetricGlassRow(
                module: module,
                theme: theme,
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
                theme: theme,
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
                theme: theme,
                detail: module.summary,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .storage:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                details: module.metrics,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .network:
            NetworkGlassRow(
                module: module,
                theme: theme,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        case .battery:
            BatteryGlassRow(
                module: module,
                theme: theme,
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
        }
    }

    private func toggleExpansion(for kind: MonitorKind) {
        withAnimation(.smooth(duration: 0.18)) {
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
    let theme: MonitorPanelTheme
    let detail: String
    var samples: [Double] = []
    var details: [MonitorMetric] = []
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
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
                Group {
                    if let storageVolumes {
                        StorageVolumeDetailList(volumes: storageVolumes, kind: module.kind, tint: tint, theme: theme)
                    } else {
                        MetricDetailGrid(metrics: details, kind: module.kind, theme: theme)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
                .transition(.detailDisclosure)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpansion?()
        }
        .glassEffect(.regular.tint(theme.rowGlassTint(for: module.kind)), in: .rect(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
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

    private var storageVolumes: [StorageVolumeInfo]? {
        guard module.kind == .storage else {
            return nil
        }

        let externalVolumes = parseExternalVolumes(module.context)
        guard !externalVolumes.isEmpty else {
            return nil
        }

        return [systemVolumeInfo] + externalVolumes
    }

    private var systemVolumeInfo: StorageVolumeInfo {
        StorageVolumeInfo(
            id: "system",
            name: "系统盘",
            used: metricValue("已用"),
            free: metricValue("可用"),
            total: metricValue("总量"),
            percentage: Int(module.value.rounded()),
            isExternal: false
        )
    }

    private func metricValue(_ name: String) -> String {
        details.first { $0.name == name }?.value ?? "--"
    }
}

// MARK: - Detail Grid

private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let kind: MonitorKind
    let theme: MonitorPanelTheme

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, 28)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(metrics) { metric in
                    metricCell(metric, theme: theme)
                }
            }
            .padding(.leading, 28)
        }
    }

    private func metricCell(_ metric: MonitorMetric, theme: MonitorPanelTheme) -> some View {
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

private struct StorageVolumeDetailList: View {
    let volumes: [StorageVolumeInfo]
    let kind: MonitorKind
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 8) {
                ForEach(Array(volumes.enumerated()), id: \.element.id) { index, volume in
                    if index > 0 {
                        Rectangle()
                            .fill(theme.rowSeparator(for: kind).opacity(0.72))
                            .frame(height: 1)
                            .padding(.leading, 22)
                    }

                    StorageVolumeRow(volume: volume, kind: kind, tint: tint, theme: theme)
                }
            }
            .padding(.leading, 28)
        }
    }
}

private struct StorageVolumeRow: View {
    let volume: StorageVolumeInfo
    let kind: MonitorKind
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: volume.symbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(volume.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(volume.name)

                    Spacer(minLength: 8)

                    Text("\(volume.clampedPercentage)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(theme.badgeFill(for: kind))
                        }
                }

                ProgressMeter(value: Double(volume.clampedPercentage), tint: tint, theme: theme)
                    .frame(height: 3)

                HStack(spacing: 8) {
                    StorageVolumeStat(label: "已用", value: volume.used, theme: theme)
                    StorageVolumeStat(label: "可用", value: volume.free, theme: theme)
                    StorageVolumeStat(label: "总量", value: volume.total, theme: theme)
                }
            }
        }
    }
}

private struct StorageVolumeStat: View {
    let label: String
    let value: String
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.captionText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StorageVolumeInfo: Identifiable {
    let id: String
    let name: String
    let used: String
    let free: String
    let total: String
    let percentage: Int

    var isExternal: Bool

    var symbol: String {
        isExternal ? "externaldrive" : "internaldrive"
    }

    var clampedPercentage: Int {
        min(100, max(0, percentage))
    }
}

// MARK: - Network Row

private struct NetworkGlassRow: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
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

                MetricPill(systemImage: "arrow.up", text: value("上传"), theme: theme)
                MetricPill(systemImage: "arrow.down", text: value("下载"), theme: theme)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isExpanded {
                MetricDetailGrid(metrics: detailMetrics, kind: module.kind, theme: theme)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.detailDisclosure)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpansion?()
        }
        .glassEffect(.regular.tint(theme.rowGlassTint(for: module.kind)), in: .rect(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
    }

    private var detailMetrics: [MonitorMetric] {
        module.metrics.filter { $0.name == "IP 地址" }
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

// MARK: - Battery Row

private struct BatteryGlassRow: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    private var tint: Color {
        theme.moduleTint(for: module.kind)
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
                    MetricPill(systemImage: powerPillIcon, text: powerPillValue, theme: theme)
                } else {
                    MetricPill(systemImage: "powerplug", text: value("适配器"), theme: theme)
                    MetricPill(systemImage: "gauge.with.dots.needle.33percent", text: value("功耗"), theme: theme)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if hasBattery && isExpanded {
                MetricDetailGrid(metrics: detailMetrics, kind: module.kind, theme: theme)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.detailDisclosure)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasBattery {
                toggleExpansion?()
            }
        }
        .glassEffect(.regular.tint(theme.rowGlassTint(for: module.kind)), in: .rect(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
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

// MARK: - Transparent Window Background

private struct TransparentWindowBackground: NSViewRepresentable {
    let colorSchemeOverride: ColorScheme?

    func makeNSView(context: Context) -> NSView {
        let nsView = TransparentBackgroundView()
        nsView.apply(colorSchemeOverride: colorSchemeOverride)
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? TransparentBackgroundView else {
            return
        }

        nsView.apply(colorSchemeOverride: colorSchemeOverride)
    }
}

private final class TransparentBackgroundView: NSView {
    private weak var configuredWindow: NSWindow?
    private var appliedAppearanceName: NSAppearance.Name?
    private var currentColorSchemeOverride: ColorScheme?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else { return }
        configure(window)

        apply(colorSchemeOverride: currentColorSchemeOverride)
    }

    func apply(colorSchemeOverride: ColorScheme?) {
        currentColorSchemeOverride = colorSchemeOverride

        guard let window else { return }
        configure(window)

        guard let colorSchemeOverride else {
            guard appliedAppearanceName != nil else { return }
            appliedAppearanceName = nil
            window.appearance = nil
            window.contentView?.appearance = nil
            return
        }

        let appearanceName: NSAppearance.Name = colorSchemeOverride == .dark ? .darkAqua : .aqua
        guard appliedAppearanceName != appearanceName else { return }

        appliedAppearanceName = appearanceName
        let appearance = NSAppearance(named: appearanceName)
        window.appearance = appearance
        window.contentView?.appearance = appearance
    }

    private func configure(_ window: NSWindow) {
        guard configuredWindow !== window else { return }
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

private func parseExternalVolumes(_ context: String?) -> [StorageVolumeInfo] {
    guard let context, let data = context.data(using: .utf8) else {
        return []
    }

    if let payload = try? JSONDecoder().decode([ExternalVolumePayload].self, from: data) {
        return payload.enumerated().map { index, volume in
            StorageVolumeInfo(
                id: "external-\(index)-\(volume.name)",
                name: volume.name,
                used: volume.used,
                free: volume.free,
                total: volume.total,
                percentage: volume.percentage,
                isExternal: true
            )
        }
    }

    return parseLegacyExternalVolumes(context)
}

private struct ExternalVolumePayload: Decodable {
    let name: String
    let used: String
    let free: String
    let total: String
    let percentage: Int
}

private func parseLegacyExternalVolumes(_ context: String) -> [StorageVolumeInfo] {
    context.split(separator: ";").enumerated().compactMap { index, item in
        let parts = item.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 5 else {
            return nil
        }

        return StorageVolumeInfo(
            id: "external-\(index)-\(parts[0])",
            name: String(parts[0]),
            used: String(parts[1]),
            free: String(parts[2]),
            total: String(parts[3]),
            percentage: Int(parts[4]) ?? 0,
            isExternal: true
        )
    }
}

private struct MetricPill: View {
    let systemImage: String
    let text: String
    let theme: MonitorPanelTheme

    var body: some View {
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

struct MonitorPanelTheme {
    let palette: MonitorPalette

    var primaryText: Color {
        palette.primaryText
    }

    var valueText: Color {
        palette.valueText
    }

    var secondaryText: Color {
        palette.secondaryText
    }

    var captionText: Color {
        palette.captionText
    }

    var trackFill: Color {
        palette.trackFill
    }

    var liveDot: Color {
        palette.liveDot
    }

    func moduleTint(for kind: MonitorKind) -> Color {
        palette.moduleTint(for: kind)
    }

    func rowGlassTint(for kind: MonitorKind) -> Color {
        palette.rowGlassTint(for: kind)
    }

    func rowSeparator(for kind: MonitorKind) -> Color {
        palette.rowSeparator(for: kind)
    }

    func badgeFill(for kind: MonitorKind) -> Color {
        palette.badgeFill(for: kind)
    }
}

private extension AnyTransition {
    static var detailDisclosure: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity
        )
    }
}
