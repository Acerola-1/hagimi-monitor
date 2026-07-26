# 模块大卡片显示方式（按模块独立设置）

## Why

2026-07-24 弃用的「悬停放大为大卡片」方案（存档：`openspec/changes/archive/2026-07-24-big-card-and-tear-off/`）死于**交互层**：悬停浮标发现成本高、三层交互过度复杂。但「大卡片」形态本身有价值——hero 大数字 + TOP 进程的仪表盘式呈现，让用户关心的模块呼出即一眼扫读。本次以**静态配置**取代动态交互复活卡片形态：在各模块设置页新增「显示方式」选项（列表行 / 大卡片），面板内交互仍只保留「点击展开」单层，规避当年全部交互层弊病。

## What Changes

- 每个模块设置页（CPU / GPU / 内存 / 磁盘 / 网络 / 电池）新增「显示方式」分段选择：**列表行**（默认，行为不变）/ **大卡片**
- 设为「大卡片」的模块在面板中渲染为铺满面板宽度的方卡：hero 主值 + 指标网格 + TOP 进程列表（固定 5 行横杠占位），**内容常显、不参与展开/收起交互**
- 「显示方式 = 大卡片」时，该模块设置页隐藏「默认展开」开关（卡片常显，默认展开无意义）；持久化的 `defaultExpandedKinds` 值保留不清除，切回列表行时恢复生效
- 标题区双击「全部展开/收起」仅作用于列表行模块，卡片模块不受影响
- 进程采样上报集合从「展开的行」扩展为「展开的行 ∪ 卡片模块」（面板可见时），复用既有按需采样记账
- 从 git 历史（`61febc61`）恢复 `MetricCardView` / `CardProcessList` 并改造：剥离悬停浮标（RowEnlargeAffordance）、放大/还原按钮与 `enlargedKinds` 交互态；**不复活**拖拽撕离
- 显示器模块（DirectOnly）不参与本次改动，维持现状

## Capabilities

### New Capabilities

- `module-display-style`: 按模块的面板显示方式设置（列表行/大卡片）——设置项持久化、面板卡片渲染、与「默认展开」及双击全展开的互斥规则、卡片模块的进程采样记账

### Modified Capabilities

（无——现有 spec 均不涉及展开/显示形态的需求级行为；`monitor-panel` spec 仅覆盖本地化，新增卡片文案作为 `module-display-style` 的场景约束，本地化完整性由 `localization-completeness` 既有要求自然覆盖，无需求变更）

## Impact

- `HagimiMonitor/MonitorSettings.swift`：新增按模块显示方式的持久化（`[MonitorKind: 显示方式]`，UserDefaults 逐 kind 键或数组键）
- `HagimiMonitor/MonitorPanelView.swift`：`row(for:)` 按显示方式分流；恢复并改造 `MetricCardView` / `CardProcessList`（约 300 行）；`reportActiveProcessKinds` 上报展开 ∪ 卡片；`toggleAllExpansion` / `allVisibleRowsExpanded` 限定列表行
- `HagimiMonitor/Views/Settings/ModuleSettingsView.swift`：新增「显示方式」分段选择；卡片档隐藏「默认展开」行
- `HagimiMonitor/Localizable.xcstrings`：新增设置项与卡片相关文案（zh-Hans / en / ja 三语）
- `HagimiMonitorTests/SettingsTests.swift`：显示方式默认值与持久化测试
- 历史硬约束必须遵守：卡片高度严格自适应内容（禁止强制正方形）、禁止 GeometryReader 宽度→高度反馈环（破坏 `FluidPanelSizeReader` 高度上报）、Row/Card Equatable 跳帧、TOP 进程固定 5 行占位防高度跳变、电池卡片单主值规则
