import AppKit
import SwiftUI

/// 主体 ScrollView 两端是否还有被裁内容,驱动上下渐隐遮罩。
private struct BodyScrollEdges: Equatable {
    let top: Bool
    let bottom: Bool
    /// 内容自然高度(不含视口),用于判定内容是否真实超高。
    let contentHeight: CGFloat
}

struct MonitorPanelView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var quickPanelPresentation: QuickPanelPresentation
    private let showsQuickPanelControls: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fluidOpenSettings) private var fluidOpenSettings
    /// 内容总高度上限(由 FluidPanelController 注入,钉住面板等其他宿主为 .infinity)。
    /// 据此封顶主体 ScrollView,使 header 固定、仅主体滚动。
    @Environment(\.panelMaxContentHeight) private var maxContentHeight
    @Namespace private var glassNamespace
    @State private var expandedKinds: Set<MonitorKind> = []
    /// header 实测高度,用于从内容总高上限换算主体 ScrollView 的 maxHeight。
    @State private var headerHeight: CGFloat = 0
    /// 主体是否已向上滚动:控制顶部渐隐遮罩。仅滚动后启用,避免未滚动时
    /// 误伤第一张卡片的顶边。
    @State private var isBodyScrolled = false
    /// 主体下方是否还有未滚到的内容:控制底部渐隐遮罩。滚到底/未溢出时
    /// 关闭,保证底部按钮清晰不被误伤。
    @State private var bodyHasMoreBelow = false
    /// header 小猫客串彩蛋（致敬 RunCat）。仅菜单栏下拉面板参与，钉住面板不触发。
    @StateObject private var cameoModel = HeaderCatCameoModel()
    /// 本面板实例私有的展开动画驱动器:与各展开区的相位 key 一一对应,
    /// 经 environmentObject 注入子树;每个面板(菜单栏/钉住)各自持有,
    /// 展开动画互不牵动。
    @StateObject private var panelExpansion = PanelExpansionDriver()
    /// 窗口层注入的贴合回调:driver 在 toggle 时把目标高度与是否动画下发给窗口层。
    /// 预览/无窗口宿主为 nil。
    @Environment(\.panelWindowResizeHandler) private var windowResizeHandler

    init(store: MonitorStore, quickPanelPresentation: QuickPanelPresentation? = nil) {
        self.store = store
        let presentation = quickPanelPresentation ?? QuickPanelPresentation()
        _quickPanelPresentation = ObservedObject(wrappedValue: presentation)
        showsQuickPanelControls = quickPanelPresentation != nil
    }

    /// 主体 ScrollView 的高度上限:内容总高上限减去 header、顶/底内边距(8/6)
    /// 与 header—主体间距(4),另留 4pt 布局缓冲。header 首帧尚未测定时偏大,
    /// 由窗口层 clamp 兜底。无上限(钉住面板等宿主)时返 nil,不施加约束。
    private var scrollBodyMaxHeight: CGFloat? {
        guard maxContentHeight != .infinity else { return nil }
        return max(120, maxContentHeight - headerHeight - 22)
    }

    /// 主体封顶时内容总高度的实际钳制值(header + 内边距/间距 + 主体上限),
    /// 与 body 的布局公式一致,上报驱动器用于识别「实测高度已封顶」。
    /// 无上限(钉住面板等宿主)时为无穷。
    private var effectiveContentHeightCap: CGFloat {
        guard let scrollBodyMaxHeight else { return .infinity }
        return scrollBodyMaxHeight + headerHeight + 22
    }

    var body: some View {
        // theme 按 (preference, colorScheme) 缓存,避免每秒采样刷新时重建整棵 Color 树。
        // 缓存返回稳定实例,Row 的 Equatable 比较可据此跳过未变化行。
        let theme = ThemeCache.theme(
            preference: store.settings.colorSchemePreference,
            scheme: colorScheme
        )

        CompatibleGlassContainer(spacing: 8) {
            VStack(spacing: 4) {
                header(theme: theme)
                    .transaction { $0.animation = nil }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { headerHeight = geometry.size.height }
                                .onChange(of: geometry.size.height) { _, newValue in
                                    headerHeight = newValue
                                }
                        }
                    )

                // 主体(模块列表+底部按钮)包在 ScrollView 里:未超高时 ScrollView
                // 理想高度=内容高度、不可滚动,行为与无 ScrollView 时一致;
                // 触封顶时仅主体滚动,header 固定不动。
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(store.modules) { module in
                                compactRow(for: module, theme: theme)
                                    .id(module.kind)
                                    .compatibleGlassEffectID("metric-\(module.kind.id)", in: glassNamespace)
                            }

                            // 显示器信息区(B4):沙盒版没有控制区,独立成行展示;
                            // Direct 版信息并入 DisplayControlsSection 展开区,
                            // 避免出现两行「显示器」重复。
                            #if !DISPLAY_CONTROL
                            if store.settings.displayModuleVisible {
                                DisplayInfoSection(
                                    theme: theme,
                                    animate: { key, toFull, animated in
                                        store.beginExpansionAnimation()
                                        if animated {
                                            panelExpansion.animate(key, toFull ? 1 : 0)
                                        } else {
                                            panelExpansion.setInstantly(key, toFull ? 1 : 0)
                                        }
                                    }
                                )
                                .compatibleGlassEffectID("display-info", in: glassNamespace)
                            }
                            #endif

                            #if DISPLAY_CONTROL
                            if store.settings.displayModuleVisible {
                                DisplayControlsSection(
                                    settings: store.settings,
                                    isPanelVisible: store.isPanelVisible,
                                    animate: { key, toFull, animated in
                                        store.beginExpansionAnimation()
                                        if animated {
                                            panelExpansion.animate(key, toFull ? 1 : 0)
                                        } else {
                                            panelExpansion.setInstantly(key, toFull ? 1 : 0)
                                        }
                                    }
                                )
                                .compatibleGlassEffectID("display-controls", in: glassNamespace)
                            }
                            #endif

                            // 底部三按钮与行卡片同规格:同内边距/同字体/同间距,
                            // 高度与行间留白都与模块行一致;文案用短形式避免折行。
                            HStack(spacing: 6) {
                                Button {
                                    openActivityMonitor()
                                } label: {
                                    Label(String(localized: "panel.monitor"), systemImage: "waveform.path.ecg")
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                }
                                .compatibleButtonStyle()

                                // 快捷功能入口:激活角标与浮层打开态高亮由子视图
                                // 自行观察 store,开关变化不牵动整块面板重绘。
                                QuickToolsEntryButton(theme: theme)

                                Button {
                                    fluidOpenSettings()
                                } label: {
                                    Label(String(localized: "panel.settings"), systemImage: "gearshape")
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                }
                                .compatibleButtonStyle()
                            }
                            .font(.callout.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // 隐藏滚动条:展开/收起时内容高度频繁变化,滚动条会随之闪现,观感差;
                    // 面板内容有限且封顶场景少见,不依赖滚动条提示位置。
                    .scrollIndicators(.never)
                    .onScrollGeometryChange(for: BodyScrollEdges.self) { geometry in
                        BodyScrollEdges(
                            top: geometry.contentOffset.y > 1,
                            bottom: geometry.contentOffset.y + geometry.containerSize.height
                                < geometry.contentSize.height - 1,
                            contentHeight: geometry.contentSize.height
                        )
                    } action: { _, edges in
                        isBodyScrolled = edges.top
                        // 底部渐隐只在内容真实超高时显示:展开动画期间内容高度补间
                        // 领先视口补间约一帧,contentSize 会瞬时大于 containerSize,
                        // 直接据此判断会在「未超高、无需滚动」时也闪现一次底部渐隐。
                        // 用稳定的封顶高度(动画期间不变)作门控,未超高时恒不触发。
                        let cappedHeight = scrollBodyMaxHeight ?? .infinity
                        bodyHasMoreBelow = edges.contentHeight > cappedHeight && edges.bottom
                    }
                    // 上下渐隐遮罩:对应边缘外还有内容时,圆角卡片滑到边界不再被直线
                    // 硬切,而是在 12pt 内渐隐消失;贴边/未溢出时渐隐段高度为 0,
                    // 首尾内容(第一张卡片/底部按钮)不受影响。
                    .mask(
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: isBodyScrolled ? 12 : 0)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: bodyHasMoreBelow ? 12 : 0)
                        }
                        .animation(.easeInOut(duration: 0.15), value: isBodyScrolled)
                        .animation(.easeInOut(duration: 0.15), value: bodyHasMoreBelow)
                    )
                    .frame(maxHeight: scrollBodyMaxHeight)
                    // 展开新行时滚动揭示:面板高度封顶后 ScrollView 才可滚(未溢出时
                    // scrollTo 无效果),把展开行底缘对齐视口底缘,保证新展开的明细
                    // (如风扇控制区)不被截在视口外看不见。
                    .onChange(of: expandedKinds) { oldSet, newSet in
                        guard let added = newSet.subtracting(oldSet).first else { return }
                        withAnimation(.easeInOut(duration: MonitorConstants.panelExpansionDuration)) {
                            proxy.scrollTo(added, anchor: .bottom)
                        }
                    }
                }
            }
            // 顶部留白收紧至 8pt 与 header—主体间距 4pt 配合压缩首屏空白;
            // 底边留白与行间节奏(6pt)对齐,侧边保持 10pt。
            .padding(.top, 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(
                minWidth: MonitorConstants.panelMinWidth,
                idealWidth: MonitorConstants.panelIdealWidth,
                maxWidth: MonitorConstants.panelMaxWidth
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(panelBackgroundColor)
        }
        .compatibleContainerBackground()
        .overlay {
            // 点一下后弹出的 RunCat 致谢卡片(面板内 overlay,避免系统 sheet 抢焦点关面板)。
            if cameoModel.showThanks {
                CatThanksCard(onClose: { cameoModel.showThanks = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameoModel.showThanks)
        .background(TransparentWindowBackground(colorSchemeOverride: store.settings.themePreference.colorScheme))
        .onChange(of: store.isPanelVisible) { _, visible in
            // 面板隐藏后重置为各模块的「默认展开」设置:不可见期间直接赋值(无动画),
            // 窗口在后台瞬时贴合新高度,下次呼出即已是设定的初始状态、无二次跳变。
            if !visible {
                applyDefaultExpansion()
            }
            // 面板由隐藏→可见:菜单栏面板摧骰子决定是否客串;隐藏时清理。
            guard !showsQuickPanelControls else { return }
            if visible {
                cameoModel.panelDidAppear()
                // 调试自动测试:可见后 0.8s 自动全量展开(走真实 setExpansion 动画路径),
                // 供 sizeDidChange 日志观察展开期间的尺寸上报行为。
                if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guard store.isPanelVisible else { return }
                        setExpansion { expandedKinds = Set(visibleKinds) }
                    }
                }
            } else {
                cameoModel.panelDidDisappear()
            }
        }
        .onChange(of: store.settings.defaultExpandedKinds) { _, _ in
            // 设置变更立即生效:面板隐藏则为下次呼出预置状态;
            // 钉住面板开着改设置时可见,直接预览展开/收起效果。
            applyDefaultExpansion()
        }
        .onAppear {
            // 桥接窗口层注入的贴合回调:driver toggle 时把目标高度与是否动画
            // 下发给窗口层,animated 时由 CoreAnimation 补间窗口 frame。
            panelExpansion.onWindowResize = windowResizeHandler
            // 视图只创建一次(常驻 NSPanel),此处覆盖首次呼出前的默认展开。
            applyDefaultExpansion()
            // 上报当前需进程采样的集合(展开的行):面板重开时 @State 可能保留上次选项,
            // 而 store 已在上次关闭时清空该来源,此处重新同步以触发对应采样。
            reportActiveProcessKinds()
        }
        .onChange(of: expandedKinds) { _, _ in
            reportActiveProcessKinds()
        }
        // 实测内容总高度上报驱动器:非动画期间据此反推收起态基线高度,
        // 动画开始时由 targetContentHeight 叠加目标相位高度预测窗口目标尺寸。
        // 同时上报总高度上限:主体 ScrollView 封顶时实测高度被钳在上限,
        // 驱动器据此跳过基线校准(反推等式在封顶期失真,会解出错误基线)。
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        panelExpansion.reportContentHeightCap(effectiveContentHeightCap)
                        panelExpansion.reportMeasuredContentHeight(geometry.size.height)
                    }
                    .onChange(of: geometry.size.height) { _, newValue in
                        panelExpansion.reportContentHeightCap(effectiveContentHeightCap)
                        panelExpansion.reportMeasuredContentHeight(newValue)
                    }
            }
        )
        .onChange(of: maxContentHeight) { _, _ in
            // 上限变化(换屏/Dock 变化)独立刷新,尺寸未必随之变化。
            panelExpansion.reportContentHeightCap(effectiveContentHeightCap)
        }
        // 展开驱动器注入整棵面板子树:CollapsibleDetail 按各自 key 自读相位。
        // 驱动器为面板实例私有(@StateObject),钉住面板与菜单栏面板并存时
        // 展开动画互不牵动。
        .environmentObject(panelExpansion)
    }

    /// 需进程采样的类目集 = 行内展开的模块。
    private func reportActiveProcessKinds() {
        store.updateExpandedKinds(expandedKinds, for: panelSource)
    }

    /// 本面板对应的进程采样来源。带快捷面板控件的是钉住面板,否则是菜单栏面板。
    private var panelSource: PanelKind {
        showsQuickPanelControls ? .pinned : .menuBar
    }

    private var panelBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.45)
    }

    private func header(theme: MonitorPanelTheme) -> some View {
        HStack(spacing: 0) {
            // 双击展开/收起手势只作用于左侧标题区，避免与右上角的钉住/关闭按钮
            // 产生手势仲裁：父视图带双击手势时，点击子按钮会被强制等待双击判定
            // 窗口（约 0.25s），造成点击迟滞。
            HStack(spacing: 5) {
                Circle()
                    .fill(theme.liveDot(for: store.haloRingLoadLevel))
                    .frame(width: 5, height: 5)
                    // 仅面板可见时脉冲:面板视图树常驻(NSPanel 不销毁),隐藏期间
                    // 持续动画会白白驱动渲染。
                    .compatiblePulseEffect(isActive: store.isPanelVisible)

                Text(String(localized: "SYSTEM · LIVE"))
                    .monitorPanelLabelFont(tracking: 1.1)
                    .foregroundStyle(theme.captionText)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                toggleAllExpansion()
            }

            if showsQuickPanelControls {
                // 钉住面板:钉住/关闭是面板本体操作不可让位,空间不足时
                // 先舍弃统计入口。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        PanelHeaderToolBadges(theme: theme)
                        statsEntryButton(theme: theme)
                        pinnedControls(theme: theme)
                    }

                    HStack(spacing: 6) {
                        PanelHeaderToolBadges(theme: theme)
                        pinnedControls(theme: theme)
                    }
                }
            } else {
                // 菜单栏面板:右上角随行簇,让位顺序小猫 → 统计入口,
                // 激活工具的运行提示永不退场。该簇是标题子 HStack 的兄弟
                // 节点,不受「双击展开」手势影响(与旧时钟同位)。
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        if cameoModel.isVisible {
                            HeaderCatCameo(
                                model: cameoModel,
                                tint: theme.captionText
                            )
                        }
                        PanelHeaderToolBadges(theme: theme)
                        statsEntryButton(theme: theme)
                    }

                    HStack(spacing: 6) {
                        PanelHeaderToolBadges(theme: theme)
                        statsEntryButton(theme: theme)
                    }

                    PanelHeaderToolBadges(theme: theme)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    /// 钉住面板的钉住/关闭按钮组。
    private func pinnedControls(theme: MonitorPanelTheme) -> some View {
        HStack(spacing: 1) {
            QuickPanelControlButton(
                imageName: quickPanelPresentation.isPinned ? "pin.fill" : "pin",
                help: String(localized: quickPanelPresentation.isPinned ? "panel.unpin" : "panel.pin"),
                tint: theme.secondaryText
            ) {
                quickPanelPresentation.togglePin()
            }

            QuickPanelControlButton(
                imageName: "xmark",
                help: String(localized: "panel.close"),
                tint: .red
            ) {
                quickPanelPresentation.close()
            }
        }
    }

    /// header 常驻的数据统计入口:打开设置页「数据统计」页签(与 App 菜单
    /// 「打开数据报表…」分工——此处为速览,完整 HTML 报表另有专属入口)。
    private func statsEntryButton(theme: MonitorPanelTheme) -> some View {
        QuickPanelControlButton(
            imageName: "chart.bar.doc.horizontal",
            help: String(localized: "panel.statistics"),
            tint: theme.secondaryText
        ) {
            SettingsWindowPresenter.open(tab: .statistics)
        }
    }

    @ViewBuilder
    private func compactRow(for module: MonitorModule, theme: MonitorPanelTheme) -> some View {
        let isExpanded = expandedKinds.contains(module.kind)
        switch module.kind {
        case .cpu:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                samples: module.samples,
                details: cpuDetails(for: module),
                isExpanded: isExpanded,
                topCPUProcesses: store.topCPUProcesses,
                showCPUProcesses: store.settings.showCPUProcesses
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
                isExpanded: isExpanded,
                topGPUProcesses: store.topGPUProcesses,
                showGPUProcesses: store.settings.showGPUProcesses
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .memory:
            let pressureMode = store.settings.memoryPrimaryMetric == .pressure
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: pressureMode ? memoryPressureText(for: module) : module.summary,
                // 压力模式下头部即压力等级文案,按等级着色(与热压力/SMART 同口径);
                // 使用率模式保持常规数值色。
                detailColor: pressureMode ? memoryPressureColor(level: pressureRawLevel(module), theme: theme) : nil,
                // 压力模式下传入压力历史,右侧即切换为曲线;使用率模式传空,保持占比进度条。
                samples: pressureMode ? module.pressureSamples : [],
                details: memoryMetrics(for: module, pressureMode: pressureMode),
                isExpanded: isExpanded,
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
                isExpanded: isExpanded,
                topDiskProcesses: store.topDiskProcesses,
                showDiskProcesses: store.settings.showDiskProcesses
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .network:
            NetworkGlassRow(
                module: module,
                theme: theme,
                details: enabledMetrics(for: module),
                isExpanded: isExpanded,
                topNetworkProcesses: store.topNetworkProcesses,
                showNetworkProcesses: store.settings.showNetworkProcesses
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .battery:
            BatteryGlassRow(
                module: module,
                theme: theme,
                details: enabledMetrics(for: module),
                isExpanded: isExpanded,
                showPowerFlow: store.settings.batteryShowPowerFlow,
                panelVisible: store.isPanelVisible,
                powerFlowActive: !store.isExpansionAnimating
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .fan:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                samples: module.samples,
                isExpanded: isExpanded,
                fans: module.fans
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .bluetooth:
            BluetoothGlassRow(
                module: module,
                theme: theme,
                isExpanded: isExpanded
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

    /// CPU 展开明细:热压力开关开启时把温度指标一并带给网格,供合并整行展示
    /// (温度在面板不再单独开关;菜单栏温度选项独立读取温度指标,不受影响)。
    private func cpuDetails(for module: MonitorModule) -> [MonitorMetric] {
        let enabled = enabledMetrics(for: module)
        guard enabled.contains(where: { $0.name == "thermal-pressure" }),
              let temperature = module.metrics.first(where: { $0.name == "temperature" }) else {
            return enabled
        }
        return enabled + [temperature]
    }

    /// 内存头部主值的压力等级文案(已本地化)。
    private func memoryPressureText(for module: MonitorModule) -> String {
        let raw = module.metrics.first { $0.name == "pressure" }?.value ?? "--"
        return localizedMemoryPressure(raw)
    }

    /// 内存模块当前压力等级原始值;模块未携带压力时按未知处理。
    private func pressureRawLevel(_ module: MonitorModule) -> Int {
        module.pressure?.rawValue ?? MemoryPressureLevel.unknown.rawValue
    }

    /// 压力模式下头部已显示压力等级,展开列表里的「压力」行原位换成「使用率」行,
    /// 两个指标仅交换显示位置,设置里的「压力」开关继续控制该槽位。
    private func memoryMetrics(for module: MonitorModule, pressureMode: Bool) -> [MonitorMetric] {
        let metrics = enabledMetrics(for: module)
        guard pressureMode else { return metrics }
        return metrics.map { metric in
            metric.name == "pressure"
                ? MonitorMetric(name: "usage", value: module.summary, numericValue: module.value)
                : metric
        }
    }

    private func defaultMetricIds(for kind: MonitorKind) -> Set<String> {
        Set(kind.availableMetrics.filter { $0.isDefault }.map { $0.id })
    }

    private func toggleExpansion(for kind: MonitorKind) {
        setExpansion {
            if expandedKinds.contains(kind) {
                expandedKinds.remove(kind)
            } else {
                expandedKinds.insert(kind)
            }
        }
    }

    /// 当前可见 row 的 kind 集合,顺序与渲染顺序一致。
    /// `store.modules` 已由 settings 过滤过,所以只取它即可。
    /// `DisplayControlsSection` 不是 module,天然不在内。
    private var visibleKinds: [MonitorKind] {
        store.modules.map(\.kind)
    }
    
    /// 当前是否所有列表行都处于展开状态。
    /// 空集时为 false——没有行可展开,双击不应被视为「已全开」。
    private var allVisibleRowsExpanded: Bool {
        !visibleKinds.isEmpty
        && visibleKinds.allSatisfy { expandedKinds.contains($0) }
    }
    
    /// 残留 expandedKinds 里的不可见 kind 不影响判定;全展开分支用可见行集合覆盖,顺便清掉残留。
    private func toggleAllExpansion() {
        setExpansion {
            if allVisibleRowsExpanded {
                expandedKinds.removeAll()
            } else {
                expandedKinds = Set(visibleKinds)
            }
        }
    }
    
    /// 把展开状态重置为「各模块默认展开设置 ∩ 可见行」(顺便清掉残留 kind)。
    /// 面板隐藏时直接赋值,不走 setExpansion——无需动画,但要把驱动器相位瞬间
    /// 同步到目标(0/1),否则收起的行会残留旧相位、呼出时高度不对;面板可见时
    /// (钉住面板开着改设置)走 setExpansion,与手动展开同一节奏。
    private func applyDefaultExpansion() {
        let target = store.settings.defaultExpandedKinds.intersection(visibleKinds)
        guard expandedKinds != target else { return }
        if store.isPanelVisible {
            setExpansion { expandedKinds = target }
        } else {
            expandedKinds = target
            // 相位同步覆盖全部模块 kind(而非仅当前可见行):展开中的模块若在隐藏前
            // 因开关/设备断开离开面板,其残留相位也一并归零,重新可见时不带出旧展开高度。
            var sync: [String: CGFloat] = [:]
            for kind in MonitorKind.allCases { sync[kind.id] = target.contains(kind) ? 1 : 0 }
            panelExpansion.setInstantly(targets: sync)
        }
    }

    /// toggle 时 `expandedKinds` 变化驱动 `CollapsibleDetail` 的 `.frame(height:)`
    /// 与 `.opacity` 动画——由 `withAnimation` 包裹状态变更,SwiftUI 动画系统在
    /// CoreAnimation 层插值,不在主线程逐帧重算。窗口目标高度由 driver 一次性
    /// 下发给窗口层做 CA 补间。
    private func setExpansion(_ mutate: () -> Void) {
        // 展开补间与浮层子窗口并存会引发布局抖动,展开前确保浮层已收起。
        QuickToolsStore.shared.popoverPresenter.dismiss()
        // 调试度量(仅 HAGIMI_PANEL_AUTOTEST 生效):在最前打快照,包住整段动画窗口。
        AutotestPerfMeter.shared.beginExpand()
        let previous = expandedKinds
        // 置位一次性动画截止标记:动画窗口内的采样结果推迟应用,避免 1-3s 节奏的
        // 模块刷新恰好撞进 ~0.15s 展开动画、拖动整棵视图树重算造成掉帧。
        store.beginExpansionAnimation()
        withAnimation(.easeInOut(duration: MonitorConstants.panelExpansionDuration)) {
            mutate()
        }
        let current = expandedKinds
        guard current != previous else { return }
        var targets: [String: CGFloat] = [:]
        for removed in previous.subtracting(current) { targets[removed.id] = 0 }
        for added in current.subtracting(previous) { targets[added.id] = 1 }
        panelExpansion.animate(targets: targets)
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

private struct QuickPanelControlButton: View {
    let imageName: String
    let help: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: imageName)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(QuickPanelControlButtonStyle(tint: tint, isHovering: isHovering))
        .help(help)
        .onHover { isHovering = $0 }
    }
}

private struct QuickPanelControlButtonStyle: ButtonStyle {
    let tint: Color
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let backgroundOpacity = configuration.isPressed ? 0.34 : (isHovering ? 0.18 : 0)

        configuration.label
            .foregroundStyle(tint)
            .background(Circle().fill(tint.opacity(backgroundOpacity)))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Header 工具徽章

/// header 右上角的激活工具提示:点亮中的快捷工具逐个亮出小图标,
/// 点击整簇唤起工具浮层(与底部入口同一锚点机制),解锁等操作在浮层完成。
/// 独立子视图观察 QuickToolsStore:开关变化只重绘本簇,不牵动整块面板。
private struct PanelHeaderToolBadges: View {
    @ObservedObject private var store = QuickToolsStore.shared
    let theme: MonitorPanelTheme
    @State private var anchor = QuickToolsAnchorBox()

    private var tint: Color {
        theme.palette.quickToolTint
    }

    var body: some View {
        HStack(spacing: 5) {
            if store.keyboardLocked {
                HStack(spacing: 3) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .semibold))
                    if let deadline = store.keyboardLockAutoUnlockDate {
                        autoUnlockCountdown(deadline: deadline)
                    }
                }
                .help(String(localized: "quicktools.keyboard-lock"))
            }
            if store.systemSleepPrevented {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 11, weight: .semibold))
                    .help(String(localized: "quicktools.system-awake"))
            }
            if store.displayAwake {
                Image(systemName: "sun.max")
                    .font(.system(size: 11, weight: .semibold))
                    .help(String(localized: "quicktools.display-awake"))
            }
        }
        .foregroundStyle(tint)
        .frame(minHeight: 18)
        .contentShape(Rectangle())
        .onTapGesture {
            store.popoverPresenter.toggle(theme: theme, anchor: anchor)
        }
        .background(QuickToolsAnchorView(box: anchor))
        // 菜单栏上已无任何激活工具时,收起本簇锚定的浮层,避免它随塌缩的
        // 徽章簇漂移到统计入口下方(脱离触发来源变得突兀)。仅作用于 header
        // 徽章打开的浮层;底部「工具」入口锚点稳定,不受此约束。
        .onChange(of: store.anyActive) { _, active in
            if !active, store.popoverPresenter.isShown(from: anchor) {
                store.popoverPresenter.dismiss()
            }
        }
    }

    /// 自动解锁倒计时:TimelineView 每秒只重算这一个 Text,不牵动面板
    /// 逐秒刷新(时钟移除后面板 body 已无每秒驱动源)。未锁定时本视图
    /// 整体不在树中,无空转计时。
    private func autoUnlockCountdown(deadline: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.remainingText(from: deadline, now: context.date))
                .monitorPanelMonoFont(.caption2, weight: .medium)
        }
    }

    /// mm:ss,锁定上限 20 分钟,两位分钟足够。
    private static func remainingText(from deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now).rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Metric Row

