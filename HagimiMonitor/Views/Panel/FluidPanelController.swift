import AppKit
import Combine
import SwiftUI

/// 自建的菜单栏面板控制器,替换系统 `MenuBarExtra(.window)`。
///
/// 背景:SwiftUI 的 `MenuBarExtra(.window)` 在 macOS 15 及更早版本对宿主窗口的
/// resize 实现很差——内容高度变化时系统会整窗重绘,导致展开子项时面板连同顶部
/// SYSTEM·LIVE 一起闪烁、像被重新加载;Apple 直到 macOS 26 才改进。为在 15 上
/// 同时拿到「不闪」和「平滑展开动画」,这里借鉴 FluidMenuBarExtra 的思路,自建
/// `NSPanel` 承载面板内容,由 AppKit 的 `setFrame(display:animate:)` 驱动高度动画:
/// 窗口原生动画 resize 不会 rebuild SwiftUI 视图树,因此不闪;顶边锚定在菜单栏
/// 下沿,只向下增长。
///
/// 动画分工(关键):内容尺寸由 SwiftUI 瞬时上报(不加 `withAnimation`),平滑
/// 的高度补间完全交给窗口层的 `animate: true`。这正好避开上一轮「SwiftUI 几何
/// 动画 + 窗口 resize 抢锚点」导致的顶部抖动。
///
/// 动态图标:把 `MenuBarStatusLabel` 用 `ImageRenderer` 快照成 `NSImage` 赋给标准
/// `NSStatusItem.button.image`(负载/采样变化时重刷)。走标准图路径而非子视图,是为了
/// 让系统对「非活跃屏幕」自动变淡(与原生 app 一致);子视图路径拿不到逐屏 dimming。
@MainActor
final class FluidPanelController: NSObject, NSWindowDelegate {
    private let store: MonitorStore
    /// 打开设置窗口的闭包。由外部注入,因为 `OpenSettingsAction` 只能在 SwiftUI 视图层获取。
    private let openSettingsAction: () -> Void

    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private var hostingView: NSHostingView<AnyView>?

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    /// 指标(文本)模式下,上一次成功栅格化所用的关键输入。$modules 每秒发布(网络字节
    /// 几乎每秒都变),但格式化后的菜单栏指标文本往往不变;文字/外观/布局/scale 全等时
    /// 据此跳过 ImageRenderer 快照,消除「指标模式每秒重绘」这一常驻 CPU 热点。
    private struct MetricsRenderKey: Equatable {
        let items: [MenuBarMetricItem]
        let isDark: Bool
        let layout: MenuBarMetricLayoutStyle
        let scale: CGFloat
    }
    private var lastMetricsRenderKey: MetricsRenderKey?

    /// 面板与菜单栏按钮左边缘对齐时,补偿窗口阴影/边框带来的 2pt 偏移。
    private static let windowBorderSize: CGFloat = 2

    /// 面板圆角半径。由 window 层的 NSVisualEffectView / hosting layer 裁剪,
    /// 恢复系统 popover 般的圆角外观(自建 borderless 窗口默认是方角)。
    private static let panelCornerRadius: CGFloat = 12

    /// 状态项内容左右留白,避免图标/文字贴住菜单栏边缘(系统 MenuBarExtra 自带此留白)。
    private static let statusItemHorizontalPadding: CGFloat = 2

    init(
        store: MonitorStore,
        openSettings: @escaping () -> Void
    ) {
        self.store = store
        self.openSettingsAction = openSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: MonitorConstants.panelIdealWidth, height: 200),
            // 对齐 FluidMenuBarExtra:保留 `.titled` 让 `setFrame(display:animate:)` 的
            // 高度动画可靠生效(borderless 窗口上 animate 常被忽略),再用
            // `.fullSizeContentView` + 隐藏标题栏做出无边框外观。
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureStatusItem()
        installEventMonitors()
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        // 隐藏标题栏,做出无边框外观(保留 `.titled` 的窗口行为)。
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // contentView 用 popover 毛玻璃:提供圆角遮罩 + 通透底(对齐 FluidMenuBarExtra)。
        // 这是恢复系统 popover 般外观的关键——实现者此前直接用透明 hosting 作 contentView,
        // 丢了圆角与毛玻璃底,面板才变成方盒子。
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.panelCornerRadius
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        // 面板内容:MonitorPanelView 通过自定义环境键获取 openSettings 闭包。
        let root = MonitorPanelView(store: store)
            .environment(\.fluidOpenSettings, OpenSettingsActionKey.Action(openSettingsAction))
            .modifier(FluidPanelSizeReader { [weak self] size in
                self?.contentSizeDidChange(to: size)
            })

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // hosting 也做圆角裁剪,否则 SwiftUI 内容(含 panelBackgroundColor 矩形)方角会溢出圆角。
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.panelCornerRadius
        hosting.layer?.masksToBounds = true
        visualEffect.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        hostingView = hosting

