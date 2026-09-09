## MODIFIED Requirements

### Requirement: Self-hosted menu bar panel window
系统 SHALL 使用自行管理的真实面板窗口展示监控内容，维持菜单栏工具的生命周期、采样恢复与隐藏行为。初始窗口尺寸 SHALL 来自有效的内容几何；可见区域、原生阴影和鼠标事件边界 SHALL 随真实窗口尺寸保持一致。

#### Scenario: Panel opens from status item
- **WHEN** 用户左键点击菜单栏状态项且面板处于隐藏状态
- **THEN** 系统 SHALL 按有效内容几何准备好匹配尺寸，将面板展示在状态项下方
- **AND** SHALL 恢复可见面板需要的进程采样
- **AND** 不得先展示错误大小再通过测量回填跳变

#### Scenario: Panel toggles closed on second click
- **WHEN** 用户在面板可见时再次左键点击状态项
- **THEN** 系统 SHALL 隐藏面板

#### Scenario: App remains an accessory
- **WHEN** 应用启动
- **THEN** 应用 SHALL 继续以菜单栏辅助应用运行，不显示 Dock 图标
- **AND** 不得自动打开普通主窗口

### Requirement: Top-anchored smooth resize
面板 SHALL 通过匹配当前内容几何的真实窗口尺寸平滑展开与收起。菜单栏面板的顶边 SHALL 锚定于菜单栏，钉住面板 SHALL 保持自身当前顶边；窗口与内容 SHALL 共同推进，而非分别对最终高度进行动画并在结束后对账。

#### Scenario: Expanding a row grows the panel downward
- **WHEN** 用户在可见面板中展开一行
- **THEN** 面板 SHALL 向下增长，并在每次更新中与当前可见内容高度一致
- **AND** 顶边 SHALL 保持对应宿主的锚点

#### Scenario: No flicker on resize
- **WHEN** 面板因展开或收起而改变高度
- **THEN** 背景材质与顶部 SYSTEM · LIVE 区域 SHALL 保持连续，不闪烁或表现为重新加载

#### Scenario: Content reports size instantly
- **WHEN** 有效尺寸已经准备好且用户触发展开
- **THEN** 系统 SHALL 使用该尺寸和当前运动状态同步推进卡片与窗口
- **AND** 不得等待逐帧内容高度回报再启动另一条窗口追赶动画

#### Scenario: Native shadow and outside events follow the visible panel
- **WHEN** 面板在任意中间高度显示
- **THEN** 系统 SHALL 保留真实窗口的原生阴影和原有圆角处事件语义
- **AND** 面板真实 frame 外的区域 SHALL 不被额外透明包络捕获
- **AND** 点外关闭、失去焦点关闭及菜单栏全屏集成 SHALL 保持原有行为

## ADDED Requirements

### Requirement: Panel visual geometry and material fidelity
性能重构 SHALL 完整保留当前面板的材质连续性、色彩、排版、留白和圆角。面板在 340pt 宽度下 SHALL 保持 328pt 卡片宽度；左右边距 SHALL 为 6pt、顶部留白为 8pt、底部留白为 6pt、行间距为 6pt，卡片与外框 SHALL 分别保持 continuous 14pt 与 continuous 20pt 圆角。

#### Scenario: Resting geometry matches the baseline
- **WHEN** 面板在相同设备、语言、内容和外观条件下处于全收起或目标展开态
- **THEN** 几何、字体、指标网格、明细缩进和各层留白 SHALL 与重构前基线一致
- **AND** 在其他受支持面板宽度下，卡片宽度 SHALL 等于实际面板宽度减去两侧各 6pt

#### Scenario: Card bottom edge during disclosure
- **WHEN** 某卡片处于部分揭示高度
- **THEN** 卡片底部 SHALL 按当前可见高度保持完整圆角与对应材质边缘
- **AND** 不得出现从完整长卡片中途切断形成的平底或材质拼接缝

#### Scenario: Material remains live across appearances
- **WHEN** 用户在亮暗外观、不同桌面背景或支持的系统版本下观察和移动面板
- **THEN** 材质 SHALL 保持与各自系统基线一致的实时透光、层级与边缘效果
- **AND** 不得以冻结截图、缩放内容或机械拼贴色块替代现有外观

### Requirement: Screen-capped body preserves existing content flow
面板受屏幕可用高度限制时 SHALL 固定顶部 Header，仅主体内容滚动，底部操作按钮 SHALL 继续属于主体内容流。主体视口、合法滚动范围和真实窗口边界 SHALL 保持一致。

#### Scenario: Content crosses the screen height cap
- **WHEN** 展开使自然内容高度从低于上限变为高于上限
- **THEN** 真实窗口 SHALL 停留在可用屏幕范围内，主体继续以滚动视口展示
- **AND** Header SHALL 保持固定，底部操作按钮继续随主体滚动
- **AND** 视口下方到面板底缘的留白 SHALL 保持 6pt

#### Scenario: Content fits again after collapse
- **WHEN** 收起使自然内容高度重新低于屏幕上限
- **THEN** 面板 SHALL 连贯地恢复与自然内容匹配的高度
- **AND** 超出新范围的滚动偏移 SHALL 连贯地归入合法范围，不产生空洞或额外尾帧修正

#### Scenario: Screen or backing scale changes
- **WHEN** 屏幕可用高度、面板所属屏幕或显示缩放比例变化
- **THEN** 面板 SHALL 使用当前屏幕的有效几何与像素对齐策略
- **AND** 保持当前内容、原有窗口定位规则、卡片间距和外侧留白