private struct MetricGlassRow: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let detail: String
    /// 明细文字自定义着色(如内存压力等级);nil 时用常规 valueText。
    var detailColor: Color? = nil
    var samples: [Double] = []
    var details: [MonitorMetric] = []
    var isExpanded = false
    var topMemoryProcesses: [TopMemoryProcess] = []
    var showMemoryProcesses = true
    var fans: [FanInfo]? = nil
    var topCPUProcesses: [TopCPUProcess] = []
    var showCPUProcesses = true
    var topGPUProcesses: [TopGPUProcess] = []
    var showGPUProcesses = true
    var topDiskProcesses: [TopDiskProcess] = []
    var showDiskProcesses = true
    var toggleExpansion: (() -> Void)?

    // theme 完全由 (preference, colorScheme) 决定(见 ThemeCache),故只比这两个键字段;
    // 闭包不参与相等判定。未变化的行 == 成立时 SwiftUI 跳过整行重绘。
    static func == (lhs: MetricGlassRow, rhs: MetricGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.detail == rhs.detail
            && lhs.detailColor == rhs.detailColor
            && lhs.samples == rhs.samples
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.topMemoryProcesses == rhs.topMemoryProcesses
            && lhs.showMemoryProcesses == rhs.showMemoryProcesses
            && lhs.topCPUProcesses == rhs.topCPUProcesses
            && lhs.showCPUProcesses == rhs.showCPUProcesses
            && lhs.topGPUProcesses == rhs.topGPUProcesses
            && lhs.showGPUProcesses == rhs.showGPUProcesses
            && lhs.topDiskProcesses == rhs.topDiskProcesses
            && lhs.showDiskProcesses == rhs.showDiskProcesses
            && lhs.fans == rhs.fans
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    /// 风扇展开区是否可展示。单风扇时主行已显示 RPM,展开无意义,故仅多风扇可展开。
    /// 非 fan 模块不由此属性门控(走 details / fans 原有逻辑)。
    private var fanDetailAvailable: Bool {
        guard module.kind == .fan else { return false }
        return (fans?.count ?? 0) > 1
    }

    /// 展开区是否有内容可显示(统一门控:fan 看 fanDetailAvailable,其余看原逻辑)。
    private var detailAvailable: Bool {
        if module.kind == .fan { return fanDetailAvailable }
        return !details.isEmpty || (fans?.isEmpty == false)
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
                    .foregroundStyle(detailColor ?? theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailingView(theme: theme)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // 手势只挂行头(与 DisplayControlsSection 同款):macOS 上覆盖整个
            // 展开区的 onTapGesture 会抢占深层控件(按钮/滑杆)的点击。
            .contentShape(Rectangle())
            .onTapGesture {
                // 单风扇时主行已展示 RPM,无展开内容,点击不切换展开状态。
                guard detailAvailable else { return }
                toggleExpansion?()
            }

            CollapsibleDetail(expansionKey: module.kind.id, isExpanded: isExpanded, contentAvailable: detailAvailable) {
                Group {
                    if module.kind == .fan, let fans, !fans.isEmpty {
                        FanList(fans: fans, theme: theme)
                    } else if let storageVolumes {
                        StorageVolumeDetailList(volumes: storageVolumes, kind: module.kind, tint: tint, theme: theme)
                    } else {
                        VStack(spacing: 9) {
                            MetricDetailGrid(
                                metrics: details,
                                kind: module.kind,
                                theme: theme,
                                cpuCoreDetail: showCPUCoresDetail ? module.cpuCoreDetail : nil
                            )
                            // CPU / 内存采样恒返回 top 5,故展开时无条件挂载列表(数据未到
                            // 先用留白占位预留高度),使展开一次到位、数据到达后原位淡入,
                            // 不产生二次高度跳变。磁盘采样需采样间隔才有增量,可能为空,仍按需挂载。
                            // GPU 列表数据源为 IORegistry 只读属性,CPU/内存列表走
                            // sysctl + proc_pidinfo,均被沙盒放行,双渠道渲染;
                            // 存储列表依赖沙盒下被拒的 proc_pid_rusage,仅直连版渲染。
                            if module.kind == .gpu, showGPUProcesses {
                                GPUProcessList(processes: topGPUProcesses, theme: theme)
                            }
                            if module.kind == .memory, showMemoryProcesses {
                                MemoryProcessList(processes: topMemoryProcesses, theme: theme)
                            }
                            if module.kind == .cpu, showCPUProcesses {
                                CPUProcessList(processes: topCPUProcesses, theme: theme)
                            }
                            #if DIRECT_DISTRIBUTION
                            if module.kind == .storage, showDiskProcesses {
                                InlineDiskProcessList(processes: topDiskProcesses, theme: theme)
                            }
                            #endif
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .compatibleGlassEffect(cornerRadius: MonitorConstants.rowCornerRadius) {
            theme.rowGlassFill(for: module.kind)
        }
    }

    @ViewBuilder
    private func trailingView(theme: MonitorPanelTheme) -> some View {
        switch module.kind {
        case .cpu, .gpu:
            if !samples.isEmpty {
                SparklineChart(samples: samples, tint: tint)
                    .frame(width: 56, height: 18)
            }
        case .memory:
            // 压力模式才会传入 samples(压力历史):有则画曲线,无则维持使用率占比进度条。
            if !samples.isEmpty {
                SparklineChart(samples: samples, tint: tint)
                    .frame(width: 56, height: 18)
            } else {
                ProgressMeter(value: module.value, tint: tint, theme: theme)
                    .frame(width: 56, height: 3)
            }
        case .storage:
            ProgressMeter(value: module.value, tint: tint, theme: theme)
                .frame(width: 56, height: 3)
        case .network, .battery, .bluetooth:
            EmptyView()
        case .fan:
            // 风扇主行右侧:有 RPM 历史则画 sparkline,否则显示当前 max RPM 数字。
            // Y 轴用风扇硬件 min~max 范围归一化(如 2317~6550),而非默认 0~100,
            // 这样日常 ~2500 RPM 的线不会贴顶,转速变化也能被放大可见。
            if !samples.isEmpty {
                let fanMin = Double(fans?.map(\.minRPM).min() ?? 0)
                let fanMax = Double(fans?.map(\.maxRPM).max() ?? 100)
                SparklineChart(samples: samples, tint: tint, minValue: fanMin, maxValue: fanMax)
                    .frame(width: 56, height: 18)
            } else {
                Text(module.summary)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(theme.valueText)
            }
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

    /// CPU 的 P/E 两行展示生效条件:采样侧产出逐核数据且用户未关闭
    /// core-split 指标开关(关闭时环形图与占用值一并隐藏)。
    private var showCPUCoresDetail: Bool {
        module.kind == .cpu
            && module.cpuCoreDetail != nil
            && details.contains { $0.name == "core-split" }
    }
}

// MARK: - Detail Grid

/// CPU 展开区 P/E 核两行展示:第一行逐核负载环形图(逐行铺满、多核
/// 自动折行,E 核绿/P 核模块色,弧线长度=单核占用),第二行 P/E 分组
/// 占用值(与 core-split 指标同口径,由采样侧同源产出)。嵌入网格内部,
/// 继承分隔线与 28pt 缩进;占用展示取代 core-split 格子避免重复。
private struct CPUCoresDetail: View {
    let detail: CPUCoreDetail
    let theme: MonitorPanelTheme

    /// E 核色:复用 severity calm 绿;P 核色:独立令牌(见 performanceCoreTint),
    /// 与行 tint 保持对比,不引入调色板之外的颜色。
    private var eTint: Color { theme.palette.severityTint(for: .calm) }
    private var pTint: Color { theme.palette.performanceCoreTint }

    var body: some View {
        VStack(spacing: 5) {
            // 圆环逐行铺满:优先放满一行,放不下自动折行;每一行(含末行)
            // 按自身环数把间隙撑满整行,不留右侧空档。
            CoreRingFlowLayout() {
                ForEach(detail.cores) { core in
                    CoreLoadRing(
                        usage: core.usage,
                        tint: core.isPerformance ? pTint : eTint,
                        // 底环比内衬底色深一档(trackFill 叠 trackFill 会糊),
                        // 复用行分隔线令牌拉开层次。
                        track: theme.rowSeparator(for: .cpu)
                    )
                }
            }
            // 内衬背景与指标格同款 trackFill 色块;环底用行分隔线令牌
            // (深一档),避免与底色糊成一片。
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.palette.trackFill)
            )

            HStack(spacing: MetricGridMetrics.columnSpacing) {
                if let efficiency = detail.efficiencyUsage {
                    usageTile(
                        label: String(localized: "cpu.detail.e-cores"),
                        tint: eTint,
                        value: efficiency
                    )
                }
                usageTile(
                    label: String(localized: "cpu.detail.p-cores"),
                    tint: pTint,
                    value: detail.performanceUsage
                )
            }
        }
    }

    /// 分组占用格:与指标网格同款 trackFill 内衬色块;左侧色点标示
    /// 圆环颜色归属,右侧百分比 mono 加粗。
    private func usageTile(label: String, tint: Color, value: Double) -> some View {
        HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(label)
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)
            Text("\(Int(value.rounded()))%")
                .monitorPanelMonoFont(.footnote, weight: .bold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.trackFill))
    }
}

/// 逐核圆环流式布局:优先放满一行(按最小间隙算每行容量),放不下再折行;
/// 每一行(含末行)都按自身环数把间隙撑满整行,单环行居中。
private struct CoreRingFlowLayout: Layout {
    var ringSize: CGFloat = 14
    var minSpacing: CGFloat = 6
    var rowGap: CGFloat = 6

    /// 按可用宽度分行,并为每一行按自身环数计算铺满整行的间隙;
    /// 单环行间隙无意义,由摆放阶段居中处理。
    private func arrange(count: Int, width: CGFloat) -> (rows: [[Int]], spacings: [CGFloat]) {
        guard count > 0, width > 0 else { return ([], []) }
        let perRow = max(1, Int(floor((width + minSpacing) / (ringSize + minSpacing))))
        var rows: [[Int]] = []
        var index = 0
        while index < count {
            rows.append(Array(index..<min(index + perRow, count)))
            index += perRow
        }
        let spacings = rows.map { indices -> CGFloat in
            guard indices.count > 1 else { return 0 }
            return (width - CGFloat(indices.count) * ringSize) / CGFloat(indices.count - 1)
        }
        return (rows, spacings)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 240, height: ringSize)).width
        let (rows, _) = arrange(count: subviews.count, width: width)
        let height = CGFloat(rows.count) * ringSize + CGFloat(max(0, rows.count - 1)) * rowGap
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (rows, spacings) = arrange(count: subviews.count, width: bounds.width)
        var y = bounds.minY
        for (rowIndex, indices) in rows.enumerated() {
            // 单环行居中;多环行从行首起按该行间隙铺满。
            var x = indices.count > 1
                ? bounds.minX
                : bounds.minX + (bounds.width - ringSize) / 2
            let spacing = spacings[rowIndex]
            for (position, subviewIndex) in indices.enumerated() {
                subviews[subviewIndex].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: ringSize, height: ringSize)
                )
                if position < indices.count - 1 {
                    x += ringSize + spacing
                }
            }
            y += ringSize + rowGap
        }
    }
}

