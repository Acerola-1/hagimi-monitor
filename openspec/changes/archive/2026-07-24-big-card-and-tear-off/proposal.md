# 大卡片 + 拖拽撕离方案（已弃用）

> 状态：**archived** — 2026-07-24 决定移除。  
> 原因：面板宽度锁死 ~320pt，大卡片在面板内无法带来真正的信息增益（只是字号放大，并非信息密度提升）；三层交互（点击展开 / 悬停放大 / 拖拽撕离）对用户心智模型过度复杂；撕离出的独立窗口虽有价值但作为 MVP 过早，暂不保留。

## 方案概述

在原有"点击展开/收起"基础上新增两层交互：

1. **悬停放大浮标（RowEnlargeAffordance）**：鼠标悬停行时右上角淡入小圆钮 `arrow.up.left.and.arrow.down.right`，点击后该行变为铺满面板宽度的方卡（MetricCardView）。
2. **拖拽撕离（RowDetachModifier + DetachedPanelController）**：在行上按住并拖动超过 26pt 阈值，即撕离为独立浮动 NSPanel 窗口，跟随光标直到松手。

## 涉及文件

- `HagimiMonitor/Views/Panel/DetachedPanelController.swift`（整文件，~360 行）
- `HagimiMonitor/MonitorPanelView.swift`（MetricCardView、CardProcessList、RowEnlargeAffordance、RowDetachModifier、enlargedKinds 状态、toggleEnlarged 函数）
- `HagimiMonitor/MonitorModels.swift`（PanelKind.detached(UUID)）
- `HagimiMonitor/AppDelegate.swift`（detachManager、detachCoordinator）
- `HagimiMonitor/Views/Panel/FluidPanelController.swift`（detachCoordinator 参数传递）
- `HagimiMonitor/Views/Panel/PinnedPanelController.swift`（detachCoordinator 参数传递）
- `HagimiMonitor/Localizable.xcstrings`（panel.enlarge、panel.restore）

## 关键设计决策

- **MetricCardView** 为方卡视图，Equatable 跳帧优化，包含 hero 指标区 + MetricDetailGrid + CardProcessList（固定 5 行横杠占位）。
- **DetachedPanelController** 使用 NSPanel（.titled/.nonactivatingPanel/.utilityWindow/.fullSizeContentView），NSVisualEffectView popover 毛玻璃圆角，QuickPanelPresentation 图钉/关闭控制。
- **DetachedPanelManager** 每模块最多一个独立面板（kindToID 去重），beginTearOff/updateTearOff/endTearOff 三阶段。
- **PanelDetachCoordinator** 闭包桥接视图层与 manager，避免视图直接持有 manager。
- 撕离动画：spawned at `.popUpMenu` level + alpha 0→1 淡入 0.12s，finishTearOff 降回 pin level。
- PanelKind.detached(UUID) 参与 expandedKindsBySource 按需采样记账。

## 弃用原因详述

1. 面板宽度 ~320pt，大卡片与展开详情的信息量几乎相同，只是视觉差异而非信息差异。
2. 悬停浮标发现成本高，新用户根本不知道存在。
3. "点击展开 → 悬停放大 → 拖拽撕离"三层交互过于复杂。
4. 如未来需要"大视图"，应在独立窗口中实现（脱离 320pt 约束），而非面板内。