        // 用内容固有尺寸初始化窗口大小(对齐 FluidMenuBarExtra)。避免首帧为默认 200 高。
        hosting.layoutSubtreeIfNeeded()
        let intrinsic = hosting.intrinsicContentSize
        if intrinsic.width > 1, intrinsic.height > 1 {
            panel.setContentSize(intrinsic)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        // 关键:图标走标准的 `button.image` 路径(而非往 button 塞 NSHostingView 子视图)。
        // 只有标准状态项图会被菜单栏系统跨屏复制并在「非活跃屏幕」自动变淡,与原生 app
        // 一致;自建子视图拿不到这个逐屏 dimming(表现为非活跃屏幕全亮)。动态内容(负载
        // 环/可变宽指标文本)通过 ImageRenderer 每次快照渲染成 NSImage 再赋给 button.image。
        button.imagePosition = .imageOnly
        button.image = nil
        button.setAccessibilityTitle("HagimiMonitor")

        refreshStatusItemImage()

        // 负载环随 displayedComputeLoad 平滑变化(30fps);指标文本随 modules 采样变化。
        // 指标模式下 displayedComputeLoad 根本不参与渲染,过滤掉这个模式下的 30fps
        // tick,避免白白触发 ImageRenderer 快照(见 refreshStatusItemImage 指标分支)。
        store.loadAnimator.$displayedComputeLoad
            .sink { [weak self] _ in
                guard let self else { return }
                switch self.store.settings.menuBarDisplayMode {
                case .ring:
                    self.refreshStatusItemImage()
                case .metrics:
                    break
                }
            }
            .store(in: &cancellables)
        // $modules 每秒发布(网络字节几乎每秒都变)。这里不做去重:环模式的负载等级颜色
        // (idle/working/busy/stressed)由 haloRingLoadLevel 决定,而 loadAnimator 仅在负载
        // 变化≥阈值时才驱动刷新,若小幅漂移跨越等级边界会漏刷环色;故环模式仍需 $modules
        // 每秒兜底刷新。真正昂贵的指标模式 ImageRenderer 快照已由 refreshStatusItemImage
        // 内部的 MetricsRenderKey 去重挡下,故此处每秒触发的实际开销极低(环模式命中缓存图)。
        store.$modules
            .sink { [weak self] _ in self?.refreshStatusItemImage() }
            .store(in: &cancellables)

        // 显示模式(环/指标)切换。
        store.settings.$menuBarDisplayMode
            .sink { [weak self] _ in self?.refreshStatusItemImage() }
            .store(in: &cancellables)

        // 主题切换:重新快照(SwiftUI 内部不感知 NSStatusItem 的 appearance)。
        store.settings.$themePreference
            .sink { [weak self] _ in self?.refreshStatusItemImage() }
            .store(in: &cancellables)

        // 关键:直接监听 button 自身的 effectiveAppearance。焦点切换 / 壁纸变化 /
        // 菜单栏黑白模式翻转时,这个值会「即刻」更新——比等下一个采样 tick(~1s)
        // 快得多,图标墨色随焦点迅速跟随。option(.initial) 顺带完成首刷。
        button.publisher(for: \.effectiveAppearance, options: [.new])
            .sink { [weak self] _ in self?.refreshStatusItemImage() }
            .store(in: &cancellables)
    }

    private func installEventMonitors() {
        // 左键单击即时切换面板;右键弹出上下文菜单(含退出)。
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self,
                  let button = self.statusItem.button,
                  event.window == button.window else {
                return event
            }

            // 按住 Cmd 点击状态项是系统的图标拖动/重排手势。必须把事件交还系统,
            // 否则菜单栏管理器拿不到它、无法进入拖动模式(macOS 15 上事件链靠前,
            // 此处不放行会导致 Cmd+拖动完全失效;26/27 上系统更早消费,才没暴露)。
            if event.modifierFlags.contains(.command) {
                return event
            }

            switch event.type {
            case .leftMouseDown:
                self.handleStatusItemLeftClick(event)
            case .rightMouseDown:
                self.dismissPanel()
                self.showStatusItemContextMenu(for: button, event: event)
            default:
                break
            }
            return nil
        }

