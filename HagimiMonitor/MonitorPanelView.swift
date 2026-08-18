import AppKit
import SwiftUI

private let panelTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

/// 主体 ScrollView 两端是否还有被裁内容,驱动上下渐隐遮罩。
private struct BodyScrollEdges: Equatable {
    let top: Bool
    let bottom: Bool
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
    @State private var timeString: String = ""
    @State private var timeUpdateTask: Task<Void, Never>?
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

    init(store: MonitorStore, quickPanelPresentation: QuickPanelPresentation? = nil) {
        self.store = store
        let presentation = quickPanelPresentation ?? QuickPanelPresentation()
        _quickPanelPresentation = ObservedObject(wrappedValue: presentation)
        showsQuickPanelControls = quickPanelPresentation != nil
    }

    /// 主体 ScrollView 的高度上限:内容总高上限减去 header、上下内边距(10×2)
    /// 与 header—主体间距(6)。header 首帧尚未测定时偏大,由窗口层 clamp 兜底。
    /// 无上限(钉住面板等宿主)时返 nil,不施加约束。
    private var scrollBodyMaxHeight: CGFloat? {
        guard maxContentHeight != .infinity else { return nil }
        return max(120, maxContentHeight - headerHeight - 26)
    }

    var body: some View {
        // theme 按 (preference, colorScheme) 缓存,避免每秒采样刷新时重建整棵 Color 树。
        // 缓存返回稳定实例,Row 的 Equatable 比较可据此跳过未变化行。
        let theme = ThemeCache.theme(
            preference: store.settings.colorSchemePreference,
            scheme: colorScheme
        )

        CompatibleGlassContainer(spacing: 8) {
            VStack(spacing: 6) {
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
                                row(for: module, theme: theme)
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
                                    beginExpansionAnimation: { store.beginExpansionAnimation() }
                                )
                                .compatibleGlassEffectID("display-info", in: glassNamespace)
                            }
                            #endif

                            #if DISPLAY_CONTROL
                            if store.settings.displayModuleVisible {
                                DisplayControlsSection(
                                    settings: store.settings,
                                    isPanelVisible: store.isPanelVisible,
                                    beginExpansionAnimation: { store.beginExpansionAnimation() }
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
                                < geometry.contentSize.height - 1
                        )
                    } action: { _, edges in
                        isBodyScrolled = edges.top
                        bodyHasMoreBelow = edges.bottom
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
            // 底边留白与面板内部行间节奏(6pt)对齐;顶/侧保持 10pt。
            .padding(.top, 10)
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
                // header 时钟仅面板可见时推进:视图树常驻,隐藏期间每秒的 @State
                // 更新只会白白重算整棵 body。
                startTimeUpdateTask()
                cameoModel.panelDidAppear()
                // 调试自动测试:可见后 0.8s 自动全量展开(走真实 setExpansion 动画路径),
                // 供 sizeDidChange 日志观察展开期间的尺寸上报行为。
                if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guard store.isPanelVisible else { return }
                        setExpansion { expandedKinds = Set(listKinds) }
                    }
                }
            } else {
                timeUpdateTask?.cancel()
                timeUpdateTask = nil
                cameoModel.panelDidDisappear()
            }
        }
        .onChange(of: store.settings.defaultExpandedKinds) { _, _ in
            // 设置变更立即生效:面板隐藏则为下次呼出预置状态;
            // 钉住面板开着改设置时可见,直接预览展开/收起效果。
            applyDefaultExpansion()
        }
        .onAppear {
            // 视图只创建一次(常驻 NSPanel),此处覆盖首次呼出前的默认展开。
            applyDefaultExpansion()
            // 上报当前需进程采样的集合(展开 ∪ 放大):面板重开时 @State 可能保留上次选项,
            // 而 store 已在上次关闭时清空该来源,此处重新同步以触发对应采样。
            reportActiveProcessKinds()
            // 钉住面板不走 isPanelVisible 的可见性分支时(已可见),补启动时钟。
            if store.isPanelVisible, !showsQuickPanelControls, timeUpdateTask == nil {
                startTimeUpdateTask()
            }
        }
        .onDisappear {
            timeUpdateTask?.cancel()
        }
        .onChange(of: expandedKinds) { _, _ in
            reportActiveProcessKinds()
        }
        .onChange(of: store.settings.cardStyleKinds) { _, _ in
            // 显示方式变更:卡片模块常显进程列表,需立即重报采样集合;
            // 尺寸变化属配置驱动,不置位展开补间标记,窗口走瞬时贴合路径。
            reportActiveProcessKinds()
        }
    }

    /// 需进程采样的类目集 = 行内展开的模块 ∪ 卡片模块(卡片常显进程列表,视同展开)。
    private func reportActiveProcessKinds() {
        let cardKinds = store.settings.cardStyleKinds.intersection(visibleKinds)
        store.updateExpandedKinds(expandedKinds.union(cardKinds), for: panelSource)
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
            } else {
                // 小猫客串紧贴在时间左侧。只在可见时才占位，隐藏时不留空隙、时间正常靠右。
                // 该分支是标题子 HStack 的兄弟节点，不受「双击展开」手势影响。
                HStack(spacing: 6) {
                    if cameoModel.isVisible {
                        HeaderCatCameo(
                            model: cameoModel,
                            tint: theme.captionText
                        )
                    }

                    Text(timeString)
                        .monitorPanelMonoFont(.caption2, weight: .medium)
                        .foregroundStyle(theme.captionText)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func row(for module: MonitorModule, theme: MonitorPanelTheme) -> some View {
        // 显示方式为「大卡片」的模块渲染常显卡片,无展开/收起交互;其余走紧凑行。
        if store.settings.cardStyleKinds.contains(module.kind) {
            card(for: module, theme: theme)
        } else {
            compactRow(for: module, theme: theme)
        }
    }

    @ViewBuilder
    private func card(for module: MonitorModule, theme: MonitorPanelTheme) -> some View {
        MetricCardView(
            module: module,
            theme: theme,
            details: enabledMetrics(for: module),
            topMemoryProcesses: store.topMemoryProcesses,
            showMemoryProcesses: store.settings.showMemoryProcesses,
            topCPUProcesses: store.topCPUProcesses,
            showCPUProcesses: store.settings.showCPUProcesses,
            topDiskProcesses: store.topDiskProcesses,
            showDiskProcesses: store.settings.showDiskProcesses,
            topNetworkProcesses: store.topNetworkProcesses,
            showNetworkProcesses: store.settings.showNetworkProcesses
        )
        .equatable()
    }

    @ViewBuilder
    private func compactRow(for module: MonitorModule, theme: MonitorPanelTheme) -> some View {
        switch module.kind {
        case .cpu:
            MetricGlassRow(
                module: module,
                theme: theme,
                detail: module.summary,
                samples: module.samples,
                details: enabledMetrics(for: module),
                isExpanded: expandedKinds.contains(module.kind),
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
                isExpanded: expandedKinds.contains(module.kind)
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
                // 压力模式下传入压力历史,右侧即切换为曲线;使用率模式传空,保持占比进度条。
                samples: pressureMode ? module.pressureSamples : [],
                details: memoryMetrics(for: module, pressureMode: pressureMode),
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
                isExpanded: expandedKinds.contains(module.kind),
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
                isExpanded: expandedKinds.contains(module.kind),
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
                isExpanded: expandedKinds.contains(module.kind),
                showPowerFlow: store.settings.batteryShowPowerFlow,
                panelVisible: store.isPanelVisible
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
                isExpanded: expandedKinds.contains(module.kind),
                fans: module.fans
            ) {
                toggleExpansion(for: module.kind)
            }
            .equatable()
        case .bluetooth:
            BluetoothGlassRow(
                module: module,
                theme: theme,
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

    /// 内存头部主值的压力等级文案(已本地化)。
    private func memoryPressureText(for module: MonitorModule) -> String {
        let raw = module.metrics.first { $0.name == "pressure" }?.value ?? "--"
        return localizedMemoryPressure(raw)
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
    
    /// 参与展开/收起机制的列表行 kind 集合 = 可见 − 卡片(卡片常显,不参与展开)。
    private var listKinds: [MonitorKind] {
        visibleKinds.filter { !store.settings.cardStyleKinds.contains($0) }
    }
    
    /// 当前是否所有列表行都处于展开状态。
    /// 空集时为 false——没有行可展开,双击不应被视为「已全开」。
    private var allVisibleRowsExpanded: Bool {
        !listKinds.isEmpty
        && listKinds.allSatisfy { expandedKinds.contains($0) }
    }
    
    /// 残留 expandedKinds 里的不可见/卡片 kind 不影响判定;全展开分支用列表行集合覆盖,顺便清掉残留。
    private func toggleAllExpansion() {
        setExpansion {
            if allVisibleRowsExpanded {
                expandedKinds.removeAll()
            } else {
                expandedKinds = Set(listKinds)
            }
        }
    }
    
    /// 把展开状态重置为「各模块默认展开设置 ∩ 列表行」(卡片不参与,顺便清掉残留 kind)。
    /// 面板隐藏时直接赋值,不走 setExpansion——无需动画,也不置位窗口补间标记;
    /// 面板可见时(钉住面板开着改设置)走 setExpansion,与手动展开同一补间节奏。
    private func applyDefaultExpansion() {
        let target = store.settings.defaultExpandedKinds.intersection(listKinds)
        guard expandedKinds != target else { return }
        if store.isPanelVisible {
            setExpansion { expandedKinds = target }
        } else {
            expandedKinds = target
        }
    }

    /// 展开区的「布局高度」由 `CollapsibleDetail` 从 0 补间到自然高度(见其说明),
    /// 窗口层(`FluidPanelController`)用**完全相同**的时长与 easeInOut 曲线并行动画到同一
    /// 终值。外层 GeometryReader 只上报一次终值、无法逐帧跟随,只有两边同时同速才能
    /// 边框与内容一起伸缩。故此处必须用 `MonitorConstants.panelExpansionDuration` + easeInOut,
    /// 与窗口侧 `NSAnimationContext` 严格一致。
    private func setExpansion(_ mutate: () -> Void) {
        // 展开补间与浮层子窗口并存会引发布局抖动,展开前确保浮层已收起。
        QuickToolsStore.shared.popoverPresenter.dismiss()
        // 置位一次性动画标记:紧接着的首次内容尺寸上报会被窗口层消费、走补间;
        // 而展开后进程数据回来/定时刷新引起的尺寸变化不再置位,瞬时贴合,不与此次展开叠加。
        store.beginExpansionAnimation()
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            NSLog("[autotest] setExpansion click ts=%.3f", CACurrentMediaTime())
        }
        withAnimation(.easeInOut(duration: MonitorConstants.panelExpansionDuration)) {
            mutate()
        }
    }

    private func startTimeUpdateTask() {
        timeUpdateTask?.cancel()
        timeUpdateTask = Task {
            while !Task.isCancelled {
                timeString = panelTimeFormatter.string(from: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
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
    var fans: [FanInfo]? = nil
    var topCPUProcesses: [TopCPUProcess] = []
    var showCPUProcesses = true
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
            && lhs.samples == rhs.samples
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.topMemoryProcesses == rhs.topMemoryProcesses
            && lhs.showMemoryProcesses == rhs.showMemoryProcesses
            && lhs.topCPUProcesses == rhs.topCPUProcesses
            && lhs.showCPUProcesses == rhs.showCPUProcesses
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
                    .foregroundStyle(theme.valueText)
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

            CollapsibleDetail(isExpanded: isExpanded && detailAvailable) {
                Group {
                    if module.kind == .fan, let fans, !fans.isEmpty {
                        FanList(fans: fans, theme: theme)
                    } else if let storageVolumes {
                        StorageVolumeDetailList(volumes: storageVolumes, kind: module.kind, tint: tint, theme: theme)
                    } else {
                        VStack(spacing: 9) {
                            MetricDetailGrid(metrics: details, kind: module.kind, theme: theme)
                            // CPU / 内存采样恒返回 top 5,故展开时无条件挂载列表(数据未到
                            // 先用留白占位预留高度),使展开一次到位、数据到达后原位淡入,
                            // 不产生二次高度跳变。磁盘采样需采样间隔才有增量,可能为空,仍按需挂载。
                            // App Store 沙盒版无法采样他进程,整体隐藏 TOP 进程列表。
                            #if DIRECT_DISTRIBUTION
                            if module.kind == .memory, showMemoryProcesses {
                                MemoryProcessList(processes: topMemoryProcesses, theme: theme)
                            }
                            if module.kind == .cpu, showCPUProcesses {
                                CPUProcessList(processes: topCPUProcesses, theme: theme)
                            }
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
        .compatibleGlassEffect(tint: theme.rowGlassTint(for: module.kind), cornerRadius: MonitorConstants.rowCornerRadius)
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
}

// MARK: - Detail Grid

private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let kind: MonitorKind
    let theme: MonitorPanelTheme
    /// true=行内展开紧凑样式(小字体 + 28pt 缩进对齐图标列);false=方卡放大样式(大字体、无缩进)。
    var isCompact: Bool = true

    /// 需要占满整行的字段:长值(IP、启动时间)塞两列会撑破列宽或不可控换行;
    /// wifi-rssi 格结构性超宽(标签+信号条+数值+单位四件套,半格装不下);
    /// gateway-latency 是其语义配对,一并整行保持网络块纵列节奏。
    /// 命中项显式整行、排到网格末尾。
    private static let fullRowMetricIDs: Set<String> = [
        "ipv4", "ipv6", "public-ip", "uptime", "adapter", "wifi-ssid",
        "wifi-rssi", "gateway-latency"
    ]

    private var leadingInset: CGFloat { isCompact ? 28 : 0 }
    private var rowSpacing: CGFloat { isCompact ? MetricGridMetrics.rowSpacing : 11 }
    private var labelStyle: Font.TextStyle { isCompact ? .footnote : .subheadline }
    private var valueStyle: Font.TextStyle { isCompact ? .footnote : .title3 }

    private var shortMetrics: [MonitorMetric] {
        metrics.filter { !Self.fullRowMetricIDs.contains($0.name) }
    }

    private var fullRowMetrics: [MonitorMetric] {
        metrics.filter { Self.fullRowMetricIDs.contains($0.name) }
    }

    var body: some View {
        VStack(spacing: isCompact ? 7 : 11) {
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
                .minimumScaleFactor(isCompact ? 1 : 0.6)
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
            switch metric.numericValue ?? 0 {
            case ..<1:
                return theme.palette.severityTint(for: .calm)
            case ..<2:
                return theme.palette.severityTint(for: .warning)
            default:
                return theme.palette.severityTint(for: .critical)
            }
        }
        // S.M.A.R.T.:verified 绿、failing 红,与原型 good/crit 色对齐。
        if kind == .storage, metric.name == "smart" {
            return metric.value == "failing"
                ? theme.palette.severityTint(for: .critical)
                : theme.palette.severityTint(for: .calm)
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
/// 避免面板挂 "--" 噪音行;条件恢复后自动出现。列表行与卡片模式共用同一套规则。
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

            CollapsibleDetail(isExpanded: isExpanded && hasExpandableContent) {
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
        .compatibleGlassEffect(tint: theme.rowGlassTint(for: module.kind), cornerRadius: MonitorConstants.rowCornerRadius)
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
    var toggleExpansion: (() -> Void)?

    static func == (lhs: BatteryGlassRow, rhs: BatteryGlassRow) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.isExpanded == rhs.isExpanded
            && lhs.showPowerFlow == rhs.showPowerFlow
            && lhs.panelVisible == rhs.panelVisible
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

            CollapsibleDetail(isExpanded: canExpand && isExpanded) {
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
                            animate: isExpanded && showPowerFlow && panelVisible
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .compatibleGlassEffect(tint: theme.rowGlassTint(for: module.kind), cornerRadius: MonitorConstants.rowCornerRadius)
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
        // 充电限制只保留在功率流电池条的刻度线上,低电量模式只保留行头图标
        // 着色与功率流配色,明细收缩为四项。
        let names = ["health", "cycle-count", "temperature", "power-loss"]

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

private func localizedBatteryState(_ id: String) -> String {
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

/// 功率流图(冻结原型重制):上排适配器/系统双节点流式排布,下方全宽电池条
/// (填充=电量,刻度=充电限制),短 stub 垂直连到汇流点;导管粗细 ∝ 瓦数。
/// 节点走正常流式布局,连线按容器几何计算绘制,构造上不会重叠。
/// 数据全部来自 BatterySampler 的遥测指标(power-in / power / battery-flow / status),
/// 沙盒版同样可用。活跃导管用彗星式能量光轨表达流向:灼亮头部 + 渐隐长尾 +
/// 外发光三层叠加,速度/数量 ∝ 瓦数(仅展开且面板可见时挂载 TimelineView
/// 30fps 驱动,收起/隐藏即回到纯静态绘制)。
private struct PowerFlowDiagram: View {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    let tint: Color
    /// 流光动画门控:仅当行展开且面板可见时为 true。
    let animate: Bool

    private static let nodeWidth: CGFloat = 104
    private static let nodeHeight: CGFloat = 46
    private static let stubHeight: CGFloat = 16
    private static let barHeight: CGFloat = 38

    var body: some View {
        if systemWatts != nil {
            VStack(alignment: .leading, spacing: 7) {
                flowArea

                if let note = flowNoteText {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(isInsufficient ? theme.palette.severityTint(for: .critical) : theme.captionText)
                        .lineLimit(2)
                }
            }
            // 与明细网格同 28pt 缩进,分区标题与图内容左缘对齐。
            .padding(.leading, 28)
        }
    }

    // MARK: 流图区域(边在底层 Canvas,节点与电池条走正常流式布局)

    private var flowArea: some View {
        ZStack(alignment: .top) {
            // 流光动画仅在门控通过时挂载 TimelineView;收起/隐藏后回到纯静态 Canvas。
            if animate {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    Canvas { context, size in
                        drawEdges(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                Canvas { context, size in
                    drawEdges(&context, size: size, time: nil)
                }
            }

            VStack(spacing: Self.stubHeight) {
                HStack(spacing: 36) {
                    adapterNode
                    Spacer(minLength: 0)
                    systemNode
                }

                if hasBattery {
                    batteryBar
                }
            }
        }
        .frame(height: hasBattery ? Self.nodeHeight + Self.stubHeight + Self.barHeight : Self.nodeHeight)
    }

    // MARK: 连线

    /// 导管宽度 ∝ 瓦数(与原型一致:1.2 + √W × 0.62,封顶 6.5)。
    private func edgeWidth(_ watts: Double?) -> CGFloat {
        guard let watts, watts >= 0.05 else { return 1.2 }
        return min(6.5, 1.2 + sqrt(watts) * 0.62)
    }

    private func strokeSegment(
        _ context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color,
        width: CGFloat,
        dashed: Bool = false
    ) {
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        let style = dashed
            ? StrokeStyle(lineWidth: width, lineCap: .round, dash: [3, 4])
            : StrokeStyle(lineWidth: width, lineCap: .round)
        context.stroke(line, with: .color(color), style: style)
    }

    private func drawEdges(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval?) {
        let topY = Self.nodeHeight / 2
        let junction = CGPoint(x: size.width / 2, y: topY)
        let adapterRight = CGPoint(x: Self.nodeWidth, y: topY)
        let systemLeft = CGPoint(x: size.width - Self.nodeWidth, y: topY)

        // 无电池台式机:适配器 → 系统一条直通线,不渲染汇流点与 stub。
        if !hasBattery {
            strokeSegment(&context, from: adapterRight, to: systemLeft,
                          color: neutralEdge, width: edgeWidth(systemWatts))
            drawEnergyBeam(&context, from: adapterRight, to: systemLeft,
                           watts: systemWatts, color: edgeShimmer, head: neutralBeamHead,
                           width: edgeWidth(systemWatts), time: time)
            return
        }

        // S1 适配器 → 汇流点:未插电只留暗轨道。
        strokeSegment(&context, from: adapterRight, to: junction,
                      color: connected ? neutralEdge : faintEdge,
                      width: edgeWidth(connected ? powerInWatts : nil))
        drawEnergyBeam(&context, from: adapterRight, to: junction,
                       watts: connected ? powerInWatts : nil, color: edgeShimmer, head: neutralBeamHead,
                       width: edgeWidth(connected ? powerInWatts : nil), time: time)

        // S2 汇流点 → 系统:系统恒耗电,恒活跃。
        strokeSegment(&context, from: junction, to: systemLeft,
                      color: neutralEdge, width: edgeWidth(systemWatts))
        drawEnergyBeam(&context, from: junction, to: systemLeft,
                       watts: systemWatts, color: edgeShimmer, head: neutralBeamHead,
                       width: edgeWidth(systemWatts), time: time)

        // S3 汇流点 ↕ 电池 stub:充电绿色、放电琥珀(适配器不足时转红)、无流动虚线轨道。
        let stubEnd = CGPoint(x: junction.x, y: Self.nodeHeight + Self.stubHeight)
        switch flowDirection {
        case .charging:
            strokeSegment(&context, from: junction, to: stubEnd,
                          color: flowTint.opacity(0.75), width: edgeWidth(batteryMagnitude))
            drawEnergyBeam(&context, from: junction, to: stubEnd,
                           watts: batteryMagnitude, color: flowTint, head: .white,
                           width: edgeWidth(batteryMagnitude), time: time)
        case .discharging:
            let color = isInsufficient
                ? theme.palette.severityTint(for: .critical).opacity(0.8)
                : theme.palette.severityTint(for: .warning).opacity(0.75)
            strokeSegment(&context, from: stubEnd, to: junction,
                          color: color, width: edgeWidth(batteryMagnitude))
            // 放电路径按电池 → 汇流点方向声明,光轨行进方向即流向。
            drawEnergyBeam(&context, from: stubEnd, to: junction,
                           watts: batteryMagnitude, color: color, head: .white,
                           width: edgeWidth(batteryMagnitude), time: time)
        case .idle:
            strokeSegment(&context, from: junction, to: stubEnd,
                          color: faintEdge, width: 1.2, dashed: true)
        }

        // 汇流点圆点。
        let dot = Path(ellipseIn: CGRect(x: junction.x - 2.4, y: junction.y - 2.4, width: 4.8, height: 4.8))
        context.fill(dot, with: .color(neutralEdge))
    }

    /// 能量光轨(彗星):灼亮头部拖一条渐隐长尾沿导管行进——外发光(模糊宽描边)
    /// + 亮芯(细渐变描边)+ 头部星点三层叠加,质感对齐 Web 能量可视化的光轨
    /// 效果。速度/数量 ∝ 瓦数。time 为 nil(门控关闭)时不绘制。
    private func drawEnergyBeam(
        _ context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        watts: Double?,
        color: Color,
        head: Color,
        width: CGFloat,
        time: TimeInterval?
    ) {
        guard let time, let watts, watts >= 0.05 else { return }
        let cycle = max(1.4, min(3.4, 4.2 / (1 + watts / 25)))
        let beams = watts > 30 ? 2 : 1
        let tail: CGFloat = 0.45
        for k in 0..<beams {
            let phase = CGFloat((time / cycle + Double(k) / Double(beams)).truncatingRemainder(dividingBy: 1))
            let headPos = phase * (1 + tail * 2) - tail
            let tailPos = headPos - tail
            guard headPos > 0, tailPos < 1 else { continue }
            var beam = Path()
            beam.move(to: lerp(from, to, max(0, tailPos)))
            beam.addLine(to: lerp(from, to, min(1, headPos)))
            // 渐变端点取未裁剪的带头带尾,光轨形状在滑入滑出过程中保持稳定。
            let g0 = lerp(from, to, tailPos)
            let g1 = lerp(from, to, headPos)

            // 外发光层:宽幅模糊低透明度,形成霓虹光晕。
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.4))
                layer.stroke(
                    beam,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0), color.opacity(0.4), color.opacity(0.7)]),
                        startPoint: g0,
                        endPoint: g1
                    ),
                    style: StrokeStyle(lineWidth: width + 2.6, lineCap: .round)
                )
            }

            // 亮芯层:更细更亮,向头部渐次逼近白热。
            context.stroke(
                beam,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.55), head.opacity(0.95)]),
                    startPoint: g0,
                    endPoint: g1
                ),
                style: StrokeStyle(lineWidth: max(1.4, width * 0.6), lineCap: .round)
            )

            // 头部星点:行进前沿的一点亮斑。
            if headPos <= 1 {
                let hp = lerp(from, to, headPos)
                let r = max(1.6, width * 0.42)
                context.fill(
                    Path(ellipseIn: CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)),
                    with: .color(head.opacity(0.95))
                )
            }
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    // MARK: 节点

    private var adapterNode: some View {
        VStack(spacing: 1) {
            Text(adapterLabel)
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(adapterValueText)
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
            adapterLoadBar
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.trackFill))
        .opacity(connected ? 1 : 0.4)
    }

    /// 适配器额定负载率细条:实际输入 / 额定瓦数。逼近上限逐级告警色,
    /// 直观预警「适配器不足」场景;未插电时隐藏。
    private var adapterLoadBar: some View {
        let load: Double = {
            guard let powerInWatts, let rated = numericValue("adapter"), rated > 0 else { return 0 }
            return min(1, powerInWatts / rated)
        }()
        let fillColor: Color = if load > 0.92 {
            theme.palette.severityTint(for: .critical)
        } else if load > 0.75 {
            theme.palette.severityTint(for: .warning)
        } else {
            isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
        }
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(isDark ? 0.10 : 0.08))
            RoundedRectangle(cornerRadius: 2)
                .fill(fillColor)
                .frame(width: load * (Self.nodeWidth - 28))
        }
        .frame(height: 2.5)
        .padding(.horizontal, 10)
        .opacity(connected ? 1 : 0)
    }

    private var systemNode: some View {
        VStack(spacing: 1) {
            Text(String(localized: "panel.power-flow.system"))
                .monitorPanelCaptionFont(.caption2)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
            Text(wattString(systemWatts))
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(width: Self.nodeWidth, height: Self.nodeHeight)
        .background(RoundedRectangle(cornerRadius: 9).fill(theme.trackFill))
    }

    // MARK: 全宽电池条

    /// 电池从「节点」升级为「全宽容器」:填充 = 电量百分比,白色刻度 = 系统充电限制;
    /// 左侧电量+状态、右侧 ETA 走 flex 两端对齐,文字永不碰撞。任何电源状态
    /// (含插电直供)都承载信息,不再出现「下半图空白」。
    private var batteryBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(barFillGradient)
                    .frame(width: max(0, CGFloat(module.value) / 100 * geo.size.width - 4),
                           height: geo.size.height - 4)
                    .offset(x: 2, y: 2)

                if let limit = numericValue("charge-limit"), limit < 100 {
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.35))
                        .frame(width: 2, height: geo.size.height - 4)
                        .offset(x: geo.size.width * CGFloat(limit) / 100 - 1, y: 2)
                }

                HStack(spacing: 6) {
                    Text(percent(module.value))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(barTextPrimary)
                    Text(barStatusText)
                        .font(.system(size: 10))
                        .foregroundStyle(barTextSecondary)
                    Spacer(minLength: 8)
                    if let eta = barEtaText {
                        Text(eta)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(barTextSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity)
                // 深色模式填充上的白字需要轻投影保可读性;浅色模式用深字不投影。
                .shadow(color: .black.opacity(isDark ? 0.45 : 0), radius: 2, x: 0, y: 1)
            }
        }
        .frame(height: Self.barHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.trackFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(barBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var barFillGradient: LinearGradient {
        if isInsufficient {
            return LinearGradient(
                colors: [
                    theme.palette.severityTint(for: .critical).opacity(0.45),
                    theme.palette.severityTint(for: .warning).opacity(0.28)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [flowTint.opacity(0.60), flowTint.opacity(0.28)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var barBorder: Color {
        if isCharging { return flowTint.opacity(0.45) }
        if isInsufficient { return theme.palette.severityTint(for: .critical).opacity(0.5) }
        return .clear
    }

    private var barTextPrimary: Color {
        isDark ? .white : Color.black.opacity(0.78)
    }

    private var barTextSecondary: Color {
        isDark ? Color.white.opacity(0.78) : Color.black.opacity(0.60)
    }

    private var barStatusText: String {
        switch status {
        case "charging": return localizedBatteryState("charging")
        case "on-battery": return localizedBatteryState("on-battery")
        case "maintain":
            // 适配器不足是 maintain 的告警子态(输入顶到额定仍放电补差),优先展示。
            return isInsufficient
                ? String(localized: "battery-state.insufficient")
                : localizedBatteryState("maintain")
        default:
            return localizedBatteryState("ac-power")
        }
    }

    private var barEtaText: String? {
        if let eta = etaText { return eta }
        // 真直供且无 ETA(已充满/达充电限制):展示「直供」状态语,条内信息不断档。
        if status == "ac-power" {
            return String(localized: "panel.power-flow.direct-supply")
        }
        return nil
    }

    // MARK: 说明与迷你曲线

    /// 图下说明行:只在需要警示的「适配器不足」场景出现;常规态(充电/直供/
    /// 电池供电/无电池)的瓦数、损耗、ETA 已分别在节点、明细网格与电池条内
    /// 展示,不再重复拼长句。
    private var flowNoteText: String? {
        guard connected, hasBattery, isInsufficient else { return nil }
        let magnitude = String(format: "%.1fW", batteryMagnitude)
        return String(format: String(localized: "panel.power-flow.note.insufficient"), magnitude)
    }

    // MARK: 数据

    private var isDark: Bool {
        theme.palette.colorScheme == .dark
    }

    private var hasBattery: Bool {
        rawValue("type") == "battery"
    }

    private var status: String {
        rawValue("status")
    }

    private var connected: Bool {
        status == "charging" || status == "ac-power" || status == "maintain"
    }

    private var systemWatts: Double? {
        numericValue("power")
    }

    private var powerInWatts: Double? {
        numericValue("power-in")
    }

    /// 电池流向方向,只依据 IOPS 的充电/连接状态判定(status 由 BatterySampler
    /// 依据 kIOPSIsChargingKey / kIOPSPowerSourceStateKey 产出):BatteryPower 的
    /// 符号约定随机型/系统版本不同,不作为方向依据。
    private enum FlowDirection { case charging, discharging, idle }

    private var flowDirection: FlowDirection {
        switch status {
        case "charging": return .charging
        case "on-battery", "maintain": return .discharging
        default: return .idle // ac-power:插电且不充电(如满电)
        }
    }

    private var isCharging: Bool { flowDirection == .charging }

    /// 适配器不足:电池放电补差,且适配器输入已逼近额定瓦数(弱适配器带高负载)。
    /// 充电上限维持等策略性放电同样伴随电池放电,但其输入接近零(系统主动
    /// 断输入),与真正的适配器供电不足区分。
    private var isInsufficient: Bool {
        guard connected, (numericValue("battery-flow") ?? 0) < -0.05,
              let powerIn = powerInWatts, let rated = numericValue("adapter"), rated > 0 else {
            return false
        }
        return powerIn / rated > 0.85
    }

    /// 电池流向功率幅度(恒非负)。放电时若遥测尚未刷新(拔电瞬间为 0),用系统
    /// 负载兜底——脱离适配器后系统功耗全部由电池提供。idle 态电池静止。
    private var batteryMagnitude: Double {
        let flow = abs(numericValue("battery-flow") ?? 0)
        switch flowDirection {
        case .discharging: return flow >= 0.05 ? flow : (systemWatts ?? 0)
        case .charging: return flow
        case .idle: return 0
        }
    }

    private var adapterLabel: String {
        let base = String(localized: "panel.power-flow.adapter")
        let rated = rawValue("adapter")
        return rated == "--" ? base : "\(base) · \(rated)"
    }

    /// 适配器节点数值:未插电显「—」;插电但 SystemPowerIn 尚未由固件填出(USB-C PD
    /// 协商/遥测预热窗口)显「采集中」,而非空白或 0——如实表达「已连接、读数在路上」。
    private var adapterValueText: String {
        guard connected else { return "—" }
        if let powerInWatts { return wattString(powerInWatts) }
        return String(localized: "panel.power-flow.collecting")
    }

    private var etaText: String? {
        guard let minutes = numericValue("time-remaining").map(Int.init), minutes > 0 else { return nil }
        let text = Self.durationFormatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
        if status == "charging" {
            return String(format: String(localized: "panel.power-flow.eta-full"), text)
        }
        if status == "on-battery" {
            return String(format: String(localized: "panel.power-flow.eta-empty"), text)
        }
        return nil
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: 配色

    /// 低电量模式:除行头图标外,功率流同步转琥珀——电池条填充/边框、充电
    /// stub、sparkline 全部换警示色,系统限电状态在图内直接可读。
    private var isLowPowerMode: Bool {
        hasBattery && rawValue("low-power-mode") == "on"
    }

    /// 功率流有效主题色:低电量模式时覆盖为 warning 琥珀;适配器不足的红色
    /// 判定优先级更高(在 barFillGradient/barBorder 内先于本值返回)。
    private var flowTint: Color {
        isLowPowerMode ? theme.palette.severityTint(for: .warning) : tint
    }

    private var neutralEdge: Color {
        isDark ? Color.white.opacity(0.36) : Color.black.opacity(0.30)
    }

    /// 中性导管上的流动亮色:比导管底色亮一档,流动可辨但不张扬。
    private var edgeShimmer: Color {
        isDark ? Color.white.opacity(0.6) : Color.black.opacity(0.4)
    }

    /// 中性导管光轨头部:暗色底亮白、浅色底深色,与导管语言一致;
    /// 语义导管(充电/放电)头部直接用白点,像火花。
    private var neutralBeamHead: Color {
        isDark ? .white : Color.black.opacity(0.6)
    }

    private var faintEdge: Color {
        isDark ? Color(hex: 0x7A91B4).opacity(0.16) : Color.black.opacity(0.10)
    }

    private func rawValue(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }

    private func numericValue(_ name: String) -> Double? {
        module.metrics.first { $0.name == name }?.numericValue
    }
}

private func localizedNetworkInterface(_ summary: String) -> String {
    let key = "network-interface.\(summary)"
    let localized = String(localized: String.LocalizationValue(key))
    return localized == key ? summary : localized
}

// MARK: - Metric Card

/// 大卡片:显示方式设为「大卡片」的模块的常显形态(hero 主值 + 指标网格 + TOP 进程)。
/// 无任何手势/按钮——显示方式是静态配置,面板内交互仍只有列表行的点击展开一层。
/// 源自已弃用的悬停放大方案(61febc61),剥离了浮标/还原按钮与 enlargedKinds 交互态。
private struct MetricCardView: View, Equatable {
    let module: MonitorModule
    let theme: MonitorPanelTheme
    var details: [MonitorMetric] = []
    var topMemoryProcesses: [TopMemoryProcess] = []
    var showMemoryProcesses = false
    var topCPUProcesses: [TopCPUProcess] = []
    var showCPUProcesses = false
    var topDiskProcesses: [TopDiskProcess] = []
    var showDiskProcesses = false
    var topNetworkProcesses: [TopNetworkProcess] = []
    var showNetworkProcesses = false

    // theme 完全由 (preference, colorScheme) 决定(见 ThemeCache),故只比这两个键字段。
    static func == (lhs: MetricCardView, rhs: MetricCardView) -> Bool {
        lhs.module == rhs.module
            && lhs.theme.palette.preference == rhs.theme.palette.preference
            && lhs.theme.palette.colorScheme == rhs.theme.palette.colorScheme
            && lhs.details == rhs.details
            && lhs.topMemoryProcesses == rhs.topMemoryProcesses
            && lhs.showMemoryProcesses == rhs.showMemoryProcesses
            && lhs.topCPUProcesses == rhs.topCPUProcesses
            && lhs.showCPUProcesses == rhs.showCPUProcesses
            && lhs.topDiskProcesses == rhs.topDiskProcesses
            && lhs.showDiskProcesses == rhs.showDiskProcesses
            && lhs.topNetworkProcesses == rhs.topNetworkProcesses
            && lhs.showNetworkProcesses == rhs.showNetworkProcesses
    }

    private var tint: Color {
        theme.moduleTint(for: module.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hero
            if !details.isEmpty {
                // 网络卡片明细走与列表行同一套门控(断网/有线/无 Wi-Fi 时
                // 不渲染 "--" 行,见 filteredNetworkMetrics);其余模块原样展示。
                if module.kind == .network {
                    let visible = filteredNetworkMetrics(details, summary: module.summary)
                    if !visible.isEmpty {
                        MetricDetailGrid(metrics: visible, kind: module.kind, theme: theme, isCompact: false)
                    }
                } else {
                    MetricDetailGrid(metrics: details, kind: module.kind, theme: theme, isCompact: false)
                }
            }
            if let section = processSection {
                CardProcessList(
                    items: section.items,
                    metricColumns: section.columns,
                    separator: theme.rowSeparator(for: module.kind),
                    theme: theme
                )
            }
        }
        .padding(16)
        // 高度随内容自适应:内容多(CPU/内存带图表+进程)则高,内容少(电源/网络)则矮,
        // 不强制方形以免底部大片留白;同时避免自测宽度回写高度与窗口跟随动画相互干扰。
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .compatibleGlassEffect(tint: theme.rowGlassTint(for: module.kind), cornerRadius: MonitorConstants.rowCornerRadius)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: module.kind.symbol)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)

            Text(module.kind.title)
                .font(.headline)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch module.kind {
        case .cpu, .gpu:
            HStack(alignment: .center, spacing: 12) {
                bigValue(percentText)
                SparklineChart(samples: module.samples, tint: tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            }
        case .memory, .storage:
            VStack(alignment: .leading, spacing: 12) {
                bigValue(percentText)
                ProgressMeter(value: module.value, tint: tint, theme: theme)
                    .frame(height: 10)
            }
        case .network:
            VStack(alignment: .leading, spacing: 14) {
                Text(localizedNetworkInterface(module.summary))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.valueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 22) {
                    cardRate(symbol: "arrow.down", value: metricValue("download"))
                    cardRate(symbol: "arrow.up", value: metricValue("upload"))
                }
            }
        case .battery:
            VStack(alignment: .leading, spacing: 10) {
                bigValue(hasBattery ? percentText : metricValue("power"))
                if hasBattery {
                    cardRate(symbol: "powermeter", value: metricValue("power"))
                }
            }
        case .fan:
            // 风扇大卡片:大数字 max RPM + sparkline
            // Y 轴用风扇硬件 min~max 归一化,与列表行 sparkline 保持一致。
            VStack(alignment: .leading, spacing: 12) {
                bigValue(percentText)
                let fanMin = Double(module.fans?.map(\.minRPM).min() ?? 0)
                let fanMax = Double(module.fans?.map(\.maxRPM).max() ?? 100)
                SparklineChart(samples: module.samples, tint: tint, minValue: fanMin, maxValue: fanMax)
                    .frame(height: 36)
            }
        case .bluetooth:
            // 蓝牙不提供卡片样式(设置侧已门控),此处仅为穷尽分支兜底:
            // 渲染设备数与展开区同款设备列表。
            VStack(alignment: .leading, spacing: 12) {
                bigValue(module.summary)
                BluetoothDeviceList(devices: module.bluetoothDevices ?? [], theme: theme)
            }
        }
    }

    private func bigValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 46, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(theme.valueText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func cardRate(symbol: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.callout.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .monitorPanelMonoFont(.title3, weight: .semibold)
                .foregroundStyle(theme.valueText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 按当前模块类型返回已开启的 top 进程小节(items + 数值列数):未开启时返回 nil。
    /// 四类列表统一固定 5 行位置:真实数据从上往下填,空位由 CardProcessList 统一补“—”占位。
    private var processSection: (items: [CardProcessItem], columns: Int)? {
        #if !DIRECT_DISTRIBUTION
        // App Store 沙盒版无法采样他进程,大卡片不渲染 TOP 进程小节。
        return nil
        #else
        switch module.kind {
        case .cpu:
            guard showCPUProcesses else { return nil }
            let items = topCPUProcesses.enumerated().map { index, proc in
                CardProcessItem(id: index, icon: proc.icon, name: proc.name, metrics: [
                    CardProcessMetric(symbol: nil, text: String(format: "%.1f%%", proc.cpuUsage))
                ])
            }
            return (items, 1)
        case .memory:
            guard showMemoryProcesses else { return nil }
            let items = topMemoryProcesses.enumerated().map { index, proc in
                CardProcessItem(id: index, icon: proc.icon, name: proc.name, metrics: [
                    CardProcessMetric(symbol: nil, text: byteCountString(Int64(proc.memoryUsage), countStyle: .memory))
                ])
            }
            return (items, 1)
        case .storage:
            guard showDiskProcesses else { return nil }
            let items = topDiskProcesses.enumerated().map { index, proc in
                CardProcessItem(id: index, icon: proc.icon, name: proc.name, metrics: [
                    CardProcessMetric(symbol: "↑", text: byteCountString(Int64(proc.bytesWritten))),
                    CardProcessMetric(symbol: "↓", text: byteCountString(Int64(proc.bytesRead)))
                ])
            }
            return (items, 2)
        case .network:
            guard showNetworkProcesses else { return nil }
            let items = topNetworkProcesses.enumerated().map { index, proc in
                CardProcessItem(id: index, icon: proc.icon, name: proc.name, metrics: [
                    CardProcessMetric(symbol: "↑", text: bytesPerSecond(Double(proc.upload))),
                    CardProcessMetric(symbol: "↓", text: bytesPerSecond(Double(proc.download)))
                ])
            }
            return (items, 2)
        case .gpu, .battery, .fan, .bluetooth:
            // 风扇/蓝牙大卡片无 TOP 进程小节
            return nil
        }
        #endif
    }

    private var percentText: String {
        "\(Int(module.value.rounded()))%"
    }

    /// 当前模块是否为真电池(非台式机外接电源):决定大卡英雄区显示电量百分比还是直接显功耗。
    private var hasBattery: Bool {
        module.metrics.first { $0.name == "type" }?.value == "battery"
    }

    private func metricValue(_ name: String) -> String {
        module.metrics.first { $0.name == name }?.value ?? "--"
    }
}

// MARK: - Card Process List

private struct CardProcessMetric {
    let symbol: String?
    let text: String
}

private struct CardProcessItem: Identifiable {
    let id: Int
    let icon: NSImage?
    let name: String
    let metrics: [CardProcessMetric]
    var isPlaceholder = false
}

/// 方卡专用的 top 进程列表:与行内版统一取自同一数据,但图标/字体更大、不再缩进 28pt,
/// 与卡片内其他内容左对齐。单值(CPU/内存)只显一列,双值(磁盘/网络)显↑/↓两列。
/// 固定 5 行:真实数据从上往下填,空位显“—”占位,高度永远不变、无加载跳变。
private struct CardProcessList: View {
    let items: [CardProcessItem]
    var metricColumns: Int = 1
    let separator: Color
    let theme: MonitorPanelTheme

    private static let rowCount = 5

    private var placeholderItem: CardProcessItem {
        CardProcessItem(
            id: -1,
            icon: nil,
            name: "—",
            metrics: Array(repeating: CardProcessMetric(symbol: nil, text: "—"), count: max(1, metricColumns)),
            isPlaceholder: true
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(separator)
                .frame(height: 1)

            VStack(spacing: 8) {
                // 按下标固定 5 个槽位:每个槽位要么真实行、要么“—”占位,数据到达为同槽位内容替换,
                // 高度恒定、不触发窗口二次动画。
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    row(for: index < items.count ? items[index] : placeholderItem)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: items.count)
        }
    }

    private func row(for item: CardProcessItem) -> some View {
        HStack(spacing: 9) {
            if item.isPlaceholder {
                Color.clear
                    .frame(width: 20, height: 20)
            } else {
                ProcessIcon(icon: item.icon, theme: theme)
                    .frame(width: 20, height: 20)
            }

            Text(item.name)
                .monitorPanelCaptionFont(.subheadline)
                .foregroundStyle(item.isPlaceholder ? theme.secondaryText.opacity(0.5) : theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            HStack(spacing: 12) {
                ForEach(Array(item.metrics.enumerated()), id: \.offset) { _, metric in
                    HStack(spacing: 3) {
                        if let symbol = metric.symbol {
                            Text(symbol)
                                .monitorPanelMonoFont(.footnote, weight: .medium)
                        }
                        Text(metric.text)
                            .monitorPanelMonoFont(.footnote, weight: .semibold)
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                }
            }
            .foregroundStyle(item.isPlaceholder ? theme.secondaryText.opacity(0.5) : theme.secondaryText)
            .layoutPriority(1)
        }
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

// MARK: - Top Memory Processes

private struct MemoryProcessList: View {
    let processes: [TopMemoryProcess]
    let theme: MonitorPanelTheme

    /// 固定展示 top 5 个位置:真实数据从上往下填,空位显“—”占位。
    private static let rowCount = 5

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .memory))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    if index < processes.count {
                        let proc = processes[index]
                        HStack(spacing: 6) {
                            ProcessIcon(icon: proc.icon, theme: theme)
                                .frame(width: 16, height: 16)

                            Text(proc.name)
                                .monitorPanelCaptionFont(.footnote)
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 4)

                            Text(byteCountString(Int64(proc.memoryUsage), countStyle: .memory))
                                .monitorPanelMonoFont(.caption2, weight: .medium)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                    } else {
                        ProcessPlaceholderRow(theme: theme)
                    }
                }
            }
            .padding(.leading, 28)
            .animation(.easeInOut(duration: 0.2), value: processes.count)
        }
    }
}

// MARK: - Top CPU Processes

private struct CPUProcessList: View {
    let processes: [TopCPUProcess]
    let theme: MonitorPanelTheme

    /// 固定展示 top 5 个位置:真实数据从上往下填,空位显“—”占位。
    private static let rowCount = 5

    var body: some View {
        let translatedCount = processes.filter(\.translated).count

        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .cpu))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(0 ..< Self.rowCount, id: \.self) { index in
                    if index < processes.count {
                        let proc = processes[index]
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

                            Text(String(format: "%.1f%%", proc.cpuUsage))
                                .monitorPanelMonoFont(.caption2, weight: .medium)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                    } else {
                        ProcessPlaceholderRow(theme: theme)
                    }
                }
            }
            .padding(.leading, 28)
            .animation(.easeInOut(duration: 0.2), value: processes.count)

            // 转译进程汇总横幅:列表存在转译进程时才出现。
            if translatedCount > 0 {
                RosettaBanner(count: translatedCount, theme: theme)
                    .padding(.leading, 28)
            }
        }
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

            CollapsibleDetail(isExpanded: isExpanded && !devices.isEmpty) {
                BluetoothDeviceList(devices: devices, theme: theme)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
        }
        .compatibleGlassEffect(tint: theme.rowGlassTint(for: module.kind), cornerRadius: MonitorConstants.rowCornerRadius)
    }
}

/// 蓝牙展开区设备列表:类型图标 + 名称 + 电量条 + 百分比。
/// 未上报电量的设备(厂商私有协议,系统本身收不到)只显示「已连接」,不伪造读数。
private struct BluetoothDeviceList: View {
    let devices: [BluetoothDeviceInfo]
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(theme.rowSeparator(for: .bluetooth))
                .frame(height: 1)
                .padding(.leading, 28)

            VStack(spacing: 4) {
                ForEach(devices) { device in
                    deviceRow(device)
                }
            }
            .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private func deviceRow(_ device: BluetoothDeviceInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: device.type.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 14)

            Text(device.name)
                .monitorPanelMetricLabelFont()
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let level = device.batteryLevel {
                BluetoothBatteryBar(level: level, tint: batteryColor(level), theme: theme)
                    .frame(width: 44, height: 4)
                Text("\(level)%")
                    .monitorPanelMonoFont(.callout, weight: .semibold)
                    .foregroundStyle(batteryColor(level))
                    .lineLimit(1)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            // 无电量设备右侧留空:列表本身即「已连接」清单,重复标注无信息量
            //(厂商私有协议设备系统读不到电量,不伪造读数)。
        }
    }

    /// 电量条/读数颜色:低电区间走 severity 色,正常区间绿色呼应电池语义。
    private func batteryColor(_ level: Int) -> Color {
        if Double(level) <= MonitorConstants.batteryCriticalThreshold {
            return theme.palette.severityTint(for: .critical)
        }
        if Double(level) <= MonitorConstants.batteryWarningThreshold {
            return theme.palette.severityTint(for: .warning)
        }
        return theme.palette.severityTint(for: .calm)
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
/// 不能用 scale / opacity 这类「渲染层变换」做展开:它们不改变布局占位——展开区一插入就
/// 按完整高度占位,容器(进而窗口)高度会「瞬间」跳到终点,随后内容才在已定型的空间里
/// 淡入/缩放,肉眼看到「边框先到位、内容再补上」的错位闪烁;收起时镜像反过来。
///
/// 实现:内容常驻(以测出自然高度),再把「布局高度」本身从 0 补间到自然高度并裁剪。
/// 这样容器高度随动画逐帧真实增长,`FluidPanelSizeReader` 的 GeometryReader 得以逐帧
/// 上报中间高度,`FluidPanelController` 的窗口层随之逐帧跟随——内外一起展开/收起。
///
/// 供各 metric 行与 `DisplayControlsSection`(Direct 目标)共用,故非 private。
struct CollapsibleDetail<Content: View>: View {
    private let isExpanded: Bool
    private let content: Content

    /// 内容的自然高度。内容始终挂载并被 GeometryReader 测量,故在首次展开前就已就绪,
    /// 保证 `withAnimation` 能从 0 补间到该高度,而不是等测量回填后「跳」到终点。
    @State private var contentHeight: CGFloat = 0

    init(isExpanded: Bool, @ViewBuilder content: () -> Content) {
        self.isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { contentHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, newValue in
                            contentHeight = newValue
                        }
                }
            )
            // 折叠时钳到 0 高度;顶部对齐 + 裁剪,使内容随高度增长自上而下「卷出」。
            .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
            // 展开状态下内容自身高度变化(如风扇模式切换插入滑杆/曲线)平滑过渡,
            // 而非无动画瞬跳;折叠态的高度变化不可见,不受影响。展开/收起仍由
            // 调用方的 withAnimation(isExpanded)驱动,与本动画互不干扰。
            .animation(.easeInOut(duration: 0.18), value: contentHeight)
            // 折叠状态(高度 0、不可见)不参与点击,避免拦截行的展开手势。
            .allowsHitTesting(isExpanded)
    }
}
