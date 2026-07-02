## 1. FluidPanelController 承载层

- [x] 1.1 以 `reference/FluidPanelController.draft.swift` 为起点，校对补全后放入 `HagimiMonitor/Views/Panel/FluidPanelController.swift`：`@MainActor final class`，持有 `MonitorStore`、`NSStatusItem`、`NSPanel`，注入「打开设置」的动作（修复草稿中 `@Environment(\.openSettings)` 用法编译错误——改为复用 `SettingsWindowPresenter`）
- [x] 1.2 配置 `NSPanel`：`styleMask [.borderless, .nonactivatingPanel, .utilityWindow, .fullSizeContentView]`、`level=.statusBar`、透明背景、有阴影、`animationBehavior=.none`、`collectionBehavior` 含 `.fullScreenAuxiliary`、`isReleasedWhenClosed=false`、`delegate=self`
- [x] 1.3 用 `NSHostingView` 承载 `MonitorPanelView(store:)`，注入 `openSettings` 环境/动作，`sizingOptions=[]`，作为 `panel.contentView`
- [x] 1.4 实现 `FluidPanelSizeReader` 修饰符（`GeometryReader` + `.fixedSize()`）读取内容固有尺寸并回调，内容瞬时上报、不加 `withAnimation`
- [x] 1.5 确认自建 `NSPanel` 下窗口透明与行级毛玻璃仍生效；若 `TransparentWindowBackground` 不再需要则由 `NSPanel` 透明配置替代

## 2. 动态状态项图标

- [x] 2.1 创建 `NSStatusItem(variableLength)`，`button` 内嵌 `NSHostingView(MenuBarStatusLabel(store:darkMode:))`，Auto Layout 居中并填满按钮高度
- [x] 2.2 设置无障碍标题 "HagimiMonitor"；订阅 `settings.$themePreference` / 外观变化，替换 hosting `rootView` 刷新图标
- [x] 2.3 验证 ring 模式与 metrics 可变宽模式均正确渲染、宽度自适应

## 3. 显隐、定位与动画

- [x] 3.1 实现 `showPanel()`：先 `layoutSubtreeIfNeeded()` 取 `fittingSize`，`setPanelFrame(animate:false)` 定位，调用 `store.panelDidAppear()`，`makeKeyAndOrderFront`，高亮按钮
- [x] 3.2 实现 `dismissPanel()`：`NSAnimationContext` 0.18s 淡出后 `orderOut`、还原 `alphaValue`、取消高亮，调用 `store.panelDidDisappear()`
- [x] 3.3 实现 `setPanelFrame(size:animate:)`：顶边锚定 `origin.y -= size.height`、`origin.x -= 2pt`，屏幕左右边缘回收，`setFrame(display:true, animate:)`
- [x] 3.4 实现 `contentSizeDidChange`：面板可见且尺寸变化时 `setPanelFrame(animate:true)`，驱动平滑高度动画
- [x] 3.5 显隐时 post `beginMenuTracking` / `endMenuTracking`，保证全屏下菜单栏保持可见

## 4. 交互与生命周期

- [x] 4.1 `LocalEventMonitor([.leftMouseDown])`：命中状态项按钮 → `togglePanel()` 并返回 `nil` 吞掉事件
- [x] 4.2 `GlobalEventMonitor([.leftMouseDown,.rightMouseDown])`：面板可见时点击外部 → `dismissPanel()`
- [x] 4.3 `NSWindowDelegate.windowDidResignKey` → `dismissPanel()`
- [x] 4.4 `deinit` 移除事件监听与 `NSStatusItem`
- [x] 4.5 打开设置的动作：先关闭面板再前置设置窗口（复用 `SettingsWindowPresenter`），验证不冲突

## 5. App 入口改造

- [x] 5.1 新增 `AppDelegate: NSObject, NSApplicationDelegate`，在 `applicationDidFinishLaunching` 创建并持有 `FluidPanelController`（注入 `MonitorStore`）
- [x] 5.2 `HagimiMonitorApp` 用 `@NSApplicationDelegateAdaptor` 接入 AppDelegate；`MonitorStore` 的所有权在 App 与 Delegate 间协调（单一实例，避免重复采样）
- [x] 5.3 移除 `MenuBarExtra` Scene 及 `.menuBarExtraStyle(.window)`，保留 `Settings` 与 `WindowGroup("Preview")`
- [x] 5.4 确认 `will terminate` 的 flush、`panelDidAppear/Disappear` 联动在新结构下仍触发

## 6. 面板动画一致性清理

- [x] 6.1 `MonitorPanelView.setExpansion`：移除 `#available(macOS 26)` 分叉与 `withAnimation`，两版本统一（高度动画交给窗口层）
- [x] 6.2 `AnyTransition.detailDisclosure`：移除按版本返回 `.identity` 的分叉，统一为单一过渡定义
- [x] 6.3 确认 `MetricGlassRow`/`NetworkGlassRow`/`BatteryGlassRow`/`DisplayControlsSection` 展开过渡共用同一定义

## 7. 验证与回归

- [x] 7.1 macOS 26 构建 `HagimiMonitorDirect`：显隐、切换、外部/失焦关闭、展开动画、设置窗口、Preview 均正常
- [ ] 7.2 macOS 15 真机回归：展开 CPU/GPU 不闪、顶部 SYSTEM·LIVE 不跳、顶边锚定、高度动画平滑
- [ ] 7.3 macOS 15 真机：ring 与 metrics 两种图标模式、全屏保持菜单栏、多屏 / 刘海屏定位与边缘回收
- [ ] 7.4 主题（浅/深、balanced/vibrant）切换后图标与面板外观正确
- [ ] 7.5 回归通过后运行 `openspec validate` 并归档 change
