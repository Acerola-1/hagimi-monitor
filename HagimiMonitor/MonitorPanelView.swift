import AppKit
import SwiftUI

private let panelTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

struct MonitorPanelView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings
    @Namespace private var glassNamespace
    @State private var expandedKinds: Set<MonitorKind> = []

    var body: some View {
        // theme 按 (preference, colorScheme) 缓存,避免每秒采样刷新时重建整棵 Color 树。
        // 缓存返回稳定实例,Row 的 Equatable 比较可据此跳过未变化行。
        let theme = ThemeCache.theme(
            preference: store.settings.colorSchemePreference,
            scheme: colorScheme
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
                        Label(String(localized: "panel.activity-monitor"), systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                    Button {
                        SettingsWindowPresenter.open(openSettings)
                    } label: {
                        Label(String(localized: "panel.settings"), systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 2)
            }
            .padding(10)
            .frame(
                minWidth: MonitorConstants.panelMinWidth,
                idealWidth: MonitorConstants.panelIdealWidth,
                maxWidth: MonitorConstants.panelMaxWidth
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(panelBackgroundColor)
        }
        .containerBackground(.clear, for: .window)
        .background(TransparentWindowBackground(colorSchemeOverride: store.settings.themePreference.colorScheme))
    }

    private var panelBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.45)
    }

    private func header(theme: MonitorPanelTheme) -> some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.liveDot(for: store.haloRingLoadLevel))
                    .frame(width: 5, height: 5)
                    .symbolEffect(.pulse, options: .repeating.speed(0.8))
                    .animation(.easeInOut(duration: 0.6), value: store.haloRingLoadLevel)

                Text("SYSTEM · LIVE")
                    .monitorPanelLabelFont(tracking: 1.1)
                    .foregroundStyle(theme.captionText)
            }

            Spacer()

            Text(timeString)
                .monitorPanelMonoFont(.caption2, weight: .medium)
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
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .gpu:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                samples: module.samples,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .memory:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind),
                topMemoryProcesses: store.topMemoryProcesses,
                showMemoryProcesses: store.settings.showMemoryProcesses
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .storage:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .network:
            NetworkGlassRow(
                module: module,
                theme: theme,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .battery:
            BatteryGlassRow(
                module: module,
                theme: theme,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind)
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        }
    }

    private func enabledMetrics(for module: MonitorModule) -> [MonitorMetric] {
        let enabledIds = store.settings.enabledMetrics[module.kind] ?? defaultMetricIds(for: module.kind)
        return module.metrics.filter { enabledIds.contains($0.name) }
    }

    private func defaultMetricIds(for kind: MonitorKind) -> Set<String> {
        Set(kind.availableMetrics.filter { $0.isDefault }.map { $0.id })
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
        panelTimeFormatter.string(from: Date())
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Metric Row

private struct MetricGlassRow: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let detail: String
    var samples: [Double] = []
    var details: [MonitorMetric] = []
    var isExpanded = false
    var topMemoryProcesses: [TopMemoryProcess] = []
    var showMemoryProcesses = true
    var toggleExpansion: (() -> Void)?

    // theme 完全由 (preference, colorScheme) 决定(见 ThemeCache),故只比这两个键字段;
    // 闭包不参与相等判定。未变化的行 == 成立时 SwiftUI 跳过整行重绘。
    static func == (lhs: MetricGlassRow, rhs: MetricGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.detail == rhs.detail
            && lhs.samples == rhs.samples
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.topMemoryProcesses == rhs.topMemoryProcesses
            && lhs.showMemoryProcesses == rhs.showMemoryProcesses
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: module.kind.symbol)
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                Text("\(module.kind.title):")
                    .monitorPanelMetricLabelFont()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailingView(theme: theme)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if isExpanded, !details.isEmpty {
                Group {
                    if let storageVolumes {
                        StorageVolumeDetailList(volumes: storageVolumes, kind: module.kind, tint: tint, theme: theme)
                    } else {
                        VStack(spacing: 9) {
                            MetricDetailGrid(metrics: details, kind: module.kind, theme: theme)
                            if module.kind == .memory, showMemoryProcesses, !topMemoryProcesses.isEmpty {
                                MemoryProcessList(processes: topMemoryProcesses, theme: theme)
                            }
                        }
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
            name: String(localized: "panel.system-volume"),
            used: metricValue("used"),
            free: metricValue("free"),
            total: metricValue("total"),
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

    /// 需要占满整行的长值字段(IP、启动时间等):它们的 value 太长,
    /// 塞进两列会撑破列宽或触发不可控换行,故显式整行、排到网格末尾。
    private static let fullRowMetricIDs: Set<String> = [
        "ip-address", "public-ip", "uptime", "adapter"
    ]

    private var shortMetrics: [MonitorMetric] {
        metrics.filter { !Self.fullRowMetricIDs.contains($0.name) }
    }

    private var fullRowMetrics: [MonitorMetric] {
        metrics.filter { Self.fullRowMetricIDs.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, 28)

            content
                .padding(.leading, 28)
        }
    }

    // 固定两列 Grid:每列 label 左对齐、value 右对齐到列右边界,
    // 短值因此落在两条稳定竖直轴上,眼睛可顺列下扫;长值统一在下方整行区。
    private var content: some View {
        VStack(alignment: .leading, spacing: MetricGridMetrics.rowSpacing) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: MetricGridMetrics.rowSpacing) {
                ForEach(Array(rowPairs.enumerated()), id: \.offset) { _, pair in
                    GridRow {
                        metricCell(pair.0)
                        if let right = pair.1 {
                            metricCell(right)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }

            ForEach(fullRowMetrics) { metric in
                metricCell(metric)
            }
        }
    }

    /// 把短值两两配对成 Grid 行;奇数个时最后一项右槽为 nil。
    private var rowPairs: [(MonitorMetric, MonitorMetric?)] {
        let items = shortMetrics
        var pairs: [(MonitorMetric, MonitorMetric?)] = []
        var index = 0
        while index < items.count {
            let left = items[index]
            let right = index + 1 < items.count ? items[index + 1] : nil
            pairs.append((left, right))
            index += 2
        }
        return pairs
    }

    private func metricCell(_ metric: MonitorMetric) -> some View {
        let labelText = localizedMetricName(kind: kind, id: metric.name)
        let valueText = localizedMetricValue(kind: kind, metric: metric)

        return HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
            Text(labelText)
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)

            Text(valueText)
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .layoutPriority(2)
                .help(valueText)
                .contentShape(Rectangle())
                .onTapGesture {
                    copyToPasteboard(metric.value)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func localizedMetricName(kind: MonitorKind, id: String) -> String {
    let key = "metric.\(kind.rawValue).\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

private func localizedMetricValue(kind: MonitorKind, metric: MonitorMetric) -> String {
    switch (kind, metric.name) {
    case (.memory, "pressure"):
        return localizedMemoryPressure(metric.value)
    default:
        return metric.value
    }
}

private func localizedMemoryPressure(_ id: String) -> String {
    let key = "memory-pressure.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
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
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(volume.name)
                        .monitorPanelCaptionFont(.footnote, weight: .semibold)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(volume.name)

                    Spacer(minLength: 8)

                    Text("\(volume.clampedPercentage)%")
                        .monitorPanelMonoFont(.footnote, weight: .semibold)
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
                    StorageVolumeStat(label: String(localized: "metric.storage.used"), value: volume.used, theme: theme)
                    StorageVolumeStat(label: String(localized: "metric.storage.free"), value: volume.free, theme: theme)
                    StorageVolumeStat(label: String(localized: "metric.storage.total"), value: volume.total, theme: theme)
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
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)

            Text(value)
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.78)
                .help(value)
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

private struct NetworkGlassRow: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var details: [MonitorMetric] = []
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    static func == (lhs: NetworkGlassRow, rhs: NetworkGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)

                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(String(localized: "kind.network") + ":")
                            .monitorPanelMetricLabelFont()
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Text(localizedNetworkInterface(module.summary))
                            .monitorPanelMonoFont(weight: .semibold)
                            .foregroundStyle(theme.valueText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                    Spacer(minLength: 2)

                    HStack(spacing: 6) {
                        NetworkRatePill(systemImage: "arrow.up", text: value("upload"), theme: theme)
                        NetworkRatePill(systemImage: "arrow.down", text: value("download"), theme: theme)
                    }
                    .layoutPriority(1)
                }
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
        let names = ["ip-address", "public-ip"]
        let enabledNames = Set(details.map(\.name))
        return names.compactMap { name in
            guard enabledNames.contains(name) else { return nil }
            return module.metrics.first(where: { $0.name == name })
        }
    }

    private func value(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

// MARK: - Battery Row

private struct BatteryGlassRow: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var details: [MonitorMetric] = []
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    static func == (lhs: BatteryGlassRow, rhs: BatteryGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: powerSymbol)
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                    .symbolEffect(.variableColor.iterative, isActive: isCharging)

                Text(String(localized: "kind.battery") + ":")
                    .monitorPanelMetricLabelFont()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(2)

                Text(summaryText)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(3)

                Spacer(minLength: 4)

                if hasBattery {
                    MetricPill(systemImage: powerPillIcon, text: powerPillValue, theme: theme)
                        .layoutPriority(0)
                } else {
                    MetricPill(systemImage: "gauge.with.dots.needle.33percent", text: value("power"), theme: theme)
                        .layoutPriority(0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if canExpand && isExpanded {
                MetricDetailGrid(metrics: detailMetrics, kind: module.kind, theme: theme)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.detailDisclosure)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canExpand {
                toggleExpansion?()
            }
        }
        .glassEffect(.regular.tint(theme.rowGlassTint(for: module.kind)), in: .rect(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
    }

    private var hasBattery: Bool {
        rawValue("type") == "battery"
    }

    private var isCharging: Bool {
        rawValue("status") == "charging"
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
        return value("power")
    }

    private var summaryText: String {
        if hasBattery {
            localizedBatteryState(module.summary)
        } else {
            value("adapter")
        }
    }

    private var detailMetrics: [MonitorMetric] {
        let names = isConnectedToPower
            ? ["charging-power", "health", "cycle-count", "temperature"]
            : ["health", "cycle-count", "temperature"]

        let enabledNames = Set(details.map(\.name))

        return names.compactMap { name in
            guard enabledNames.contains(name) else { return nil }
            return module.metrics.first(where: { $0.name == name })
        }
    }

    private var canExpand: Bool {
        !detailMetrics.isEmpty
    }

    private func value(_ name: String) -> String {
        let raw = rawValue(name)
        switch name {
        case "type", "status":
            return localizedBatteryState(raw)
        default:
            return raw
        }
    }

    private func rawValue(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }

    private var isConnectedToPower: Bool {
        rawValue("status") != "on-battery"
    }
}

private func localizedBatteryState(_ id: String) -> String {
    let key = "battery-state.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

private func localizedNetworkInterface(_ summary: String) -> String {
    let key = "network-interface.\(summary)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? summary : localized
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
        window.contentView?.superview?.wantsLayer = true
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor

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
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .monospacedDigit()
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            // Compact status pill: fixed width keeps battery row controls from shifting during live updates.
            .frame(width: 72, alignment: .trailing)
    }
}

private struct NetworkRatePill: View {
    let systemImage: String
    let text: String
    let theme: MonitorPanelTheme

    private var parts: (value: String, unit: String) {
        guard let split = text.lastIndex(of: " ") else {
            return (text, "")
        }

        return (
            String(text[..<split]),
            String(text[text.index(after: split)...])
        )
    }

    var body: some View {
        let parts = parts

        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .frame(width: 10)

            Text(parts.value)
                .monitorPanelMonoFont(.caption2, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(minWidth: 8, maxWidth: 30, alignment: .trailing)

            Text(parts.unit)
                .monitorPanelMonoFont(.caption2, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 26, alignment: .leading)
        }
        .foregroundStyle(theme.secondaryText)
        .fixedSize(horizontal: true, vertical: false)
        // Compact network rate pill: bounded width preserves room for both upload and download rates.
        .frame(minWidth: 48, maxWidth: 68, alignment: .trailing)
    }
}

extension Text {
    func monitorPanelLabelFont(tracking: CGFloat) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .kerning(tracking)
    }

    func monitorPanelMetricLabelFont() -> some View {
        self
            .font(.callout.weight(.medium))
            .kerning(0.15)
    }

    func monitorPanelCaptionFont(_ style: Font.TextStyle = .caption2, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(style).weight(weight))
            .kerning(0.1)
    }

    func monitorPanelMonoFont(_ style: Font.TextStyle = .callout, weight: Font.Weight = .semibold) -> some View {
        self
            .font(.system(style, design: .monospaced).weight(weight))
            .monospacedDigit()
    }

    func monitorPanelRoundedFont(_ style: Font.TextStyle = .callout, weight: Font.Weight = .semibold) -> some View {
        self
            .font(.system(style, design: .rounded).weight(weight))
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

    func liveDot(for loadLevel: MenuBarComputeLoadLevel) -> Color {
        palette.liveDot(for: loadLevel)
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

/// 按 `(偏好, 外观)` 缓存 MonitorPanelTheme。preference 只有 balanced/vibrant 两个值,
/// colorScheme 只有 light/dark,最多 4 个组合,命中率近乎 100%,避免每帧重建整棵
/// Color 树。访问仅发生在 MainActor(body 求值),无需加锁。
@MainActor
private enum ThemeCache {
    private struct Key: Hashable {
        let preference: MonitorColorSchemePreference
        let scheme: ColorScheme
    }

    private static var cache: [Key: MonitorPanelTheme] = [:]

    static func theme(
        preference: MonitorColorSchemePreference,
        scheme: ColorScheme
    ) -> MonitorPanelTheme {
        let key = Key(preference: preference, scheme: scheme)
        if let cached = cache[key] {
            return cached
        }
        let theme = MonitorPanelTheme(palette: MonitorPalette(preference: preference, colorScheme: scheme))
        cache[key] = theme
        return theme
    }
}

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

// MARK: - Top Memory Processes

private struct MemoryProcessList: View {
    let processes: [TopMemoryProcess]
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .memory))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(Array(processes.enumerated()), id: \.element.id) { i, proc in
                    HStack(spacing: 6) {
                        Text("\(i + 1).")
                            .monitorPanelMonoFont(.caption2, weight: .medium)
                            .foregroundStyle(theme.captionText)
                            .frame(width: 16, alignment: .trailing)

                        Text(proc.name)
                            .monitorPanelCaptionFont(.footnote)
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        Text(ByteCountFormatter.string(fromByteCount: Int64(proc.memoryUsage), countStyle: .memory))
                            .monitorPanelMonoFont(.caption2, weight: .medium)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
            }
            .padding(.leading, 28)
        }
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
