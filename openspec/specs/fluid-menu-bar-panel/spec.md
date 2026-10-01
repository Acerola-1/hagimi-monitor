# fluid-menu-bar-panel Specification

## Purpose
Defines the self-hosted menu bar panel, its visible geometry and classic material, input boundaries, screen placement, and presentation lifecycle across supported macOS versions.

## Requirements

### Requirement: Self-hosted menu bar panel window

系统 SHALL 继续通过应用自有面板窗口展示监控内容，维持菜单栏工具的启动与采样生命周期。承载容量可以大于可见轮廓，但用户感知的面板边界、背景、阴影和可交互区域 SHALL 以当前可见轮廓为准。

#### Scenario: Panel opens from status item
- **WHEN** 用户点击状态项且面板隐藏
- **THEN** 面板在状态项下方以当前内容的正确可见尺寸打开
- **AND** 恢复既有面板可见期采样，不显示尚未准备好的空白大窗口

#### Scenario: Panel toggles closed on second click
- **WHEN** 面板可见时用户再次点击状态项
- **THEN** 按原有关闭行为收起整个面板并完成可见期生命周期回收

#### Scenario: App remains an accessory
- **WHEN** 正式应用启动
- **THEN** 应用保持无 Dock 图标的菜单栏工具形态
- **AND** 不自动显示 Demo 控制窗或普通主窗口

### Requirement: Top-anchored smooth resize

菜单栏面板的可见顶边 SHALL 锚定菜单栏，内容高度变化通过可见轮廓连续向下展开或收起；真实窗口尺寸 SHALL NOT 成为展开运动期间另一套逐帧高度插值的来源。可见面板及滚动视口 SHALL 保持在当前屏幕的可用范围内。

#### Scenario: Expanding a row grows the panel downward
- **WHEN** 用户展开一行且内容尚未达到屏幕限高
- **THEN** 可见底边随内容向下移动，顶边位置保持不变
- **AND** 明细、后续行、圆角轮廓和阴影同步变化

#### Scenario: No flicker on resize
- **WHEN** 面板展开或收起
- **THEN** 底座、标题和行材质不闪烁或重新加载
- **AND** 不出现额外真实窗口高度动画与内容运动相互追赶

#### Scenario: Content reports size instantly
- **WHEN** 内容的自然尺寸因设置或结构变化更新
- **THEN** 新尺寸作为整体几何的新目标使用
- **AND** 尺寸登记本身不另行触发一条竞争的布局动画

#### Scenario: 内容达到或离开屏幕限高
- **WHEN** 展开或收起使内容穿过屏幕高度上限
- **THEN** 可见轮廓平滑进入或离开封顶状态，主体按现有滚动规则呈现
- **AND** 标题保持固定，所有内容仍可访问，终态无额外补跳

### Requirement: Dynamic status item icon hosting
The status item SHALL host the existing `MenuBarStatusLabel` SwiftUI view inside an `NSHostingView` embedded in `NSStatusItem.button`, so both the dynamic halo ring and the variable-width metrics label render correctly.

#### Scenario: Ring mode renders
- **WHEN** the menu bar display mode is the halo ring
- **THEN** the status item SHALL display the dynamic ring reflecting the current compute load

#### Scenario: Metrics mode renders variable width
- **WHEN** the menu bar display mode is metrics text
- **THEN** the status item width SHALL follow the hosting view's intrinsic content size

#### Scenario: Appearance change refreshes icon
- **WHEN** the effective appearance (light/dark) or theme preference changes
- **THEN** the hosted label SHALL refresh so the icon keeps sufficient contrast

### Requirement: Dismissal and system integration

面板 SHALL 保持外部交互关闭、焦点、菜单跟踪和多显示器行为，并按当前可见轮廓判定内外交互。不可见的透明承载区域 SHALL NOT 阻挡其他应用的鼠标点击、拖动或滚轮输入。

#### Scenario: Click outside closes panel
- **WHEN** 用户在可见轮廓外点击，包括透明承载区域
- **THEN** 普通面板按既有规则淡出关闭
- **AND** 点击到达原本位于该位置的外部应用，不需要补点一次

#### Scenario: Resign key closes panel
- **WHEN** 普通面板失去原有关闭规则所依赖的焦点
- **THEN** 按现有规则关闭，内部子弹窗或编辑交互不因宿主迁移被提前打断

#### Scenario: Full screen keeps menu bar
- **WHEN** 面板在其他应用全屏时显示
- **THEN** 保持既有菜单跟踪及 Spaces 行为，菜单栏在面板打开期间可用

#### Scenario: Panel clamps to screen edge
- **WHEN** 面板靠近屏幕边缘或切换到另一块尺寸/缩放不同的屏幕
- **THEN** 可见轮廓及滚动视口留在目标屏幕的可用范围内
- **AND** 不显示旧屏幕上的轮廓、错误阴影或透明事件遮挡

### Requirement: Discoverable status-item exit controls
The status item SHALL offer an explicit right-click Quit command and a double-click shortcut to quit HagimiMonitor, while a single left-click continues to toggle the panel.

#### Scenario: Right-click exposes Quit
- **WHEN** the user right-clicks the menu bar status item
- **THEN** the app SHALL show a context menu containing the localized Quit command

#### Scenario: Double-click quits without opening the panel
- **WHEN** the user double-clicks the menu bar status item
- **THEN** the app SHALL terminate
- **AND** the panel SHALL NOT flash open before termination

### Requirement: 普通与置顶面板共享运动行为

菜单栏面板、快捷键临时面板和置顶面板 SHALL 采用相同的模块运动与可见边界规则，同时保留各自既有定位、失焦、关闭、钉住及拖动行为。

#### Scenario: 置顶面板展开并移动
- **WHEN** 用户在置顶面板展开模块、拖动窗口或取消置顶
- **THEN** 内部运动保持与菜单栏面板一致的几何关系
- **AND** 窗口可拖动、取消置顶及关闭行为保持可用，透明区域不会阻挡下方应用

### Requirement: 面板隐藏后停止运动附加工作

面板隐藏或关闭后 SHALL 停止本会话的动画、事件边界监测及尺寸提交，并维持既有后台刷新门控；重新打开 SHALL 只恢复当前有效状态。正式运行 SHALL NOT 保留常驻的动画采样或 Demo 日志工作。

#### Scenario: 隐藏期间无残留驱动
- **WHEN** 动画中关闭最后一个可见面板
- **THEN** 旧回调不再更新宿主，运动相关定时工作停止
- **AND** 后台刷新和资源使用恢复既有隐藏期行为
