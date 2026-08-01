# Design: Menu Bar Quick Tools

## Context
菜单栏面板（`MonitorPanelView`，承载于自建 `NSPanel`，见 `FluidPanelController` /
`PinnedPanelController`）目前只展示监控模块。用户希望额外集成"顺手小工具"（防休眠、键盘锁定），
但这些是**主动开关**而非监控项，需要与监控区在信息架构与视觉语言上分离。部署目标 macOS 15.0，
双 target（沙盒 App Store 版 / 非沙盒 Direct 版）。

## Decision 1: 承载方式 = 官方 NSPopover 外部浮层
**选择**：面板底部操作区放一个「工具」按钮，点击用 `NSPopover.show(relativeTo:of:preferredEdge:.maxY)`
从按钮弹出浮层。

**理由 / 否决的替代**：
- ❌ 自绘悬停子窗口：`onHover` 在刚 `orderFront` 的子窗口上首次收不到 enter（首次不弹）；
  `.behindWindow` + 手绘阴影与面板材质不一致；自适应方位要手写屏幕余量几何，脆弱。
- ❌ 面板内展开区块（同「显示器」行）：稳且同款玻璃，但让主动开关伪装成只读监控行，
  违背"形式即语义"，用户明确反对。
- ✅ NSPopover：官方组件，**点击**触发（无 hover bug）；系统绘制箭头/圆角/材质/阴影（不突兀）；
  箭头指向入口（可发现）；**原生自适应方位**；macOS 26+ 自动液态玻璃。

**关键实现点**：
- 触发用**点击**，不用 hover。
- popover.behavior = `.transient`（点击外部自动关闭），contentViewController 用 `NSHostingController(rootView: ToolsPopoverView)`。
- `preferredEdge: .maxY`（朝下）；下方空间不足时系统自动翻到 `.maxX/.minX/.minY`，箭头自动重指——
  这正是早期"自适应沙盘"手写的"底→右→左→顶"，改用官方组件免费获得。
- 从菜单栏面板与钉住面板都能弹（两个控制器各自持有/呈现），锚点是各自面板里的「工具」按钮。

## Decision 2: 液态玻璃只在 popover，不在面板行
**选择**：popover 用系统默认材质（macOS 26+ 自动液态玻璃）；面板监控行维持既有 `.menu` 毛玻璃。

**理由**：项目此前**主动**把行级液态玻璃降级为 `NSVisualEffectView(.menu, .withinWindow)`，
因为 `GlassEffectContainer` 的几何合并会在面板伸缩时引发展开闪烁（见 `CompatibleGlassContainer` 头注）。
NSPopover 是独立窗口、不随面板每秒刷新，因此在这里用液态玻璃**安全**、且不触碰面板既有闪烁治理。

## Decision 3: 防休眠 = IOPMAssertion（双版本）
- `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, ...)`，
  阻止显示器空闲休眠（连带阻止空闲锁屏/睡眠）。进程内、无需权限、**沙盒兼容**。
- 幂等 activate/deactivate；`deinit` 释放。
- **不持久化**：App 退出/崩溃时断言由系统自动释放，下次启动回到未激活——刻意为之，避免无感知耗电。
- 合盖不睡（需 `pmset disablesleep`/root）**不做**，见 Non-Goals。

## Decision 4: 键盘锁定 = CGEventTap（仅 Direct）
- `CGEvent.tapCreate` 监听 `keyDown|keyUp|flagsChanged`，回调恒返回 nil **吞事件**。
  参考既有 `MediaKeyTapBridge` 的 tap 生命周期与 tapDisabled 自动重启用。
- **只锁键盘，不锁鼠标/触控板**——鼠标点面板是解锁逃生通道，绝不能一并拦截。
- 主动式 tap 需辅助功能权限 → 复用 `AccessibilityPermissionService`（弹窗 + 打开系统设置 + 轮询）。
  沙盒拿不到该权限，故此文件放 `HagimiMonitorDirectOnly/`，仅 Direct target 编译。
- 安全兜底：系统锁屏是独立安全会话，tap 影响不到密码输入（不会把自己锁死）；
  加自动解锁计时（默认 20 分钟）防"锁了就忘"；tapDisabledByTimeout/UserInput 时自动重启用。
- 线程：非隔离类，owner（`ToolsState`，MainActor）在主线程调用；`deinit` 同步移除 runLoopSource。

## Decision 5: 状态层 ToolsState（单例 + 双版本门控）
- `@MainActor final class ToolsState: ObservableObject`，`static let shared`（菜单栏/钉住面板共享同一份状态，
  断言/tap 全局只应存在一份）。
- `keepAwakeActive` 双版本；`keyboardLocked` 与相关成员用 `#if DIRECT_DISTRIBUTION` 包裹。
- `anyToolActive` 供「工具」按钮角标（收起时若有工具激活，按钮上显示小圆点提示）。

## Decision 6: 浮层视觉 = 点亮式 toggle 磁贴（控制中心语言）
- 每个工具一张磁贴：圆形图标徽标 + 名称 + 状态副文案 + 原生 `Toggle(.switch)`（或整块可点）。
- **激活态整块染色发光**（模块色：键盘锁暖色、防休眠冷色），圆标满色——一眼区别于只读监控行。
- 键盘锁未授权时副文案显示「需辅助功能权限」，点击触发授权引导。
- 沙盒版浮层只有防休眠一个磁贴（键盘锁 `#if` 后不编译）。

## Risks
- NSPopover 从非激活 `NSPanel`（面板本身失焦即收）弹出时的焦点/关闭交互需实测：
  popover 打开期间不能让宿主面板误判 resignKey 而收起。可能需要 `.applicationDefined` behavior
  或在 popover 生命周期内抑制面板的 resignKey 关闭。**这是落地时的头号验证项。**
- macOS 15 上 NSPopover 无液态玻璃（走系统 vibrancy），需确认降级观感可接受。
- 键盘锁的辅助功能授权在首次点击时触发，需清晰的未授权态与授权后自动生效（复用媒体键那套轮询）。

## Migration / Rollback
- 纯新增能力，无数据迁移。回滚 = 删除新增文件 + 面板按钮 + `tools.*` 键（本次已演练过一次删除，干净）。