        // 面板打开时点击外部区域:关闭面板。
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.dismissPanel()
        }
    }

    // MARK: - Show / Hide

    private func handleStatusItemLeftClick(_ event: NSEvent) {
        // 单击即时切换面板。退出走右键上下文菜单,故不做双击判定,避免为等待
        // 双击窗口而延迟单击响应(那会导致面板"点了不出现")。
        togglePanel()
    }

    private func showStatusItemContextMenu(for button: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu(title: "HagimiMonitor")
        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(terminateApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func terminateApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func togglePanel() {
        if panel.isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // 先让 SwiftUI 布局出内容固有尺寸,再据此定位窗口,避免首帧尺寸跳变。
        // 用 intrinsicContentSize(NSHostingView 返回 SwiftUI 理想尺寸),不能用
        // fittingSize——hosting 被四边约束钉在 contentView 上,fittingSize 会解算成
        // 窗口现尺寸甚至 0,导致面板 0×0 看不见(这正是「有高亮但没面板」的根因)。
        hostingView?.layoutSubtreeIfNeeded()
        let intrinsic = hostingView?.intrinsicContentSize ?? .zero
        let size = (intrinsic.width > 1 && intrinsic.height > 1) ? intrinsic : panel.frame.size
        setPanelFrame(size: size, animate: false)

        store.panelDidAppear()
        statusItem.button?.highlight(true)

        // 通知系统在全屏模式下保持菜单栏可见。
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissPanel() {
        guard panel.isVisible else { return }

        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.statusItem.button?.highlight(false)
            self.store.panelDidDisappear()
        }
    }

    // MARK: - Sizing / Positioning

    /// SwiftUI 内容尺寸变化时:窗口顶边锚定、高度贴合内容当前尺寸。
    ///
    /// 必须 `DispatchQueue.main.async`(对齐 FluidMenuBarExtra):该回调发生在 SwiftUI
    /// 布局事务内,若同步 `setFrame(display:true)` 会在动画事务里强制重绘、引发 re-entrant
    /// 布局,把窗口定位/尺寸状态搞坏(表现为面板脱离菜单栏、底部大片空窗)。异步派发
    /// 到下一个 runloop,让 SwiftUI 先完成当前帧布局,窗口再贴合。
    ///
    /// 不能 guard panel.isVisible:size reader 的首次 onAppear 常在面板可见之前(init
    /// 布局阶段)触发,若丢弃则窗口尺寸永远停在默认值、之后 onChange 不再触发。
    ///
    /// 动画分工(关键):外层 `.background(GeometryReader)` 只在展开/收起时上报一次
    /// **终值**(不逐帧),故这里不能靠「逐帧 animate:false 贴合」补出平滑——那只会
    /// 让窗口一步瞬跳到终点。改为:面板可见且高度变化显著(展开/收起)时,用与内容
    /// (`MonitorPanelView.setExpansion` / `CollapsibleDetail`)完全一致的时长与 easeInOut
    /// 曲线做窗口补间;二者从同一时刻并行动画到同一终值,窗口高度(t)≈内容高度(t),
    /// 边框与内容一起伸缩、不裁剪不留空。指标微调(<阈值)仍瞬时贴合,不触发多余动画。
    private func contentSizeDidChange(to size: CGSize) {
        guard panel.frame.size != size else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.frame.size != size else { return }
            let delta = abs(self.panel.frame.height - size.height)
            // 仅用户 toggle 后的首次尺寸上报走补间;数据到达/定时刷新引起的变化
            // 瞬时贴合,不与展开动画叠加二次动画。
            let userToggled = self.store.consumeExpansionAnimationFlag()
            let animate = self.panel.isVisible && delta > 8 && userToggled
            self.setPanelFrame(size: size, animate: animate)
        }
    }

    private func setPanelFrame(size: CGSize, animate: Bool) {
        guard let buttonWindow = statusItem.button?.window else {
            panel.setContentSize(size)
            panel.center()
            return
        }

        let buttonFrame = buttonWindow.frame
        var origin = buttonFrame.origin

        // macOS 坐标原点在左下:origin.y 减去窗口高度,使顶边钉在菜单栏下沿,
        // 面板只向下生长。左边缘与按钮对齐,补偿窗口边框。
        origin.y -= size.height
        origin.x -= Self.windowBorderSize

        var newFrame = CGRect(origin: origin, size: size)

        // 越过屏幕右缘时向左回收;越左缘时向右回收。
        if let screen = buttonWindow.screen {
            if newFrame.maxX > screen.visibleFrame.maxX {
                newFrame.origin.x = screen.visibleFrame.maxX - size.width - Self.windowBorderSize
            }
            if newFrame.minX < screen.visibleFrame.minX {
                newFrame.origin.x = screen.visibleFrame.minX + Self.windowBorderSize
            }
        }

        guard newFrame != panel.frame else { return }
        if animate {
            // 与内容侧 `withAnimation(.easeInOut(panelExpansionDuration))` 完全同时长同曲线,
            // 使窗口高度补间与 CollapsibleDetail 的高度补间并行、逐帧对齐。
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MonitorConstants.panelExpansionDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    /// 构造状态项 label 视图:内嵌尺寸读取器,内容宽度变化时更新 `statusItem.length`,
    /// 使 variableLength 状态项宽度精确跟随图标/文字固有宽度(否则 button 会塌成默认窄宽,
    /// 图标被挤)。水平留白模拟系统 MenuBarExtra 的边距。
    /// 把 SwiftUI 状态项 label 快照成 NSImage 赋给 `button.image`,并按图像宽度更新
    /// `statusItem.length`。快照走 SwiftUI 现有绘制,样式与旧的子视图完全一致。
    private func refreshStatusItemImage() {
        // 用「状态项按钮的外观」而非 App 全局外观来决定墨色:菜单栏图标的黑/白由
        // 系统按当前壁纸/菜单栏底色决定(彩色壁纸下会走白字模式),button 的
        // effectiveAppearance 已反映这一判定,与旁边系统图标同步;若用 App 全局外观,
        // 浅色系统 + 彩色壁纸时会画成黑环,和白色的系统图标格格不入。
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.isDark

        // 环模式:MenuBarComputeRingIcon 已直接产出一张缓存好的 18×18 AppKit NSImage,
        // 无需再走 SwiftUI + ImageRenderer 二次光栅化。直接赋给 button.image,可绕开
        // CoreSVG/ImageRenderer 那一整套快照中间对象(CGImage/NSCGImageSnapshotRep/SVGPath),
        // 它们此前会随负载动画持续累积、常驻不释放,也是空闲 CPU 高的主因。
        // 该 NSImage 由绘制闭包惰性渲染,系统绘制时会按各屏 scale 原生重画,多屏依旧清晰;
        // 内部读 NSAppearance.currentDrawing() 判定墨色,与 button 外观同步。
        if store.settings.menuBarDisplayMode == .ring {
            // 切到环形模式时失效指标缓存:之后切回指标模式时,即使文本碰巧与上次
            // 相同,也得重新栅格化(当前 button.image 已是环形图)。
            lastMetricsRenderKey = nil
            let image = MenuBarComputeRingIcon.image(
                load: store.loadAnimator.displayedComputeLoad,
                darkMode: isDark,
                loadLevel: store.haloRingLoadLevel
            )
            // 负载未跨整数桶 / 外观未变时,image(...) 返回同一缓存 NSImage 对象。此时跳过
            // button.image 重新赋值:$modules 每秒 tick 都会触发本方法,重复赋同一张图会让
            // AppKit 反复为其生成缓存位图 rep(NSCGImageSnapshotRep),静置也持续累积。
            // 直接比较 statusItem.button?.image(真实显示状态),而非另开一个影子变量:
            // 后者在指标模式分支改写 button.image 后不会同步更新,会导致「指标→环形」
            // 切换回来时误判「未变」而漏刷新。
            guard image !== statusItem.button?.image else { return }
            // isTemplate 已在 MenuBarComputeRingIcon.image(...) 内部设置,此处无需重复赋值。
            statusItem.button?.image = image
            // 与旧的 .padding(.horizontal) 等价:图像左右各补留白。
            updateStatusItemLength(image.size.width + Self.statusItemHorizontalPadding * 2)
            return
        }

        // 指标(文本)模式:无现成位图,仍用 ImageRenderer 快照。
        // 先按最大屏 scale 与当前指标文本构造去重键,命中即跳过整套快照渲染。
        let scale = NSScreen.screens.map(\.backingScaleFactor).max()
            ?? statusItem.button?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        let renderKey = MetricsRenderKey(
            items: store.menuBarMetricItems,
            isDark: isDark,
            layout: store.settings.menuBarMetricLayoutStyle,
            scale: scale
        )
        guard renderKey != lastMetricsRenderKey else { return }

        // autoreleasepool 确保每次快照产生的 CG/SVG 中间对象在本次调用结束即释放,不再攒到内存高水位。
        autoreleasepool {
            let label = MenuBarStatusLabel(store: store, darkMode: isDark)
                .environment(\.colorScheme, isDark ? .dark : .light)
                .padding(.horizontal, Self.statusItemHorizontalPadding)
                .fixedSize()

            let renderer = ImageRenderer(content: label)
            renderer.proposedSize = ProposedViewSize(width: nil, height: 22)
            // 按所有屏幕里的最大 backingScaleFactor 光栅化:菜单栏在每块屏幕各画一遍,若只按
            // 主屏 scale 烤成位图,到 scale 更高的副屏会被放大而模糊。取最大 scale 后,任何屏幕
            // 都是缩小(清晰)而非放大。point 尺寸 = 像素/scale 不变,故状态项宽度、布局不受影响。
            renderer.scale = scale

            // 把选定外观设为当前绘制上下文,使内部的 NSAppearance.currentDrawing() 判定
            // 与上面 isDark 一致(否则 ImageRenderer 会用 App 全局外观绘制)。
            var cgImage: CGImage?
            appearance.performAsCurrentDrawingAppearance {
                cgImage = renderer.cgImage
            }
            guard let cgImage else { return }

            let pointSize = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
            let image = NSImage(cgImage: cgImage, size: pointSize)
            image.isTemplate = false

            statusItem.button?.image = image
            updateStatusItemLength(pointSize.width)
            // 仅在成功产出图像后记录去重键:渲染失败(cgImage 为 nil)时保留旧键,下个 tick 会重试。
            lastMetricsRenderKey = renderKey
        }
    }

    private func updateStatusItemLength(_ width: CGFloat) {
        let target = max(width.rounded(.up), 24)
        guard statusItem.length != target else { return }
        statusItem.length = target
    }

    /// 打开设置窗口前关闭面板(供 AppDelegate 的 openSettings 闭包调用)。
    /// 不直接调用 openSettingsAction,因为关闭面板和打开设置需要由外部协调。
    func dismissPanelForSettings() {
        guard panel.isVisible else { return }
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)
        panel.orderOut(nil)
        panel.alphaValue = 1
        statusItem.button?.highlight(false)
        store.panelDidDisappear()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            dismissPanel()
        }
    }
}