/// 单核负载环:trackFill 底环 + 占用弧。弧线随采样帧短促缓动过渡,
/// 无持续动画。
private struct CoreLoadRing: View {
    let usage: Double
    let tint: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, usage / 100)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .animation(.easeOut(duration: 0.3), value: usage)
    }
}

private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let kind: MonitorKind
    let theme: MonitorPanelTheme
    /// CPU 逐核数据:非 nil 时在网格顶部渲染 P/E 两行展示,
    /// 并剔除 core-split 格子(同源数值不重复展示)。
    var cpuCoreDetail: CPUCoreDetail? = nil

    /// 需要占满整行的字段:长值(IP、启动时间)塞两列会撑破列宽或不可控换行;
    /// wifi-rssi 格结构性超宽(标签+信号条+数值+单位四件套,半格装不下);
    /// gateway-latency 是其语义配对,一并整行保持网络块纵列节奏;
    /// capacity 为「剩余 / 满充 mAh」斜杠长值,半格装不下。
    /// 命中项显式整行、排到网格末尾。
    private static let fullRowMetricIDs: Set<String> = [
        "ipv4", "ipv6", "public-ip", "uptime", "adapter", "wifi-ssid",
        "wifi-rssi", "gateway-latency", "capacity"
    ]

    private var leadingInset: CGFloat { 28 }
    private var rowSpacing: CGFloat { MetricGridMetrics.rowSpacing }
    private var labelStyle: Font.TextStyle { .footnote }
    private var valueStyle: Font.TextStyle { .footnote }

    private var shortMetrics: [MonitorMetric] {
        metrics.filter { !Self.fullRowMetricIDs.contains($0.name) && !isMergedThermalRow($0) }
    }

    private var fullRowMetrics: [MonitorMetric] {
        metrics.filter { Self.fullRowMetricIDs.contains($0.name) && !isMergedThermalRow($0) }
    }

    /// core-split 被 P/E 两行展示取代时从格子列表剔除。
    private func isReplacedByCoreDetail(_ metric: MonitorMetric) -> Bool {
        cpuCoreDetail != nil && metric.name == "core-split"
    }

    /// 热压力与温度合并为整行渲染(温度并入热压力行;菜单栏温度选项独立)。
    private func isMergedThermalRow(_ metric: MonitorMetric) -> Bool {
        kind == .cpu && (metric.name == "thermal-pressure" || metric.name == "temperature")
    }

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, leadingInset)

            content
                .padding(.leading, leadingInset)
        }
    }

    // 逐格内衬网格(stat tile 形态):每个指标独立 trackFill 圆角内衬色块,
    // 边界属于格子自己,不依赖行数;单元保持「标签左·数值右」,数值字重
    // 提到 bold 强化存在感。
    private var content: some View {
        VStack(alignment: .leading, spacing: MetricGridMetrics.gridRowGap) {
            if let cpuCoreDetail {
                CPUCoresDetail(detail: cpuCoreDetail, theme: theme)
            }

            if !shortMetrics.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: MetricGridMetrics.columnSpacing),
                              GridItem(.flexible())],
                    spacing: MetricGridMetrics.gridRowGap
                ) {
                    ForEach(shortMetrics) { metric in
                        metricCell(metric)
                    }
                }
            }

            if let thermal = metrics.first(where: { $0.name == "thermal-pressure" }) {
                let temperature = metrics.first { $0.name == "temperature" }
                thermalPressureCell(thermal: thermal, temperature: temperature)
            }

            ForEach(fullRowMetrics) { metric in
                metricCell(metric)
            }
        }
    }

    /// 指标格内衬容器:trackFill 圆角色块包裹,格与格靠 8pt 间隙 + 各自
    /// 色块边界分开;1~2 项的模块同样成立,不产生斑马/发丝线的行级副作用。
    private func insetCell<Content: View>(_ content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.trackFill))
    }

    /// 热压力整行:标签「热压力」,右侧数值为「温度 / 热压力档位」。
    /// 直连版温度可用时双值并排;沙盒版无温度只显示档位。档位按 severity 着色,
    /// 温度保持 valueText 与其余数值同层级。
    private func thermalPressureCell(thermal: MonitorMetric, temperature: MonitorMetric?) -> some View {
        insetCell(
            HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
                Text(localizedMetricName(kind: kind, id: thermal.name))
                    .monitorPanelCaptionFont(labelStyle)
                    .foregroundStyle(theme.captionText)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)

                if let temperature {
                    splitValue(temperature, text: localizedMetricValue(kind: kind, metric: temperature))
                        .help(localizedMetricValue(kind: kind, metric: temperature))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyToPasteboard(temperature.value)
                        }
                }
                splitValue(thermal, text: localizedMetricValue(kind: kind, metric: thermal))
                    .help(localizedMetricValue(kind: kind, metric: thermal))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyToPasteboard(thermal.value)
                    }
            }
        )
    }

    /// 热压力四档 severity 着色:正常→calm 绿,轻微→warning,严重/临界→critical。
    private func thermalPressureColor(_ metric: MonitorMetric) -> Color {
        switch metric.numericValue ?? 0 {
        case ..<1:
            return theme.palette.severityTint(for: .calm)
        case ..<2:
            return theme.palette.severityTint(for: .warning)
        default:
            return theme.palette.severityTint(for: .critical)
        }
    }

    private func metricCell(_ metric: MonitorMetric) -> some View {
        let labelText = localizedMetricName(kind: kind, id: metric.name)
        let valueText = localizedMetricValue(kind: kind, metric: metric)

        // Wi-Fi 信号用「信号格 + dBm」组合(冻结原型),非纯文本值。
        if kind == .network, metric.name == "wifi-rssi" {
            return AnyView(insetCell(wifiSignalCell(labelText: labelText, metric: metric)))
        }

        return AnyView(insetCell(
            HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
                Text(labelText)
                    .monitorPanelCaptionFont(labelStyle)
                    .foregroundStyle(theme.captionText)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)

                splitValue(metric, text: valueText)
                    .help(valueText)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyToPasteboard(metric.value)
                    }
            }
        ))
    }

    /// 数值/单位两段组合:数字 mono bold 主角化,单位 caption 弱化;
    /// 无 unit 标记或后缀不匹配("--"、文本态、长值)时回退整串渲染。
    /// 两段同 layoutPriority(2) 一起预留宽度,单位另加 fixedSize:
    /// 单位若掉到默认优先级,窄格中会被挤成省略号。
    private func splitValue(_ metric: MonitorMetric, text: String) -> some View {
        let parts = splitValueUnit(text, unit: metric.unit)
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.number)
                .monitorPanelMonoFont(valueStyle, weight: .bold)
                .foregroundStyle(metricValueColor(metric))
                .lineLimit(1)
                .layoutPriority(2)
            if let unit = parts.unit {
                Text(unit)
                    .monitorPanelCaptionFont(labelStyle)
                    .foregroundStyle(theme.captionText)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
    }

    /// 按采样侧标注的单位后缀拆分文案;不命中时返回整串。
    private func splitValueUnit(_ text: String, unit: String?) -> (number: String, unit: String?) {
        guard let unit, !unit.isEmpty, text.hasSuffix(unit), text.count > unit.count else {
            return (text, nil)
        }
        return (String(text.dropLast(unit.count)), unit)
    }

    /// Wi-Fi 信号单元:升序四格信号条 + dBm 读数,等级由 RSSI 阈值换算。
    private func wifiSignalCell(labelText: String, metric: MonitorMetric) -> some View {
        HStack(spacing: MetricGridMetrics.cellHStackSpacing) {
            Text(labelText)
                .monitorPanelCaptionFont(labelStyle)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: MetricGridMetrics.cellSpacerMinLength)

            WifiSignalBars(level: Self.wifiSignalLevel(metric.numericValue))

            splitValue(metric, text: metric.value)
        }
    }

    /// RSSI → 信号格数:≥-55 满格,逐级递减,低于 -90 计 0 格。

    private static func wifiSignalLevel(_ rssi: Double?) -> Int {
        guard let rssi else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -75 { return 2 }
        return rssi > -90 ? 1 : 0
    }

    /// 个别指标按语义着色:CPU 热压力四档与 SMART 同口径(正常→calm 绿,
    /// 轻微→warning,严重/临界→critical;serious 与 critical 共用红色,
    /// 档位文本仍可区分);其余数值用 valueText 主角化,
    /// 与 captionText 标签拉开亮度层级,指标多了不再糊成一片。
    private func metricValueColor(_ metric: MonitorMetric) -> Color {
        if kind == .cpu, metric.name == "thermal-pressure" {
            return thermalPressureColor(metric)
        }
        // S.M.A.R.T.:verified 绿、failing 红,与原型 good/crit 色对齐。
        if kind == .storage, metric.name == "smart" {
            return metric.value == "failing"
                ? theme.palette.severityTint(for: .critical)
                : theme.palette.severityTint(for: .calm)
        }
        // 内存压力档位着色:取 pressure-level 指标原始值判级,与热压力/SMART 同口径。
        if kind == .memory, metric.name == "pressure" {
            let level = Int(metrics.first { $0.name == "pressure-level" }?.numericValue
                ?? Double(MemoryPressureLevel.unknown.rawValue))
            return memoryPressureColor(level: level, theme: theme)
        }
        return theme.valueText
    }
}

