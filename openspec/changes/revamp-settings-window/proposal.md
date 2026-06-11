## Why

当前 `SettingsView` 存在结构性问题，导致视觉粗糙且不易扩展：

- 使用松散的 split/sidebar 布局容易在 Settings 场景里出现异常空白列或窗口过宽，无法稳定呈现小巧偏好窗口
- 侧栏 row 中嵌入 `Toggle`，与 `List(selection:)` 的选中态、点击区、键盘焦点冲突，是「bug 多」的主要来源
- 存在两套并存的导航枚举（`SettingsSelection` 实际使用，`SettingsRoute` 死代码），重构残留
- 固定 `frame(width: 520, height: 360)` 太挤，无法容纳即将到来的「每模块可置换检测项目」
- `GeneralSettingsView` / `ModuleSettingsView` 内容稀疏，`AboutSettingsView` 中「检查更新」用手拼 HStack，没有官方 `LabeledContent` 的对齐与无障碍
- Liquid Glass 应用混乱：菜单栏面板有 [[adapt-macos27-glass-appearance]] 在收敛过度玻璃，设置窗口也应同步采用克制策略

每个监控模块即将引入「可置换检测项目」功能（如 CPU 可选用户态/系统态/单核负载/热状态等子项），必须先为详情页准备好可扩展的 Section 框架。

## What Changes

- 用受控紧凑双栏重建设置窗口骨架，侧栏使用 `.listStyle(.sidebar)`，正文用 `Form { } .formStyle(.grouped)`
- 侧栏导航项**只显示** `Label`，移除内嵌 `Toggle`；模块的可见性开关挪到详情页第一个 Section
- 删除死代码 `SettingsRoute` / `SettingsSidebar.swift`（或将其作为新实现的基础重命名）
- 统一导航枚举为单一来源（`SettingsRoute`）
- 设置窗口尺寸改为可调整：`min 480×360, ideal 640×480`
- 详情页所有「label + 控件」用 `LabeledContent`，按钮主操作用 `.buttonStyle(.glassProminent)`，次操作用 `.buttonStyle(.glass)`
- About 页顶部 App 信息卡片用 `glassEffect(.regular, in: .rect(cornerRadius: 14))` 作为唯一玻璃点缀
- 为每个 `MonitorKind` 详情页预留「检测项目」Section，框架先就位（即使当前每个模块只有一项占位），新增数据模型 `MetricSwitch` 和 `MonitorSettings.enabledMetrics` 持久化
- 保持现有功能等价：所有持久化偏好、开机自启、主题/配色/负载环数据源、显示器控制、更新检查全部保留

## Capabilities

### New Capabilities

- `settings-window`: 设置窗口的导航结构、视觉规范、模块详情页框架、可置换检测项目数据模型

### Modified Capabilities

- 无（设置相关行为此前未形成独立 spec，本次首次建模）

## Impact

- 新增文件：`HagimiMonitor/Views/Settings/SettingsRootView.swift`（新的紧凑双栏容器）
- 重写文件：`HagimiMonitor/Views/Settings/SettingsSidebar.swift`、`GeneralSettingsView.swift`、`ModuleSettingsView.swift`、`AboutSettingsView.swift`
- 删除文件：`HagimiMonitor/SettingsView.swift`（功能合并到 SettingsRootView）
- 修改文件：
  - `HagimiMonitor/HagimiMonitorApp.swift`：`Settings { ... }` 入口替换为新视图
  - `HagimiMonitor/MonitorModels.swift`：新增 `MetricSwitch` 与 `MonitorKind.availableMetrics`
  - `HagimiMonitor/MonitorSettings.swift`：新增 `enabledMetrics` 状态与 `isMetricEnabled / setMetric` 接口
  - `HagimiMonitor/SettingsWindowPresenter.swift`：`SettingsTab` 与新 `SettingsRoute` 的桥接
- 不影响：所有 Sampler、`SystemMonitorSampler`、`MonitorStore` 业务逻辑；菜单栏面板 [[adapt-macos27-glass-appearance]] 工作流可独立推进
- 验证：App Store 与 Direct 双 target 构建均需通过；在浅色/深色与系统/浅色/深色三种主题切换下逐页校验
