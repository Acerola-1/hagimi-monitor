# Proposal: Menu Bar Quick Tools（菜单栏快捷小工具）

## Summary
在菜单栏面板中集成一组**轻量、无侵入的快捷小工具**（首批两个：键盘锁定、防休眠），
它们不是系统监控项，而是"顺手用一下"的**主动开关**。工具承载于面板底部「工具」按钮
点出的 **NSPopover 外部浮层**中——独立于监控列表、语义干净、可发现、原生自适应方位，
并在 macOS 26+ 自动获得液态玻璃材质。

> 状态：**已设计、暂缓实现**。本 change 记录经多轮原型探索后收敛的最终方案与踩坑结论，
> 供未来某个版本直接落地。设计原型见 `prototypes/tools-popover/`（首选方案）、
> `prototypes/tools-integration/`（四方向对比）、`prototypes/tools-drawer/`（早期悬停抽屉，已否决）。

## Problems
- 用户有一些高频顺手的小操作（擦键盘时锁键盘、看视频/演示时防息屏），希望在已有的
  菜单栏 App 里"额外集成一下"，而不必再装 One Switch / Amphetamine 等独立应用。
- 这些工具**不属于监控主题**：监控行是"只读、连续、被动"的仪表，工具是"主动去拨"的开关。
  若沿用监控行的形式，会在信息架构上误导用户"这也是一项监控"（形式即语义）。
- 面板高度有限且可能很长（模块多时贴近屏幕底部），工具入口必须能自适应弹出方位。

## Goals
- 首批两个工具：
  - **防休眠**：阻止显示器空闲休眠（连带阻止空闲锁屏/睡眠）。双渠道（含沙盒）均可用。
  - **键盘锁定**：拦截并吞掉全部键盘事件（只锁键盘、不锁鼠标/触控板，鼠标是解锁逃生通道）。仅 Direct 版。
- 工具入口与监控区**视觉/语义分离**：面板底部操作区一个「工具」按钮，点击弹出**外部浮层**，
  浮层用"点亮式 toggle 磁贴"（控制中心语言），激活时整块染色发光，一眼区别于监控行。
- 浮层用官方 **NSPopover**：带箭头指向入口、系统绘制的圆角/材质/阴影、
  **原生自适应方位**（下方不够自动翻侧边/上方），macOS 26+ 自动液态玻璃。
- 双版本门控：键盘锁定仅 Direct 版编译；防休眠双版本可用。
- 激活态**不持久化**（即时性工具，跨启动残留会造成无感知的耗电/拦截）。
- 三语本地化（zh-Hans / en / ja）。

## Non-Goals
- 不做"合盖不睡"（需 root + pmset disablesleep，须新建特权通道，与轻量定位冲突；
  待特权助手基建落地后另议）。
- 不做工具的持久化开机自启/跨启动记忆。
- 不做用户自定义工具/插件系统；工具集合本期硬编码。
- 不做全局快捷键绑定（可作为后续增强）。
- 首期不追求把整个面板迁移到液态玻璃（那是独立的 adopt-liquid-glass 议题）。

## Impact
- 新增（Direct + 沙盒共享，`HagimiMonitor/Tools/`）：
  - `KeepAwakeController.swift` — IOPMAssertion 封装。
  - `ToolsState.swift` — `@MainActor ObservableObject`，`static shared`，工具激活态与开关逻辑；键盘锁成员用 `#if DIRECT_DISTRIBUTION` 门控。
  - `ToolsPopoverView.swift` — 浮层 SwiftUI 内容（点亮式磁贴）。
- 新增（仅 Direct，`HagimiMonitorDirectOnly/`）：
  - `KeyboardLockController.swift` — CGEventTap 键盘拦截，复用 `AccessibilityPermissionService` 授权链路。
- 改动：
  - `MonitorPanelView.swift` — 底部操作区新增「工具」按钮（激活时带角标），点击弹 NSPopover。
  - `FluidPanelController.swift` / `PinnedPanelController.swift` — 持有并呈现 NSPopover（`show(relativeTo:of:preferredEdge:.maxY)`）。
  - `Localizable.xcstrings` — 新增 `tools.*` 键（三语）。
- 构建：`HagimiMonitor/Tools/` 走 fileSystemSynchronizedGroups 自动归属两个 target；
  `HagimiMonitorDirectOnly/` 只归属 Direct target，无需改 pbxproj。

## Dependencies
- 无强依赖。复用现有 `AccessibilityPermissionService`（媒体键接管已在用）。
- 与 adopt-liquid-glass 解耦：NSPopover 的液态玻璃是系统自动的，不依赖面板改造。

## History / 决策沉淀（重要）
落地前曾走过三条弯路，最终收敛到 NSPopover，结论务必带入实现：
1. **自绘悬停子窗口（否决）**：hover 触发导致首次不弹/误触；`.behindWindow` 材质与手绘浓投影与面板不搭；自适应方位靠手写几何，脆弱。
2. **面板内展开区块（否决）**：虽和「显示器」行同款玻璃、稳，但让"主动开关"长成"只读监控行"，违背形式即语义。
3. **右键菜单（仅作补充）**：不占面板、极稳，但可发现性弱、无点亮视觉。
→ **NSPopover 一次满足全部诉求**：外部浮层、可发现（按钮+箭头）、系统绘制不突兀、点击触发（无 hover bug）、原生自适应方位、macOS 26+ 自动液态玻璃且不踩面板行内液态玻璃的展开闪烁坑。
