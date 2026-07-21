## Context

监控面板目前由自建的 `FluidPanelController` 承载在一个 `NSPanel` 中，从菜单栏状态项点击弹出，并在失焦（`windowDidResignKey`）或点击外部（全局事件监听）时自动关闭。面板内容视图 `MonitorPanelView(store:)` 与数据源 `MonitorStore`（单例，由 `AppDelegate` 持有）解耦，采样节流依赖 `MonitorStore.isPanelVisible`（单一布尔）与 `panelDidAppear()/panelDidDisappear()`。

本次要新增一个「钉住面板」：全局快捷键呼出、可拖动、始终最前、位置持久化、仅当前桌面显示。它与现有菜单栏面板并存，需要共享同一个 `MonitorStore`，且不破坏现有面板「点开即弹、失焦即收」的手感。

约束：
- 需兼容 App Store 沙盒分发版与直接分发版（`#if DIRECT_DISTRIBUTION`）。
- 全局快捷键 MUST NOT 依赖辅助功能权限（沙盒下不可用）。
- 遵循 i18n 规范：新增用户可见文案在 `Localizable.xcstrings` 补齐 `zh-Hans` / `en`。
- 保留 macOS 15 / 26 兼容层（`CompatibleGlassContainer` 等）。

## Goals / Non-Goals

**Goals:**
- 全局快捷键切换钉住面板显隐，快捷键可自定义、可清除、可持久化。
- 钉住面板可拖动、始终最前、失焦不关闭、悬停显示关闭按钮。
- 窗口位置持久化并在重启后恢复，越界时回收到可见屏幕内。
- 菜单栏面板与钉住面板共享单一 `MonitorStore`，采样循环唯一。
- 采样可见性判定改为引用计数，任一面板可见即保持采样。

**Non-Goals:**
- 不实现「所有桌面（Spaces）显示」（不启用 `.canJoinAllSpaces`）。
- 不实现多个钉住窗口同时存在（本期仅单个钉住面板；架构预留但不落地）。
- 不改变现有菜单栏面板的交互与外观。
- 不实现钉住面板的缩放、透明度调节、内容裁剪等增强（后续可选）。

## Decisions

### 决策 1：新建 `PinnedPanelController`，而非改造 `FluidPanelController`
钉住面板所需性质与菜单栏面板几乎相反（可移动 / 失焦不关 / 非菜单栏锚定 / floating 层级）。改造现有控制器会引入大量条件分支，易破坏「点开即弹、失焦即收」的稳定手感。
- **方案**：新建 `PinnedPanelController`（`@MainActor`，持有独立 `NSPanel`），复用 `MonitorPanelView(store:)` 作为内容，注入相同的 `openSettings` 闭包与透明背景组件。
- **窗口配置**：`isMovableByWindowBackground = true`；`level = .floating`；`hidesOnDeactivate = false`；`collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`（不含 `.canJoinAllSpaces`）；`windowDidResignKey` 不做关闭；不安装「点击外部关闭」的全局监听。
- **备选**：在 `FluidPanelController` 加「pinned 模式」标志位——被否，理由如上。

### 决策 2：全局快捷键使用 `KeyboardShortcuts`（SPM）
- **方案**：引入 `sindresorhus/KeyboardShortcuts`。底层用 Carbon `RegisterEventHotKey`，**无需辅助功能权限**、**沙盒可用**；自带 SwiftUI `KeyboardShortcuts.Recorder` 录制控件与 UserDefaults 自动持久化；定义一个 `KeyboardShortcuts.Name.togglePinnedPanel`。
- **备选 A**：自建 Carbon `RegisterEventHotKey` 封装——可行但需自写录制 UI 与持久化，成本高。
- **备选 B**：`NSEvent.addGlobalMonitorForEvents`——无法「消费」按键、且全局监听键盘在沙盒/权限上有顾虑，不适合做快捷键，排除。
- **接线**：`AppDelegate` 在 `applicationDidFinishLaunching` 里 `KeyboardShortcuts.onKeyUp(for: .togglePinnedPanel) { self.pinnedPanelController.toggle() }`。清除快捷键时库自动注销热键。