/// Wi-Fi 信号格:四根升序小柱,点亮数 = 信号等级,网络模块色;未点亮暗灰。
private struct WifiSignalBars: View {
    let level: Int
    @Environment(\.colorScheme) private var colorScheme

    private static let heights: [CGFloat] = [4, 6, 8, 11]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < level
                        ? Color(hex: 0x43A6A0)
                        : Color.white.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .frame(width: 3, height: Self.heights[index])
            }
        }
    }
}

/// 网络明细指标门控(与用户设置无关,纯当前网络条件):条件不符的指标不渲染,
/// 避免面板挂 "--" 噪音行;条件恢复后自动出现。
/// - 主接口非 Wi-Fi(有线/USB 热点)时隐藏 Wi-Fi 信号/SSID——有线连接下
///   Wi-Fi 芯片仍可能关联着家中网络,该读数与当前连接无关;
/// - 探针失败或无对应条件(值为 "--")时隐藏:未连 Wi-Fi → 信号/SSID;
///   无 IPv4 默认网关 → 网关延迟;完全无网络地址 → IP/公网 IP。
private func filteredNetworkMetrics(_ metrics: [MonitorMetric], summary: String) -> [MonitorMetric] {
    let usesWiFi = summary == "Wi-Fi"
    return metrics.filter { metric in
        if metric.value == "--" { return false }
        if (metric.name == "wifi-rssi" || metric.name == "wifi-ssid") && !usesWiFi {
            return false
        }
        return true
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
    case (.cpu, "thermal-pressure"):
        return localizedThermalPressure(metric.value)
    case (.storage, "smart"):
        let key = "storage-smart.\(metric.value)"
        let localized = String(localized: String.LocalizationValue(key))
        return localized == key ? metric.value : localized
    default:
        return metric.value
    }
}

