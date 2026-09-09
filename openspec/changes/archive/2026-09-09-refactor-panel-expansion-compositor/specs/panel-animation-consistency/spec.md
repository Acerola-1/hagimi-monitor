## MODIFIED Requirements

### Requirement: Version-aware detail disclosure transition
The system SHALL use one top-anchored clipped-reveal behavior for every expandable panel section on macOS 15 and macOS 26+. Expanded content SHALL remain at its natural size and fixed relative to the row header while the lower reveal boundary moves; the transition SHALL NOT resize, scale, or recursively relayout the hosted detail content on each animation frame.

#### Scenario: Unified transition on all supported versions
- **WHEN** any expandable row is expanded or collapsed on macOS 15 or macOS 26+
- **THEN** the content SHALL use the same disclosure motion on both versions
- **AND** the disclosure SHALL NOT introduce a second geometric animation that competes with panel resizing

#### Scenario: Height change is smooth without flicker
- **WHEN** a row is expanded or collapsed
- **THEN** the card reveal, following rows, footer, and panel boundary SHALL move as one coherent transition
- **AND** no removal frame or empty strip SHALL appear against a mismatched panel size

#### Scenario: Detail content keeps drawer geometry
- **WHEN** an expansion animation is paused at an intermediate point
- **THEN** the visible detail content SHALL retain its natural scale and top position
- **AND** only the lower clipping boundary SHALL determine how much content is revealed

### Requirement: Version-aware expansion animation
The system SHALL drive every expansion state change through one frame-rate-independent spring motion shared by the real panel size and all affected content geometry. The behavior SHALL be identical on macOS 15 and macOS 26+ and SHALL NOT depend on refresh-rate-specific branches.

#### Scenario: Expansion toggles uniformly
- **WHEN** a row is toggled on macOS 15 or macOS 26+
- **THEN** the row reveal, following rows, footer, and panel height SHALL be sampled from the same motion state
- **AND** no per-version SwiftUI geometry animation SHALL run in parallel

#### Scenario: Top edge stays anchored during animation
- **WHEN** the menu bar panel grows or shrinks from an expansion toggle
- **THEN** its top edge SHALL remain anchored at the menu bar throughout the animation

#### Scenario: Motion reverses without restarting
- **WHEN** the user reverses or redirects an expansion before the current spring settles
- **THEN** the new motion SHALL start from the current visible position
- **AND** it SHALL inherit the current velocity without resetting to rest

### Requirement: 多行同时展开时滚动揭示目标确定
当一次操作展开多个可折叠行且内容超过面板可用高度时，系统 SHALL 选择确定的新内容作为揭示目标，并使滚动位移与本次展开使用同一运动状态，不得启动独立的滚动动画。

#### Scenario: 双击展开全部行
- **WHEN** 用户在面板高度受屏幕限制时双击表头一次性展开全部行
- **THEN** 面板滚动到确定的新展开内容位置并使其可见
- **AND** 不会停留在与本次展开无关的任意行
- **AND** 滚动揭示与卡片展开之间不会出现分段或相位错位

## ADDED Requirements

### Requirement: 展开动画逐帧几何一致性
系统 SHALL 从同一份有效几何状态生成卡片可见高度、后续卡片位置、底部操作区位置和面板高度，使每个实际呈现的动画帧都满足静止布局的间距约束。

#### Scenario: 单行展开或收起
- **WHEN** 任一模块行正在展开或收起
- **THEN** 该行下边缘与下一行顶边的距离在每个实际呈现帧中均为 6pt
- **AND** 面板底边与底部操作区的距离在每个实际呈现帧中均为 10pt

#### Scenario: 动画中途逐帧检查
- **WHEN** 测试在动画过程中的任意呈现帧截取画面
- **THEN** 画面 SHALL 不包含窗口空白、内容裁切、卡片重叠或行距撕裂
- **AND** 该帧的全部可见几何 SHALL 构成一份有效的中间布局

#### Scenario: 多行和嵌套分区同时变化
- **WHEN** 多个模块或显示器内嵌分区在同一操作中改变展开状态
- **THEN** 所有受影响的高度与位置 SHALL 共同满足相同的 6pt 行距和 10pt 底边距约束

### Requirement: 实时材质在展开期间保持活跃
系统 SHALL 在完整展开/收起过程保持面板与卡片的原生实时材质、动态背景混合和系统窗口阴影，不得以静态位图、预渲染快照或栅格化替代可见内容。

#### Scenario: 面板后方内容在动画期间变化
- **WHEN** 面板后方的桌面或窗口内容在展开动画期间移动或改变
- **THEN** 可见材质 SHALL 持续反映实时背景变化
- **AND** 卡片内容 SHALL 不出现快照切换、缩放变形或清晰度变化

### Requirement: 跳帧时保持整体一致
系统 SHALL 以绝对时间计算动画状态，不假设每个显示刷新周期都能产生新帧；当系统负载导致某次更新或呈现缺失时，下一帧 SHALL 将全部相关几何共同推进到同一时间状态。

#### Scenario: 低刷新率或系统高负载
- **WHEN** 面板在 60Hz、低电量模式或高系统负载下展开或收起
- **THEN** 动画 SHALL 不使用针对特定刷新率的参数分支
- **AND** 任一漏过的动画采样 SHALL 不导致窗口、卡片、Footer 或滚动位移出现相互独立的进度

### Requirement: 两种面板宿主共享运动语义
菜单栏瞬态面板与快捷键唤起的可钉住面板 SHALL 使用相同的展开几何、卷出方式、中断续速和实时材质要求，同时保留各自的定位与关闭行为。

#### Scenario: 比较两种面板
- **WHEN** 用户在菜单栏面板和可钉住面板中展开同一模块
- **THEN** 两者 SHALL 呈现相同的卡片内部卷出和兄弟行下推运动
- **AND** 钉住、失焦关闭及菜单栏锚定等宿主特有行为 SHALL 保持不变