### 决策 3：采样可见性引用计数
`MonitorStore` 增加一个可见消费者集合（例如 `enum PanelKind { case menuBar, pinned }` 的 `Set`）。
- `panelDidAppear(_:)` / `panelDidDisappear(_:)` 带来源参数，插入/移除后由集合是否为空推导 `isPanelVisible`。
- 进程采样定时器仅在集合「从空变非空」时启动、「从非空变空」时停止，避免抖动。
- `DisplayControlsSection` 继续读 `store.isPanelVisible`，语义自然兼容（任一面板可见即为真）。
- **兼容**：保留现有无参 `panelDidAppear()/panelDidDisappear()` 作为 `.menuBar` 的便捷封装，减少对 `FluidPanelController` 的改动面。

### 决策 4：位置持久化与越界回收
- **方案**：拖动结束（`windowDidMove` / `windowDidEndLiveResize`）时，将 `panel.frame.origin` 存入 `MonitorSettings`（`UserDefaults`，与现有键风格一致，存 `x/y` 两个 Double 或一个 NSStringFromRect）。
- **呼出定位**：显示时读取存储的 origin；若无历史值则用默认位置（主屏右上或屏幕中心附近）。
- **越界回收**：定位前用 `NSScreen.screens` 的 `visibleFrame` 校验，若面板矩形不与任何可见区域相交，则夹取回主屏 `visibleFrame` 内（复用 `FluidPanelController.setPanelFrame` 里已有的边界回收思路）。

### 决策 5：关闭方式（快捷键 + 悬停按钮）
- 快捷键做 toggle：可见则 `orderOut` 隐藏，不可见则定位并 `orderFront` 显示（不夺取焦点，用 `orderFrontRegardless` 或非激活显示，保持当前 App 前台）。
- 悬停关闭按钮：在 `MonitorPanelView` 内新增一个仅「钉住模式」显示的关闭控件，通过环境值或初始化参数区分面板角色，点击回调走 controller 的隐藏逻辑。为避免污染菜单栏面板，用一个 `panelRole` 环境键控制其显隐。

### 决策 6：依赖接入两个 target
`KeyboardShortcuts` 需同时链接 `HagimiMonitor`（App Store）与 `HagimiMonitorDirect` 两个 target。快捷键功能对两版都开放（非 `#if DIRECT_DISTRIBUTION` 限定）。

## Risks / Trade-offs

- [快捷键与系统/其他 App 冲突] → 使用 `KeyboardShortcuts.Recorder`，冲突时库会提示；默认不预置快捷键（留空），由用户自行设置，避免开箱即撞键。
- [floating 层级遮挡全屏应用] → `collectionBehavior` 含 `.fullScreenAuxiliary`，在全屏辅助场景表现可控；不追加 all-spaces，降低干扰。
- [引用计数改动波及现有采样启停] → 保留旧的无参 API 作封装，改动集中在 `MonitorStore` 内部；补单元测试覆盖「单开/双开/全关」三种可见性推导。
- [位置记忆导致面板出现在已拔掉的屏幕外] → 定位前做屏幕可见区域相交校验并回收到主屏。
- [新增 SPM 依赖增加构建与签名复杂度] → `KeyboardShortcuts` 为纯 Swift、无额外可执行组件，签名影响小；与既有 Sparkle SPM 流程一致。
- [两个窗口共享 `MonitorStore` 的线程/主线程约束] → 二者均 `@MainActor`，与现有约定一致。

## Migration Plan

1. 添加 SPM 依赖 `KeyboardShortcuts` 到两个 target。
2. `MonitorStore` 引入引用计数可见性（保留旧 API 封装），加单测。
3. 新建 `PinnedPanelController` 与位置持久化字段（`MonitorSettings`）。
4. `AppDelegate` 持有 `pinnedPanelController` 并接线快捷键回调。
5. 设置界面加入快捷键录制控件与（可选）自动显示开关；补 `Localizable.xcstrings`。
6. `MonitorPanelView` 加入「钉住模式」悬停关闭控件（按 `panelRole` 显隐）。
7. 回归验证菜单栏面板行为不变；`xcodebuild test` 通过后按 `release.sh` 流程发布。

回滚策略：功能自成模块，若出问题可移除快捷键接线与 `PinnedPanelController` 实例化（不影响菜单栏面板与采样主流程）。

## Open Questions

- 是否需要「开机自动显示钉住面板」开关？（proposal 标记为可选，倾向本期提供一个 UserDefaults 开关，默认关闭。）
- 默认呼出位置：主屏右上角 vs 屏幕中心？（倾向右上角，贴近钉图直觉，最终以实现时观感为准。）
- 钉住面板是否需要与菜单栏面板不同的默认宽度或紧凑布局？（本期沿用相同 `MonitorPanelView`，后续按反馈调整。）
