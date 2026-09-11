import SwiftUI

/// 设置页监测项目的实时预览卡:复刻面板行卡片形态——行头(模块图标 +
/// 标题 + 主值 + 曲线/进度条)与已勾选指标的明细网格,勾选变化即时反映,
/// 所见即面板展开后的样子。示例读数取自 MetricSampleCatalog;逐核环形图
/// 与功率流图直接复用面板组件,以静态示例数据渲染。
struct ModuleRowPreview: View {
    let kind: MonitorKind
    /// 已勾选指标(含压力模式下的标题替换)。
    let metrics: [MetricSwitch]
    let memoryPressureMode: Bool
    /// 功率流开关(仅电池模块消费,与面板 batteryShowPowerFlow 门控同源)。
    let showPowerFlow: Bool
    let palette: MonitorPalette
    /// 电池模块分页选择(拓扑/健康/排名/供电):由设置页持有,驱动预览分页与下方指标选项联动。
    @Binding var batteryTab: BatteryPageTab

    private var theme: MonitorPanelTheme {
        MonitorPanelTheme(palette: palette)
    }

    private var tint: Color {
        palette.moduleTint(for: kind)
    }

    /// 渲染入口指标:网络模块按面板 NetworkGlassRow 的固定顺序重排
    /// (信号/延迟同排,SSID 长值,地址类殿后),其余模块保持设置列表顺序。
    private var renderMetrics: [MetricSwitch] {
        guard kind == .network else { return metrics }
        let ordered = networkDetailMetricOrder.compactMap { name in
            metrics.first { $0.id == name }
        }
        let rest = metrics.filter { !networkDetailMetricOrder.contains($0.id) }
        return ordered + rest
    }

    /// 逐核展示条件:与面板 showCPUCoresDetail 同构——勾选 core-split 时
    /// 逐核环形图取代 core-split 格子(预览示例核数据恒可用)。
    private var showsCoreDetail: Bool {
        kind == .cpu && metrics.contains { $0.id == "core-split" }
    }

    /// 与面板 canExpand / 功率流挂载条件对齐:任一区块有内容才渲染展开区。
    private var hasDetail: Bool {
        // 电池分页预览恒展示(供电页始终有诊断内容),其余模块按明细是否有内容判定。
        guard kind != .battery else { return true }
        return !shortMetrics.isEmpty || thermalMetric != nil || !fullRowMetrics.isEmpty
            || showsCoreDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if hasDetail {
                if kind == .battery {
                    // 电池展开区与面板 BatteryGlassRow 同构:贯穿分隔线由
                    // PowerSectionHeader 自带,不再外挂。
                    batteryTabbedDetail
                        .padding(.horizontal, 10)
                        .padding(.bottom, 9)
                } else {
                    // 展开区骨架与面板 MetricDetailGrid 同构:贯穿分隔线与全宽顶格排版。
                    VStack(spacing: 7) {
                        Rectangle()
                            .fill(theme.rowSeparator(for: kind))
                            .frame(height: 1)

                        detailGrid
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                }
            }
        }
        .background(
            palette.rowGlassFill(for: kind)
                .clipShape(RoundedRectangle(cornerRadius: MonitorConstants.rowCornerRadius, style: .continuous))
        )
    }

