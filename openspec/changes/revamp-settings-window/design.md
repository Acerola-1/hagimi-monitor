## Context

HagimiMonitor 的设置窗口是用户感知品质的重要门面。当前实现于 `SettingsView.swift` 用手拼 `HStack { List, Divider, Detail }` 模拟侧栏布局，并在 List row 中嵌入 Toggle 控件，与 `List(selection:)` 的选中态语义冲突，造成视觉与交互的双重 bug。

与此同时，每个监控模块即将引入「可置换检测项目」能力（例如 CPU 允许用户启用/禁用用户态占比、系统态占比、单核负载、热状态等子项），需要详情页提前预留可扩展的 Section 框架，否则后续每加一个开关都得改 UI 结构。

macOS 26+ 引入 Liquid Glass，但 [[adapt-macos27-glass-appearance]] 已经识别出 macOS 27 Beta 1 中 `.glass` 高光过于强烈的问题。本提案在设置窗口中采用与之一致的「克制玻璃」策略，避免在 Form 内部滥用 glass。

## Goals / Non-Goals

**Goals:**
- 使用 Apple 原生语义组件（sidebar `List`、`Form .grouped`、`LabeledContent`、`.buttonStyle(.glass*)`），避免手绘
- 修复侧栏 row 中嵌 Toggle 引起的交互 bug
- 为「每模块可置换检测项目」预留可扩展 Section 框架
- 采用克制的液态玻璃：仅 About 卡片 + 主操作按钮使用 glass
- 设置窗口可调整大小，初始尺寸合理容纳模块详情

**Non-Goals:**
- 不实际定义每个模块的检测项目清单（仅做框架与占位）
- 不改动 Sampler / MonitorStore / 菜单栏面板的任何业务逻辑
- 不引入新的偏好项（除「检测项目启用集合」这个为框架配套的持久化）
- 不为 macOS 26 与 macOS 27 之间做差异化样式分支（统一采用克制策略）

## Decisions

### 用受控双栏布局而不是系统 `NavigationSplitView`

初版尝试使用 `NavigationSplitView`，但在 Settings 场景中实测会出现异常的三段式宽布局：窗口左侧生成一块大空白列，实际 sidebar 被推到中间，详情页也被压成窄条。该行为与「小巧精致」目标冲突。

新方案采用受控 `HStack(spacing: 0)` 双栏：左侧固定 164pt sidebar，右侧为详情区，中间用 `Divider`。侧栏内部仍使用 `List(selection:)` + `.listStyle(.sidebar)`，保留系统 sidebar 的选中态、键盘导航与无障碍语义，但不再把根布局交给系统 split view 自动分配。

替代方案：继续用 `TabView .tabViewStyle(.sidebarAdaptable)`。被否决，因为 macOS 设置窗口的主流形态已经从「顶部 Tab」迁移到「侧栏 + 详情」，且 Tab 模式不能优雅承载模块数量增长。

### 侧栏 row 只显示 Label，可见性开关挪到详情页

当前侧栏 row 是 `Label + Spacer + Toggle`，导致：
- 用户想点击 row 切换详情，可能误触 Toggle
- `List(selection:)` 的选中态高亮覆盖 Toggle，视觉混乱
- VoiceOver 无法清晰播报「这是一个导航条目」还是「这是一个开关」

新方案：侧栏 row 只是 `Label(kind.title, systemImage: kind.symbol)`，模块的「在面板中显示」开关移到该模块详情页的第一个 Section。

### 用 `Form .grouped` + `LabeledContent` 作为详情页基底

`Form` 自动提供 macOS 原生的分组样式、行高、分隔线与圆角。`LabeledContent("xxx") { Control }` 自动处理左右对齐、文字截断与无障碍标签。这是 Apple 在系统设置中的事实标准。

替代方案：自己用 `VStack + HStack` 拼分组卡片。被否决，因为既无法跟随系统外观变化，也会拼出 [[adapt-macos27-glass-appearance]] 中提到的过度玻璃问题。

### 克制的液态玻璃策略

仅在以下三处使用 `glassEffect` / `.glass*` button style：

1. **About 页顶部的 App 信息卡片** —— `glassEffect(.regular, in: .rect(cornerRadius: 14))`，作为视觉锚点
2. **主操作按钮** —— 「检查更新」/「下载更新」用 `.buttonStyle(.glassProminent)`
3. **次操作按钮** —— GitHub 链接、重置按钮用 `.buttonStyle(.glass)`

所有 glass 元素包在 `GlassEffectContainer` 中以获得统一高光。

替代方案：在每个模块详情页顶部加状态卡片（带模块色 tint）。被否决，与本次「克制」决策冲突，且会和详情页 Form 的视觉重量竞争。可在后续作为独立 change 评估。

### 「可置换检测项目」的数据模型

```swift
struct MetricSwitch: Identifiable, Hashable {
    let id: String        // 形如 "cpu.user", "cpu.system"
    let title: String     // 用户可见名称
    let isDefault: Bool   // 出厂默认启用状态
}

extension MonitorKind {
    var availableMetrics: [MetricSwitch] { /* 各 kind 独自定义 */ }
}
```