private func localizedThermalPressure(_ id: String) -> String {
    let key = "thermal-pressure.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

private func localizedMemoryPressure(_ id: String) -> String {
    let key = "memory-pressure.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

/// 内存压力档位着色:与热压力/SMART 同口径——正常→calm 绿、
/// 警告→warning、严重→critical;未知态不强调,回退中性 valueText。
/// level 用 MemoryPressureLevel.rawValue。
private func memoryPressureColor(level: Int, theme: MonitorPanelTheme) -> Color {
    switch level {
    case MemoryPressureLevel.warning.rawValue:
        return theme.palette.severityTint(for: .warning)
    case MemoryPressureLevel.critical.rawValue:
        return theme.palette.severityTint(for: .critical)
    case MemoryPressureLevel.unknown.rawValue:
        return theme.valueText
    default:
        return theme.palette.severityTint(for: .calm)
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
    var topNetworkProcesses: [TopNetworkProcess] = []
    var showNetworkProcesses = true
    var toggleExpansion: (() -> Void)?

    static func == (lhs: NetworkGlassRow, rhs: NetworkGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.topNetworkProcesses == rhs.topNetworkProcesses
            && lhs.showNetworkProcesses == rhs.showNetworkProcesses
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    private var hasExpandableContent: Bool {
        #if DIRECT_DISTRIBUTION
        !detailMetrics.isEmpty || showNetworkProcesses
        #else
        // App Store 沙盒版不展示网络 TOP 进程,只依据地址类指标判定是否可展开。
        !detailMetrics.isEmpty
        #endif
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

            CollapsibleDetail(expansionKey: module.kind.id, isExpanded: isExpanded, contentAvailable: hasExpandableContent) {
                VStack(spacing: 9) {
                    if !detailMetrics.isEmpty {
                        MetricDetailGrid(metrics: detailMetrics, kind: module.kind, theme: theme)
                    }
                    // App Store 沙盒版无法采样网络他进程(nettop 被拒),隐藏网络 TOP 进程列表。
                    #if DIRECT_DISTRIBUTION
                    if showNetworkProcesses {
                        InlineNetworkProcessList(processes: topNetworkProcesses, theme: theme)
                    }
                    #endif
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasExpandableContent {
                toggleExpansion?()
            }
        }
        .compatibleGlassEffect(cornerRadius: MonitorConstants.rowCornerRadius) {
            theme.rowGlassFill(for: module.kind)
        }
    }

    private var detailMetrics: [MonitorMetric] {
        // 顺序对齐冻结原型网格配对:(信号, 延迟),SSID 长值整行,地址类殿后。
        // 门控规则见 filteredNetworkMetrics:断网/有线/无 Wi-Fi 时不挂 "--" 行。
        let names = ["wifi-rssi", "gateway-latency", "wifi-ssid", "ipv4", "ipv6", "public-ip"]
        let enabledNames = Set(details.map(\.name))
        let selected = names.compactMap { name -> MonitorMetric? in
            guard enabledNames.contains(name) else { return nil }
            return module.metrics.first(where: { $0.name == name })
        }
        return filteredNetworkMetrics(selected, summary: module.summary)
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
    /// 功率流图开关(Beta,settings.battery.showPowerFlow):关闭后展开区仅保留指标网格。
    var showPowerFlow = true
    /// 面板可见性:与 isExpanded 一起门控功率流的流光动画。
    var panelVisible = true
    /// 功率流流光启用:false 时回落到纯静态绘制,用于展开动画窗口期停更 GPU 流光。
    var powerFlowActive = true
    var toggleExpansion: (() -> Void)?

    static func == (lhs: BatteryGlassRow, rhs: BatteryGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.showPowerFlow == rhs.showPowerFlow
            && lhs.panelVisible == rhs.panelVisible
            && lhs.powerFlowActive == rhs.powerFlowActive
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // 充电时用 `battery.100percent.bolt`(电池中间带闪电)静态图标表示充电状态,
                // 不再叠加 `.variableColor.iterative` 持续动画——该动画会让 SwiftUI 视图图每帧
                // 重渲染整棵面板树,是面板展开时 CPU 高占用的根因之一。图标本身已足够表达充电语义。
                // 低电量模式开启时整个电池图标染成琥珀色(与 macOS 菜单栏省电态同思路,
                // SF Symbols 为模板图,颜色由前景样式决定,无需单独的黄色电池符号)。
                Image(systemName: powerSymbol)
                    .font(.callout.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isLowPowerMode ? theme.palette.severityTint(for: .warning) : tint)
                    .frame(width: 18)
                    .help(isLowPowerMode ? String(localized: "panel.battery.low-power-on") : "")

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

                // 双 pill 常驻:⚡(充电功率)+ 仪表(整机功耗)。成对出现互相注解——
                // 闪电抢占「充电」语义后,仪表自然归位为「消耗读数」;未充电时 CHG
                // 显占位符而非隐藏,布局永不跳动(同进程列表横杠占位哲学)。
                // 台式机无电池无充电概念,只显功耗 pill。
                if hasBattery {
                    PowerLabelPill(symbol: "bolt.fill", value: chargingPillValue, theme: theme)
                        .layoutPriority(0)
                }
                PowerLabelPill(symbol: "gauge.with.needle", value: value("power"), theme: theme)
                    .layoutPriority(0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // 手势只挂行头,不覆盖展开区(与 MetricGlassRow/DisplayControlsSection
            // 同款纪律:整行 onTapGesture 会抢占深层控件的点击)。
            .contentShape(Rectangle())
            .onTapGesture {
                if canExpand {
                    toggleExpansion?()
                }
            }

            CollapsibleDetail(expansionKey: module.kind.id, isExpanded: isExpanded, contentAvailable: canExpand) {
                VStack(spacing: 9) {
                    MetricDetailGrid(metrics: detailMetrics, kind: module.kind, theme: theme)
                    // 指标网格(健康度/温度/循环/损耗)与功率流图之间用带标题的分区分隔线
                    // 明确隔开。功率流是电源模块的展开区亮点,双渠道(含沙盒)均可用——
                    // 数据全部来自 BatterySampler 读 AppleSmartBattery/PowerTelemetryData 的
                    // IORegistry 只读属性,不涉及他进程采样或私有 API,沙盒允许。
                    // 由设置项 batteryShowPowerFlow(Beta)门控,关闭后展开区仅剩指标网格。
                    // 功率流无 power 数据(老款 Mac 读不到 PowerTelemetryData.SystemPower)时整体隐藏,
                    // 避免只显标题不出图的视觉断裂。canExpand 已用同一条件门控展开动作,渲染侧保持联动。
                    if showPowerFlow && numericValue("power") != nil {
                        PowerSectionHeader(title: String(localized: "panel.power-flow.title"), theme: theme)
                            .padding(.top, 3)
                            // 与明细网格同 28pt 缩进,分区标题与下方图内容左缘对齐(原型基准)。
                            .padding(.leading, 28)
                        PowerFlowDiagram(
                            module: module,
                            theme: theme,
                            tint: tint,
                            animate: isExpanded && showPowerFlow && panelVisible && powerFlowActive
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .compatibleGlassEffect(cornerRadius: MonitorConstants.rowCornerRadius) {
            theme.rowGlassFill(for: module.kind)
        }
    }

    private var hasBattery: Bool {
        rawValue("type") == "battery"
    }

    private var isCharging: Bool {
        rawValue("status") == "charging"
    }

    /// 低电量模式(系统设置 > 电池):开启时行头图标叠叶片角标。
    private var isLowPowerMode: Bool {
        hasBattery && rawValue("low-power-mode") == "on"
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

    /// CHG pill 内容:充电中显充电功率,其余状态(电池供电/插电直供)显占位符。
    private var chargingPillValue: String {
        guard isCharging else { return "-" }
        let raw = rawValue("charging-power")
        return raw == "--" ? "-" : raw
    }

    private var summaryText: String {
        if hasBattery {
            localizedBatteryState(module.summary)
        } else {
            value("adapter")
        }
    }

    private var detailMetrics: [MonitorMetric] {
        // 充电功率已上移到行首常驻 CHG pill,明细不再重复展示。
        // 充电限制只保留在功率流电池条的旗标上,低电量模式只保留行头图标
        // 着色与功率流配色。电压/电流为常规半格;容量是「剩余 / 满充 mAh」
        // 斜杠长值,由 fullRowMetricIDs 自动整行排到末尾。
        let names = ["health", "cycle-count", "temperature", "power-loss", "voltage", "current", "capacity"]

        let enabledNames = Set(details.map(\.name))

        return names.compactMap { name in
            guard enabledNames.contains(name) else { return nil }
            return module.metrics.first(where: { $0.name == name })
        }
    }

    private var canExpand: Bool {
        // 指标全关时,只有功率流开启且有功耗值,展开区才仍有内容可显示。
        !detailMetrics.isEmpty || (showPowerFlow && numericValue("power") != nil)
    }

    private func numericValue(_ name: String) -> Double? {
        module.metrics.first { $0.name == name }?.numericValue
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
}

func localizedBatteryState(_ id: String) -> String {
    let key = "battery-state.\(id)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? id : localized
}

// MARK: - Power Flow

/// 展开区分区标题:一段小标题 + 贯穿分隔线,用来把上方的电池指标网格
/// (健康度/温度/循环/损耗)与下方的功率流图、耗电排行明确切分成独立区块。
private struct PowerSectionHeader: View {
    let title: String
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .monitorPanelLabelFont(tracking: 0.8)
                .foregroundStyle(theme.captionText)
                .fixedSize()
            Rectangle()
                .fill(theme.rowSeparator(for: .battery))
                .frame(height: 1)
        }
    }
}

/// 充电上限旗标形状:顶端倒三角旗头(底边在上、尖朝下) + 自旗头尖端下探的
/// 细圆头竖线,单一填充色整形绘制。
struct LimitFlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headHeight: CGFloat = 5
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + headHeight))
        path.closeSubpath()
        let lineWidth: CGFloat = 1.5
        path.addRoundedRect(
            in: CGRect(x: rect.midX - lineWidth / 2, y: rect.minY + headHeight,
                       width: lineWidth, height: rect.height - headHeight),
            cornerSize: CGSize(width: lineWidth / 2, height: lineWidth / 2)
        )
        return path
    }
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

/// 外置卷 JSON 解码器。JSONDecoder 默认无跨解码状态,共享一个实例即可,
/// 避免每次面板刷新解析存储卷时都新建。仅主线程(SwiftUI body)调用,无并发问题。
private let externalVolumeDecoder = JSONDecoder()

private func parseExternalVolumes(_ context: String?) -> [StorageVolumeInfo] {
    guard let context, let data = context.data(using: .utf8) else {
        return []
    }

    if let payload = try? externalVolumeDecoder.decode([ExternalVolumePayload].self, from: data) {
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

/// 电源行专用的定宽 pill:符号标识(⚡充电 / 仪表功耗)+ 数值。
/// 定宽保证数值位数变化/充电状态切换时行内元素不抖动。
private struct PowerLabelPill: View {
    let symbol: String
    let value: String
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.secondaryText.opacity(0.72))
            Text(value)
                .foregroundStyle(theme.secondaryText)
        }
        .font(.system(.footnote, design: .monospaced).weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(width: 74, alignment: .trailing)
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

    @ViewBuilder
    func rowGlassFill(for kind: MonitorKind) -> some View {
        palette.rowGlassFill(for: kind)
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
enum ThemeCache {
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

// MARK: - Top Processes (通用列表)

/// 通用 TOP 进程行数据。内存/CPU/GPU 三列表共用,行内可选 Rosetta 角标与 API 类型。
private struct TopProcessRowData {
    let name: String
    let icon: NSImage?
    let valueText: String
    /// GPU 的图形 API 类型(Metal 等),空/未上报时不渲染。非 GPU 列表传 nil。
    let apiText: String?
    /// 是否正通过 Rosetta 转译(仅 CPU 可能为 true)。
    let translated: Bool
}

/// 通用 TOP 进程列表:分隔线 + 固定 5 行 + 可选 Rosetta 横幅。
/// 内存/CPU/GPU 三列表主体完全一致,差异(值格式/角标/横幅)收敛为参数,
/// 避免三份近逐字重复的视图各自漂移。
private struct TopProcessList: View {
    let kind: MonitorKind
    let rows: [TopProcessRowData]
    let theme: MonitorPanelTheme
    /// CPU 列表在存在转译进程时展示汇总横幅;其余列表传 false。
    let showRosettaBanner: Bool

    /// 固定展示 top 5 个位置:真实数据从上往下填,空位显“—”占位。
    private static let rowCount = 5

    var body: some View {
        let translatedCount = rows.filter(\.translated).count

        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    if index < rows.count {
                        let proc = rows[index]
                        HStack(spacing: 6) {
                            ProcessIcon(icon: proc.icon, theme: theme)
                                .frame(width: 16, height: 16)

                            Text(proc.name)
                                .monitorPanelCaptionFont(.footnote)
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            // Rosetta 转译角标:macOS 28 起 Intel 应用将无法运行,
                            // 在 TOP 进程行内尽早暴露(仅 arm64 宿主可能为 true)。
                            if proc.translated {
                                RosettaBadge()
                            }

                            Spacer(minLength: 4)

                            Text(proc.valueText)
                                .monitorPanelMonoFont(.caption2, weight: .medium)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)

                            // 图形 API 类型(Metal 等):驱动在 AppUsage 里按 API 记录
                            // GPU 时间,空值(旧驱动/未上报)时不渲染。
                            if let apiText = proc.apiText {
                                Text(apiText)
                                    .monitorPanelCaptionFont(.caption2)
                                    .foregroundStyle(theme.captionText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    } else {
                        ProcessPlaceholderRow(theme: theme)
                    }
                }
            }
            .padding(.leading, 28)
            .animation(.easeInOut(duration: 0.2), value: rows.count)

            // 转译进程汇总横幅:CPU 列表存在转译进程时才出现。
            if showRosettaBanner, translatedCount > 0 {
                RosettaBanner(count: translatedCount, theme: theme)
                    .padding(.leading, 28)
            }
        }
    }
}

private struct MemoryProcessList: View {
    let processes: [TopMemoryProcess]
    let theme: MonitorPanelTheme

    var body: some View {
        TopProcessList(
            kind: .memory,
            rows: processes.map {
                TopProcessRowData(
                    name: $0.name,
                    icon: $0.icon,
                    valueText: byteCountString(Int64($0.memoryUsage), countStyle: .memory),
                    apiText: nil,
                    translated: false
                )
            },
            theme: theme,
            showRosettaBanner: false
        )
    }
}

// MARK: - Top CPU Processes

private struct CPUProcessList: View {
    let processes: [TopCPUProcess]
    let theme: MonitorPanelTheme

    var body: some View {
        TopProcessList(
            kind: .cpu,
            rows: processes.map {
                TopProcessRowData(
                    name: $0.name,
                    icon: $0.icon,
                    valueText: String(format: "%.1f%%", $0.cpuUsage),
                    apiText: nil,
                    translated: $0.translated
                )
            },
            theme: theme,
            showRosettaBanner: true
        )
    }
}

// MARK: - Top GPU Processes

private struct GPUProcessList: View {
    let processes: [TopGPUProcess]
    let theme: MonitorPanelTheme

    var body: some View {
        TopProcessList(
            kind: .gpu,
            rows: processes.map {
                TopProcessRowData(
                    name: $0.name,
                    icon: $0.icon,
                    valueText: String(format: "%.1f%%", $0.gpuUsage),
                    apiText: $0.api.isEmpty ? nil : $0.api,
                    translated: false
                )
            },
            theme: theme,
            showRosettaBanner: false
        )
    }
}

/// Rosetta 角标:小号琥珀胶囊,样式对齐冻结原型(badge-rosetta)。
private struct RosettaBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let warning = Color(hex: 0xB8872E)
        Text("ROSETTA")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(colorScheme == .dark ? Color(hex: 0xE0B45E) : warning)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(warning.opacity(colorScheme == .dark ? 0.15 : 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(warning.opacity(colorScheme == .dark ? 0.45 : 0.38), lineWidth: 1))
    }
}

/// Rosetta 汇总横幅:提醒转译进程数量与 macOS 28 兼容性风险。
private struct RosettaBanner: View {
    let count: Int
    let theme: MonitorPanelTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let warning = Color(hex: 0xB8872E)
        Text(String(format: String(localized: "panel.processes.rosetta-banner"), count))
            .font(.system(size: 10))
            .foregroundStyle(colorScheme == .dark ? Color(hex: 0xE0B45E) : warning)
            .lineLimit(3)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(warning.opacity(colorScheme == .dark ? 0.09 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(warning.opacity(0.30), lineWidth: 1))
    }
}

/// 进程行“—”占位(单值列版,用于 CPU/内存):与真实行同结构(16pt 图标位 + 一行文本),
/// 图标位留空、名称与数值位显淡色横杠,撑住高度并告知“空位”。
private struct ProcessPlaceholderRow: View {
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 16, height: 16)
            Text("—")
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(theme.secondaryText.opacity(0.5))
            Spacer(minLength: 4)
            Text("—")
                .monitorPanelMonoFont(.caption2, weight: .medium)
                .foregroundStyle(theme.secondaryText.opacity(0.5))
        }
    }
}

// MARK: - Top Disk Processes

// DiskProcessList and NetworkProcessList removed — inline rendering used instead

/// 简单的进程行数据，用于 ForEach 渲染。避免跨文件类型的 SwiftUI 类型推断问题。
private struct ProcessRowData: Identifiable {
    let id: Int
    let name: String
    let icon: NSImage?
    /// 上行/写入 值(不含箭头)
    let upText: String
    /// 下行/读取 值(不含箭头)
    let downText: String
    var isPlaceholder = false
}

/// 固定 5 行的“—”占位行数据:磁盘/网络无数据或不足 5 行时填充。
private let processDashRow = ProcessRowData(id: -1, name: "—", icon: nil, upText: "—", downText: "—", isPlaceholder: true)

/// 磁盘 I/O 进程列表。固定 5 行位置:真实数据从上往下填,空位显“—”,高度恒定无加载跳变。
private struct InlineDiskProcessList: View {
    let processes: [TopDiskProcess]
    let theme: MonitorPanelTheme

    private static let rowCount = 5

    private var rows: [ProcessRowData] {
        processes.enumerated().map { index, proc in
            ProcessRowData(
                id: Int(proc.pid),
                name: proc.name,
                icon: proc.icon,
                upText: byteCountString(Int64(proc.bytesWritten)),
                downText: byteCountString(Int64(proc.bytesRead))
            )
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .storage))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    ProcessRowView(row: index < rows.count ? rows[index] : processDashRow, theme: theme)
                }
            }
            .padding(.leading, 28)
            .animation(.easeInOut(duration: 0.2), value: rows.count)
        }
    }
}

/// 网络流量进程列表。固定 5 行位置:真实数据从上往下填,空位显“—”,高度恒定无加载跳变。
private struct InlineNetworkProcessList: View {
    let processes: [TopNetworkProcess]
    let theme: MonitorPanelTheme

    private static let rowCount = 5

    private var rows: [ProcessRowData] {
        processes.enumerated().map { index, proc in
            ProcessRowData(
                id: Int(proc.pid),
                name: proc.name,
                icon: proc.icon,
                upText: bytesPerSecond(Double(proc.upload)),
                downText: bytesPerSecond(Double(proc.download))
            )
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .network))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    ProcessRowView(row: index < rows.count ? rows[index] : processDashRow, theme: theme)
                }
            }
            .padding(.leading, 28)
            .animation(.easeInOut(duration: 0.2), value: rows.count)
        }
    }
}

