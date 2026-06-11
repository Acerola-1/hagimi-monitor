## Why

当前设置窗口使用 `TabView` 三 Tab（常规 / 模块 / 关于）的纵向列状布局，模块 Tab 下所有子模块（CPU/GPU/内存/存储/网络/电池）共用一个滚动面板。未来需要为每个模块加入子项可见性开关（如 CPU 各项指标、温度传感器分类等），列状结构会让单页内容急剧膨胀、滚动疲劳。

改为「左侧导航 + 右侧详情」的 macOS 主流设置布局（NavigationSplitView），可以让每个子模块独享右侧画布，为后续「指标可见性」「温度监控」等功能预留充分空间。

## What Changes

- **BREAKING（UI 层）**：`SettingsView` 由 `TabView` 重构为 `NavigationSplitView`，左侧为带 SF Symbol 图标的导航列表，右侧为路由切换的详情区
- 左侧一级菜单平铺：「常规」→「模块」（含 6 个子菜单：CPU/GPU/内存/存储/网络/电池）→「关于」，无分组标题
- 「模块」一级菜单默认展开，6 个子菜单始终可见，不可折叠
- 每个模块子菜单对应独立的右侧视图，当前阶段只显示「模块可见性开关」（迁移自现有「模块」Tab 的对应行），为后续子项可见性扩展预留布局空间
- 设置窗口默认尺寸由 480×400 调整为 720×520，允许用户拖拽放大
- 新增 `SettingsRoute` 枚举驱动导航选择状态

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `color-scheme-settings`: 「常规」Tab 内容（主题、配色、负载环数据源等）迁移到 NavigationSplitView 右侧的「常规」详情区，呈现方式由 Tab 切换改为侧边栏选中

## Impact

- 修改：`HagimiMonitor/SettingsView.swift`（核心重构）
- 新增：`HagimiMonitor/Views/Settings/` 目录，按职责拆出 `SettingsSidebar.swift`、`GeneralSettingsView.swift`、`AboutSettingsView.swift`、`ModuleSettingsView.swift`（接收 `MonitorKind` 渲染对应模块的详情）
- 新增：`SettingsRoute` 枚举（可放在 `SettingsView.swift` 同文件或独立 `SettingsRoute.swift`）
- 不影响：`MonitorSettings.swift` 持久化层、`MonitorStore`、所有 Sampler、面板视图（`MonitorPanelView`）
- 不影响：双分发模式（App Store / Direct）的条件编译逻辑，`DISPLAY_CONTROL` 仍按现状嵌入对应模块详情