`MonitorSettings` 新增：

```swift
@Published private(set) var enabledMetrics: [MonitorKind: Set<String>]
func isMetricEnabled(_ id: String, for kind: MonitorKind) -> Bool
func setMetric(_ id: String, enabled: Bool, for kind: MonitorKind)
```

持久化策略：UserDefaults key 形如 `settings.enabledMetrics.<kind.rawValue>`，存为 `[String]`，缺失时回退到 `availableMetrics` 中所有 `isDefault == true` 的项。

详情页通过 `ForEach(kind.availableMetrics)` 自动渲染开关，新增项目时只需扩展 `availableMetrics` 数组，无需改 UI。

本提案不定义具体项目清单（用户表示「先搭框架」），但每个 kind 至少返回一项占位（例如 CPU 返回 `"cpu.overall"`），用于验证框架可工作。

检测项目不是二元开关外观，而是主面板字段选择器：每行点击后以圆形 checkmark 表示选中。每个模块最多选中 4 项，该限制与主面板展示容量一致。`MonitorSettings.setMetric(_:enabled:for:)` 在数据层执行上限约束，UI 层在达到 4 项后禁用其他未选行，但允许取消已选行。

### 紧凑精品窗口尺寸与密度

视觉目标从「照搬 System Settings」调整为「macOS 原生偏好窗口 + Xcode/Finder/CleanShot X/Raycast 式工具密度」。保留 sidebar `List` 与原生 Form 语义，但不让详情页无限铺宽。

侧栏固定 164pt；窗口本体通过 `.frame(minWidth: 560, idealWidth: 600, minHeight: 360, idealHeight: 382)`。`SettingsWindowPresenter.register(_:)` 会把历史上被异常拉大的设置窗口恢复到 600×382，避免用户继续看到坏掉的旧窗口状态。详情内容额外包在统一 `SettingsPage` 容器内，不显示页面级标题/副标题，直接呈现设置组，让内容占据真正有价值的空间。

右侧不再使用滚动 `Form` 作为根容器，因为内容较少时滚动条会显得突兀且靠近中部。改为 `SettingsGroup` + `SettingsRow` 的非滚动分组布局：组间距 24pt、页面内边距 34/36/28pt，分组随详情区展开，行内 label 与控件两端对齐。各页面统一使用 `.controlSize(.small)` 的密度。About 图标卡片压缩到 46pt 图标与 12/14pt 内边距，保留 glass 作为唯一视觉锚点，但降低视觉重量。

### 删除死代码

`SettingsSidebar.swift` 中的 `SettingsRoute` / `SettingsSidebar` 此前未被引用，是上次重构残留。本次实现复用 `SettingsRoute` 作为统一导航枚举（替换 `SettingsSelection`），但旧文件需要重写。

`SettingsTab` 枚举在 `SettingsWindowPresenter` 中被用作外部入口（菜单栏面板"关于"按钮直接跳转 About 页），保留并增加从 `SettingsTab` 到 `SettingsRoute` 的桥接。

## Risks / Trade-offs

- **风险**：删除 `SettingsView.swift` 后，`SettingsWindowPresenter` 中依赖 `SettingsTab` 的跳转行为可能失效。**缓解**：新视图通过 `@State selection: SettingsRoute` 与 NotificationCenter 桥接，`SettingsWindowPresenter.open(_:tab:)` 内部把 `SettingsTab` 翻译成对应 `SettingsRoute`。
- **风险**：`enabledMetrics` 的持久化字典在用户更换 App 版本后，旧 key 可能与新定义不匹配。**缓解**：`isMetricEnabled` 在查不到记录时回退到 `availableMetrics` 的 `isDefault`，旧版本残留的未知 id 直接忽略。
- **权衡**：每模块详情页"检测项目" Section 当前只有占位项，看上去略空。可接受：框架就位比内容堆砌优先级更高，避免后续重构。

## Migration Plan

1. 先实现 `MetricSwitch` 数据模型与 `MonitorSettings` 扩展，不动 UI（可独立通过单元测试或编译验证）
2. 新建 `SettingsRootView.swift`，逐步把现有 `GeneralSettingsView` / `AboutSettingsView` 内容接进来
3. 删除旧 `SettingsView.swift`，改 `HagimiMonitorApp.swift` 的 `Settings { ... }` 入口
4. 重写 `SettingsSidebar.swift`，让 `SettingsRootView` 引用它
5. 更新 `SettingsWindowPresenter` 的 tab→route 桥接
6. App Store 与 Direct 双 target 各自构建验证

## Open Questions

- 检测项目清单的具体内容（哪些子项归 CPU、哪些归 GPU 等）由用户后续单独提供，本提案不预设
- 是否要给"重置默认值"按钮单独的二次确认？暂按不需要处理（次操作 + 单一模块作用域，影响小）