// MARK: - Size Reader

/// 读取 SwiftUI 内容固有尺寸并回调。内容瞬时上报尺寸,高度动画交给窗口层。
///
/// modifier 顺序对齐 FluidMenuBarExtra 的 `RootViewModifier`,三者缺一不可:
/// 1. `.background(GeometryReader)` 放在 `.fixedSize()` **之前**——测的是内容自然
///    布局尺寸,不受后面 `.frame(maxHeight:.infinity)` 拉伸影响;
/// 2. `.fixedSize()` 固定内容为固有尺寸;
/// 3. `.frame(maxWidth/Height:.infinity, alignment: .top)` 让内容在被窗口拉伸的
///    hosting 里顶部对齐——窗口高度动画时内容从顶部展开,而非居中跳变。
///    实现者此前把 `.fixedSize()` 放在测量之前、且缺少顶对齐 frame,是动画观感丢失的原因之一。
private struct FluidPanelSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            // 关键:必须忽略安全区。窗口是 `.titled`,SwiftUI 默认把顶部标题栏区域
            // 当安全区留白——内容被下顶(顶部大空白),底部溢出窗口(按钮被裁掉)。
            // 对齐 FluidMenuBarExtra 的 RootViewModifier,填掉标题栏空间。
            .edgesIgnoringSafeArea(.all)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { onChange(geometry.size) }
                        .onChange(of: geometry.size) { _, newValue in
                            onChange(newValue)
                        }
                }
            )
            .fixedSize()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - OpenSettings Environment Key

/// 自定义环境键,用于将 openSettings 闭包注入到 NSHostingView 承载的 SwiftUI 视图树中。
/// `OpenSettingsAction` 是 SwiftUI 内部类型,无法在 NSHostingView 构造时直接注入,
/// 因此用自定义环境键传递闭包,在 MonitorPanelView 中读取并调用。
enum OpenSettingsActionKey: EnvironmentKey {
    struct Action: Sendable {
        let action: @Sendable () -> Void

        init(_ action: @escaping @Sendable () -> Void) {
            self.action = action
        }

        func callAsFunction() {
            action()
        }
    }

    static let defaultValue: Action = Action({})
}

extension EnvironmentValues {
    var fluidOpenSettings: OpenSettingsActionKey.Action {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }
}

// MARK: - Notification Names

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}