/// 风扇展开区列表:按实际风扇数量动态渲染行数(无占位行)。
/// 每行展示 name / current RPM / min-max 比例条 / 状态指示点。
/// 仅在多风扇(>=2)时渲染;单风扇的主行已展示 RPM,不进入展开区。
private struct FanList: View {
    let fans: [FanInfo]
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .fan))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(fans) { fan in
                    fanRow(fan)
                }
            }
            .padding(.leading, 28)
        }
    }

    /// 渲染单个风扇行:状态点 + 名称 + RPM(带单位,取代原 min-max 比例条)。
    @ViewBuilder
    private func fanRow(_ fan: FanInfo) -> some View {
        let status = fan.status

        HStack(spacing: 6) {
            // 状态指示点:fault=红 / warning=橙 / normal=绿 / unknown=灰
            Circle()
                .fill(theme.palette.severityTint(for: status.severity))
                .frame(width: 5, height: 5)
            Text(fan.name)
                .monitorPanelMetricLabelFont()
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            // 单位直接缀在数值后:比例条信息量低且易被误读为 sparkline。
            Text("\(fan.currentRPM) RPM")
                .monitorPanelMonoFont(.callout, weight: .semibold)
                .foregroundStyle(rpmColor(for: status))
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    /// RPM 数值颜色:fault/warning 用 severity 色,normal/unknown 用默认值色。
    private func rpmColor(for status: FanStatus) -> Color {
        switch status {
        case .fault, .warning: theme.palette.severityTint(for: status.severity)
        case .normal, .unknown: theme.valueText
        }
    }
}

/// 蓝牙设备电量行:行头显示设备数与最低电量,展开区逐设备列出电量。
/// 与 BatteryGlassRow 同款结构:手势只挂行头,展开区不拦截。
private struct BluetoothGlassRow: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var isExpanded = false
    var toggleExpansion: (() -> Void)?

    static func == (lhs: BluetoothGlassRow, rhs: BluetoothGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.isExpanded == rhs.isExpanded
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    private var devices: [BluetoothDeviceInfo] {
        module.bluetoothDevices ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                module.kind.symbolImage
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
                    // 占位宽度与其余行头图标(SF Symbols .frame(width: 18))一致,
                    // 保证各行标题文字起始列对齐;高度 14 匹配符文的窄高形态。
                    .frame(width: 18, height: 14)

                Text("\(module.kind.title):")
                    .monitorPanelMetricLabelFont()
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(module.summary)
                    .monitorPanelMonoFont(weight: .semibold)
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // 行尾不放电量数值:多设备时「最低电量」归属不明,易误读;
                // 与显示器模块同款展开箭头,设备明细全在展开区。
                // 无设备时无内容可展开,箭头隐藏(显占位保持行高稳定)。
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.captionText)
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: MonitorConstants.panelExpansionDuration), value: isExpanded)
                    .opacity(devices.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                // 无设备时展开区无内容,点击不切换状态。
                guard !devices.isEmpty else { return }
                toggleExpansion?()
            }

            CollapsibleDetail(expansionKey: module.kind.id, isExpanded: isExpanded, contentAvailable: !devices.isEmpty) {
                BluetoothDeviceList(devices: devices, theme: theme)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
        }
        .compatibleGlassEffect(cornerRadius: MonitorConstants.rowCornerRadius) {
            theme.rowGlassFill(for: module.kind)
        }
    }
}