    // MARK: 行头

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.callout.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text("\(kind.title):")
                .monitorPanelMetricLabelFont()
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)

            headerSummary

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .panelRowHeaderHeight()
    }

    private var headerSummary: some View {
        let sample = MetricSampleCatalog.summary(for: kind, memoryPressureMode: memoryPressureMode)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            ForEach(Array(sample.parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(part.tone == .calm ? palette.severityTint(for: .calm) : palette.valueText)
                    .lineLimit(1)
                if let unit = part.unit {
                    Text(unit)
                        .monitorPanelMonoFont(weight: .semibold)
                        .foregroundStyle(palette.valueText)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch kind {
        case .cpu, .gpu:
            SparklineChart(samples: MetricSampleCatalog.sparklineSamples, tint: tint)
                .frame(width: 56, height: 18)
        case .memory:
            // 压力模式行尾为压力历史曲线,使用率模式保持占比进度条,与面板行尾同构。
            if memoryPressureMode {
                SparklineChart(samples: MetricSampleCatalog.sparklineSamples, tint: tint)
                    .frame(width: 56, height: 18)
            } else {
                ProgressMeter(value: MetricSampleCatalog.memoryUsageFraction * 100, tint: tint, theme: theme)
                    .frame(width: 56, height: 3)
            }
        case .storage:
            ProgressMeter(value: MetricSampleCatalog.storageUsageFraction * 100, tint: tint, theme: theme)
                .frame(width: 56, height: 3)
        case .network, .battery, .fan, .bluetooth:
            EmptyView()
        }
    }

    // MARK: 明细网格

    /// 网格分组与面板 MetricDetailGrid 同构:逐核环形图在前,半行两列居中,
    /// 热压力合并行、整行指标沉底。整行归属查同一静态登记表,预览与面板
    /// 布局规则同源。
    private var shortMetrics: [MetricSwitch] {
        renderMetrics.filter { !isFullRow($0) && !isMergedThermalRow($0) && !(showsCoreDetail && $0.id == "core-split") }
    }

    private var fullRowMetrics: [MetricSwitch] {
        renderMetrics.filter { isFullRow($0) && !isMergedThermalRow($0) }
    }

    private var thermalMetric: MetricSwitch? {
        guard kind == .cpu, mergesThermalRow else { return nil }
        return renderMetrics.first { $0.id == "thermal-pressure" }
    }

    /// 温度读数仅直连版产出(SMC 在沙盒下不可读);沙盒版预览里热压力同样
    /// 回落为普通半行档位格,与面板 MetricDetailGrid 同源。
    private var mergesThermalRow: Bool {
        #if DISPLAY_CONTROL
        true
        #else
        false
        #endif
    }

    /// 整行查表用面板侧的有效指标名:压力模式下面板在进网格前把「压力」槽
    /// 改名为 usage(memoryMetrics(for:pressureMode:)),登记表按改名后的
    /// key 判定(memory.usage 与 memory.pressure 均走半行)。
    private func lookupName(_ metric: MetricSwitch) -> String {
        memoryPressureMode && metric.id == "pressure" ? "usage" : metric.id
    }

    private func isFullRow(_ metric: MetricSwitch) -> Bool {
        StaticMetricSizing.isFullRow(kind: kind, name: lookupName(metric))
    }

    private func isMergedThermalRow(_ metric: MetricSwitch) -> Bool {
        mergesThermalRow && kind == .cpu && metric.id == "thermal-pressure"
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: MetricGridMetrics.gridRowGap) {
            if showsCoreDetail {
                CPUCoresDetail(detail: MetricSampleCatalog.cpuCoreDetail, theme: theme)
            }

            if !shortMetrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: MetricGridMetrics.columnSpacing),
                              GridItem(.flexible())],
                    spacing: MetricGridMetrics.gridRowGap
                ) {
                    ForEach(shortMetrics) { metric in
                        MetricPreviewTile(
                            kind: kind,
                            id: metric.id,
                            title: metric.title,
                            memoryPressureMode: memoryPressureMode,
                            palette: palette
                        )
                    }
                }
            }

            if let thermal = thermalMetric {
                MetricPreviewTile(
                    kind: kind,
                    id: thermal.id,
                    title: thermal.title,
                    memoryPressureMode: memoryPressureMode,
                    palette: palette
                )
            }

            ForEach(fullRowMetrics) { metric in
                MetricPreviewTile(
                    kind: kind,
                    id: metric.id,
                    title: metric.title,
                    memoryPressureMode: memoryPressureMode,
                    palette: palette
                )
            }
        }
    }

    // MARK: 电池分页预览

    /// 与面板 BatteryGlassRow 同构的分页展开区:动态小标题 + 胶囊切换器,
    /// 三页各自渲染示例内容(拓扑=分项功耗网格+功率流图,健康=指标网格,
    /// 供电=固定诊断视图)。静态示例数据渲染,不向设置页引入常驻动画驱动。
    @ViewBuilder
    private var batteryTabbedDetail: some View {
        VStack(spacing: 8) {
            PowerSectionHeader(title: batteryTab.title, theme: theme) {
                PanelCapsulePicker(
                    selection: $batteryTab,
                    items: BatteryPageTab.previewCases,
                    icon: { $0.icon },
                    tooltip: { $0.title },
                    tint: tint,
                    theme: theme
                )
            }

            switch batteryTab {
            case .flow:
                if !flowMetrics.isEmpty {
                    previewGrid(flowMetrics)
                }
                if showPowerFlow {
                    PowerFlowDiagram(
                        module: MetricSampleCatalog.powerFlowModule,
                        theme: theme,
                        tint: tint,
                        animate: false
                    )
                }
            case .health:
                if !healthMetrics.isEmpty {
                    previewGrid(healthMetrics)
                }
            case .ranking:
                PowerAppRankingList(
                    shares: MetricSampleCatalog.appEnergyRankingShares,
                    theme: theme
                )
            case .supply:
                PowerSupplyDiagnosticsView(
                    module: MetricSampleCatalog.powerFlowModule,
                    theme: theme
                )
            }
        }
    }

    /// 拓扑页已勾分项功耗(整机/屏幕/GPU),随分页联动。
    private var flowMetrics: [MetricSwitch] {
        let names = BatteryPageTab.flow.metricNames
        return renderMetrics.filter { names.contains($0.id) }
    }

    /// 健康页已勾指标(健康度/循环/温度/电芯等),随分页联动。
    private var healthMetrics: [MetricSwitch] {
        let names = BatteryPageTab.health.metricNames
        return renderMetrics.filter { names.contains($0.id) }
    }

    /// 半行两列 + 整行沉底的示例网格(电池分页用;不含 CPU 逐核/热压力等网格外特殊形态)。
    @ViewBuilder
    private func previewGrid(_ gridMetrics: [MetricSwitch]) -> some View {
        let short = gridMetrics.filter { !isFullRow($0) }
        let full = gridMetrics.filter { isFullRow($0) }
        VStack(alignment: .leading, spacing: MetricGridMetrics.gridRowGap) {
            if !short.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: MetricGridMetrics.columnSpacing),
                              GridItem(.flexible())],
                    spacing: MetricGridMetrics.gridRowGap
                ) {
                    ForEach(short) { metric in
                        MetricPreviewTile(
                            kind: kind,
                            id: metric.id,
                            title: metric.title,
                            memoryPressureMode: memoryPressureMode,
                            palette: palette
                        )
                    }
                }
            }

            ForEach(full) { metric in
                MetricPreviewTile(
                    kind: kind,
                    id: metric.id,
                    title: metric.title,
                    memoryPressureMode: memoryPressureMode,
                    palette: palette
                )
            }
        }
    }
}