/// 蓝牙展开区设备列表:图标底座 + 名称/类型双行文字 + 电量条 + 百分比。
/// 未上报电量的设备(厂商私有协议,系统本身收不到)右侧以短横占位,不伪造读数。
private struct BluetoothDeviceList: View {
    let devices: [BluetoothDeviceInfo]
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .bluetooth))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 8) {
                ForEach(devices) { device in
                    deviceRow(device)
                }
            }
            .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: BluetoothDeviceInfo) -> some View {
        HStack(spacing: 8) {
            // 图标底座:模块色圆角方块承托形态符号,与系统设备卡片语言一致。
            Image(systemName: device.type.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.moduleTint(for: .bluetooth))
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.badgeFill(for: .bluetooth))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(typeLabel(for: device.type))
                    .monitorPanelCaptionFont()
                    .foregroundStyle(theme.captionText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let level = device.batteryLevel {
                BluetoothBatteryBar(level: level, tint: batteryColor(level), theme: theme)
                    .frame(width: 56, height: 6)
                Text("\(level)%")
                    .monitorPanelMonoFont(.footnote, weight: .semibold)
                    .foregroundStyle(levelTextColor(level))
                    .lineLimit(1)
                    .frame(width: 38, alignment: .trailing)
            } else {
                // 无电量设备右侧占位与 TOP 进程空位行同规;列表本身即「已连接」清单。
                Text("—")
                    .monitorPanelCaptionFont(.footnote)
                    .foregroundStyle(theme.captionText)
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    /// 电量条颜色:低电区间走 severity 色,正常区间绿色呼应电池语义。
    private func batteryColor(_ level: Int) -> Color {
        if Double(level) <= MonitorConstants.batteryCriticalThreshold {
            return theme.palette.severityTint(for: .critical)
        }
        if Double(level) <= MonitorConstants.batteryWarningThreshold {
            return theme.palette.severityTint(for: .warning)
        }
        return theme.palette.severityTint(for: .calm)
    }

    /// 电量数字颜色:常态用中性值色,只有低电区间才染 severity 色,
    /// 避免饱和绿文字在玻璃底上抢眼。
    private func levelTextColor(_ level: Int) -> Color {
        if Double(level) <= MonitorConstants.batteryCriticalThreshold {
            return theme.palette.severityTint(for: .critical)
        }
        if Double(level) <= MonitorConstants.batteryWarningThreshold {
            return theme.palette.severityTint(for: .warning)
        }
        return theme.valueText
    }

    /// 设备类型副标题:三语文案见 Localizable 的 bluetooth.type.* 键。
    private func typeLabel(for type: BluetoothDeviceType) -> String {
        switch type {
        case .mouse: String(localized: "bluetooth.type.mouse")
        case .keyboard: String(localized: "bluetooth.type.keyboard")
        case .headphones: String(localized: "bluetooth.type.headphones")
        case .headset: String(localized: "bluetooth.type.headset")
        case .gamepad: String(localized: "bluetooth.type.gamepad")
        case .trackpad: String(localized: "bluetooth.type.trackpad")
        case .speaker: String(localized: "bluetooth.type.speaker")
        case .other: String(localized: "bluetooth.type.other")
        }
    }
}

/// 设备电量条:trackFill 底槽 + 按百分比填充,只用调色板令牌。
private struct BluetoothBatteryBar: View {
    let level: Int
    let tint: Color
    let theme: MonitorPanelTheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.palette.trackFill)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * CGFloat(max(0, min(100, level))) / 100)
            }
        }
    }
}

/// 通用进程行渲染。isPlaceholder 为真时渲染"—"空位行(清图标 + 淡色横杠)。
private struct ProcessRowView: View {
    let row: ProcessRowData
    let theme: MonitorPanelTheme

    var body: some View {
        HStack(spacing: 6) {
            if row.isPlaceholder {
                Color.clear
                    .frame(width: 16, height: 16)
            } else {
                ProcessIcon(icon: row.icon, theme: theme)
                    .frame(width: 16, height: 16)
            }

            Text(row.name)
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(row.isPlaceholder ? theme.secondaryText.opacity(0.5) : theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // 两个数值各占固定宽度、右对齐:箭头留在左侧固定位置,数字尾部对齐,
            // 数值宽度变化时列位置不再左右抖动,跨行也对齐成整齐两列。
            HStack(spacing: 10) {
                metricColumn(symbol: "↑", value: row.upText)
                metricColumn(symbol: "↓", value: row.downText)
            }
            .foregroundStyle(row.isPlaceholder ? theme.secondaryText.opacity(0.5) : theme.secondaryText)
            .lineLimit(1)
            .layoutPriority(1)
        }
    }

    private func metricColumn(symbol: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(symbol)
                .monitorPanelMonoFont(.caption2, weight: .medium)
            Text(value)
                .monitorPanelMonoFont(.caption2, weight: .medium)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

/// 取不到图标(命令行进程等)时回退到通用应用占位图标,保证每行视觉对齐一致。
private struct ProcessIcon: View {
    let icon: NSImage?
    let theme: MonitorPanelTheme

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .font(.caption2)
                .foregroundStyle(theme.captionText)
        }
    }
}

// MARK: - Collapsible Detail

/// 高度揭示式展开容器。
///
/// 不能用 scale / opacity 这类「渲染层变换」做展开:它们不改变布局占位--展开区一插入就
/// 按完整高度占位,容器(进而窗口)高度会「瞬间」跳到终点,随后内容才在已定型的空间里
/// 淡入/缩放,肉眼看到「边框先到位、内容再补上」的错位闪烁;收起时镜像反过来。
///
/// 实现:内容常驻(以测出自然高度),布局高度在展开/收起两态间切换(0 或自然高度),
/// 由 SwiftUI 动画系统(`.animation(value: isExpanded)`)在 CoreAnimation 层插值--
/// body 只在 toggle 时求值一次,帧间高度插值由 CA 在合成器侧完成,不在主线程逐帧
/// 重算。顶部对齐 + 裁剪,内容随高度增长自上而下「卷出」。
///
/// `isExpanded` 是展开态(toggle 时触发高度动画),`contentAvailable` 是内容门控:
/// 内容可用性消失(如蓝牙设备全部断开)时高度直接钳 0,瞬时归零、不参与动画--
/// 数据驱动的收起没有用户手势,不需要过渡动画。
///
/// 供各 metric 行与 `DisplayControlsSection`(Direct 目标)共用,故非 private。
struct CollapsibleDetail<Content: View>: View {
    /// 面板根注入的展开驱动器:仅用于上报自然高度供窗口高度预测。
    @EnvironmentObject private var expansion: PanelExpansionDriver
    /// 驱动器内对应的展开区 key。
    private let expansionKey: String
    /// 是否处于展开态。toggle 时由 SwiftUI 动画系统补间布局高度。
    private let isExpanded: Bool
    /// 是否有可展开的内容。false 时无论展开态如何,高度恒为 0。
    private let contentAvailable: Bool
    private let content: Content

    /// 内容的自然高度。内容始终挂载并被 GeometryReader 测量,故在首次展开前就已就绪,
    /// 保证展开时高度从 0 平滑增长,而不是等测量回填后「跳」到终点。
    @State private var contentHeight: CGFloat = 0

    init(
        expansionKey: String,
        isExpanded: Bool,
        contentAvailable: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.expansionKey = expansionKey
        self.isExpanded = isExpanded
        self.contentAvailable = contentAvailable
        self.content = content()
    }

    var body: some View {
        let expanded = contentAvailable && isExpanded
        content
            .opacity(expanded ? 1 : 0)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            contentHeight = geometry.size.height
                            expansion.reportNaturalHeight(expansionKey, geometry.size.height)
                        }
                        .onChange(of: geometry.size.height) { _, newValue in
                            // 内容自然高度变化(内层档案开合、风扇模式插入滑杆等)时,
                            // onChange 回调无动画上下文,裸更新会让容器高度与下方内容
                            // 的位移瞬跳;显式包一次补间,让它平滑并入既有展开节奏。
                            withAnimation(.easeInOut(duration: MonitorConstants.panelExpansionDuration)) {
                                contentHeight = newValue
                            }
                            expansion.reportNaturalHeight(expansionKey, newValue)
                        }
                }
            )
            // 展开时高度 = 自然高度,收起时 = 0;由 .animation(value: isExpanded)
            // 在 CoreAnimation 层插值,不在主线程逐帧重算。顶部对齐 + 裁剪,
            // 使内容随高度增长自上而下「卷出」。
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            // 收起(高度 0、不可见)不参与点击,避免拦截行的展开手势。
            .allowsHitTesting(isExpanded)
            // toggle 时 SwiftUI 动画系统补间高度与透明度;contentAvailable 变化
            // (数据驱动)不触发此动画,瞬时切换。
            .animation(.easeInOut(duration: MonitorConstants.panelExpansionDuration), value: isExpanded)
    }
}
