## MODIFIED Requirements

### Requirement: Version-aware detail disclosure transition
所有面板可展开分区 SHALL 在 macOS 15 与 macOS 26+ 使用一致的顶部揭示语义，明细内容保持原有字体、尺寸与内部间距，窗口边界与内容揭示随同一运动状态变化。系统 SHALL 保留行头完整显示，并使收起态明细完全不可见、不可交互。

#### Scenario: Unified transition on all supported versions
- **WHEN** 用户在 macOS 15 或 macOS 26+ 展开或收起任意可展开分区
- **THEN** 分区 SHALL 以相同的弹簧揭示行为从顶部展开或收回
- **AND** 文字、图表与控件 SHALL 保持自然尺寸，不随揭示进度缩放或重新折行

#### Scenario: Height change is smooth without flicker
- **WHEN** 用户展开或收起一行
- **THEN** 面板高度、卡片边缘与可见明细 SHALL 一致地连续变化
- **AND** 不得出现明细移除残帧、两段式跳变或结束后补调窗口高度

#### Scenario: Collapsed header is complete and details are absent
- **WHEN** 某分区处于精确收起态
- **THEN** 行头图标、标题、读数与折线图 SHALL 完整显示在原有留白中
- **AND** 明细分隔线、核心环、文字和控件 SHALL 没有任何像素露出
- **AND** 隐藏的明细 SHALL 不接受鼠标事件、键盘焦点或辅助功能导航

#### Scenario: Controls during partial reveal
- **WHEN** 分区尚未完全展开且用户点击明细区域
- **THEN** 只有当前可见区域内且语义上可用的控件 SHALL 能响应
- **AND** 收起当前持有键盘焦点的明细时，焦点 SHALL 返回可见行头或对应可见控制

### Requirement: Version-aware expansion animation
面板展开 SHALL 在两个分发渠道和支持的系统版本中保留 response 0.32、dampingFraction 0.82 的弹簧手感。窗口尺寸、卡片揭示、兄弟位置与自动滚动 SHALL 由同一运动状态保持一致；隐藏重置、首次展示与减少动态效果模式 SHALL 使用准确的同步状态。

#### Scenario: Expansion toggles uniformly
- **WHEN** 任意分区在 macOS 15 或 macOS 26+ 被切换
- **THEN** 系统 SHALL 使用相同的展开语义和弹簧参数
- **AND** 窗口与内容 SHALL 不运行可相互漂移的独立展开轨迹

#### Scenario: Top edge stays anchored during animation
- **WHEN** 菜单栏面板因展开或收起而改变高度
- **THEN** 面板顶边 SHALL 保持菜单栏下方的锚点
- **AND** 钉住面板的同类操作 SHALL 保持其当前顶边位置

#### Scenario: Rapid reversal preserves motion
- **WHEN** 用户在运动尚未结束、可见几何未碰到硬边界时反向点击或重定向目标
- **THEN** 新运动 SHALL 从当前实际运动位置和速度连续接续
- **AND** 不得先跳回起点、跳到旧终点或将速度归零再启动

#### Scenario: Spring reaches a geometric boundary
- **WHEN** 欠阻尼运动到达零揭示高度或屏幕视口上限
- **THEN** 行头 SHALL 保持完整，揭示高度 SHALL 非负，真实窗口 SHALL 保持在可用屏幕范围内
- **AND** 卡片位置、视口与窗口 SHALL 使用同一合法几何结果
- **AND** 边界处理 SHALL 不造成终态明细重新露出或额外收尾跳变

#### Scenario: Hidden reset and reduced motion
- **WHEN** 面板隐藏后按默认设置重置、首次展示，或用户启用减少动态效果
- **THEN** 系统 SHALL 同步呈现完整目标布局与匹配的真实窗口尺寸
- **AND** 不得播放初始化补间或在下次展示时继续上次未结束的轨迹

#### Scenario: Two panels remain independent
- **WHEN** 菜单栏面板与钉住面板同时存在，其中一个发生展开操作
- **THEN** 另一个面板的展开位置、速度、目标和滚动位置 SHALL 不被此次操作改变

### Requirement: 多行同时展开时滚动揭示目标确定
一次操作展开多个分区时，系统 SHALL 按当前视觉顺序选择最后一个实际新展开且有内容的分区作为自动揭示目标。自动滚动 SHALL 与展开几何保持一致，并允许用户滚动连续接管。

#### Scenario: 双击展开全部行
- **WHEN** 用户在面板受屏幕高度限制时双击表头展开多行
- **THEN** 系统 SHALL 以视觉顺序中最后一个实际新展开且有内容的分区作为唯一目标
- **AND** 目标底缘 SHALL 在合法滚动范围内尽量对齐主体视口底缘
- **AND** 不得因集合遍历顺序不同而停在任意行

#### Scenario: 内容未触及屏幕上限
- **WHEN** 展开后的全部主体内容仍能在面板内完整显示
- **THEN** 系统 SHALL 保持主体滚动偏移为零
- **AND** 不得因动画瞬时测量差异而闪现溢出渐隐提示

#### Scenario: 用户在自动揭示期间滚动
- **WHEN** 用户在自动揭示尚未结束时使用滚轮或触控板
- **THEN** 用户滚动 SHALL 从当前可见偏移连续接管
- **AND** 自动揭示 SHALL 不再争抢偏移，卡片展开仍能继续完成

## ADDED Requirements

### Requirement: Geometry changes remain coherent during disclosure
语言、宽度、字体环境、真实内容结构与显示器集合变化时，系统 SHALL 使用有效的新几何完成展示，不依赖过期测量隐藏行头、重复计算嵌套高度或在动画结束后跳变校准。

#### Scenario: Initial geometry is not available
- **WHEN** 用户请求展开的内容尚未得到有效自然尺寸
- **THEN** 系统 SHALL 保持完整且可用的收起行头，准备好尺寸后再呈现展开
- **AND** 不得先用零尺寸启动，再跳到异步回填的高度

#### Scenario: Geometry changes during motion
- **WHEN** 动画期间语言、宽度、字体环境或内容结构改变
- **THEN** 系统 SHALL 连贯地采用最新有效内容与尺寸
- **AND** 不得继续应用旧内容的迟到测量或重置仍有效运动的速度

#### Scenario: Nested display sections toggle together
- **WHEN** 显示器分区及其内嵌区域同时展开、收起或因设备移除而改变可用性
- **THEN** 可见高度 SHALL 仅包含当前可见层级各自的一次贡献
- **AND** 关闭外层后，内层 SHALL 不继续撑高窗口或响应隐藏控件事件

### Requirement: Disclosure performance and presentation are validated together
展开性能改善 SHALL 与视觉保真同时验收；系统 SHALL 在已记录的相同设备、构建、刷新率和负载条件下消除可重复归因于展开内容递归布局的 40–50ms 慢帧。验证 SHALL 区分应用几何一致性与屏幕实际呈现，不把状态更新完成当成显示完成。

#### Scenario: Controlled 60Hz performance comparison
- **WHEN** 对相同内容执行预热后的单行、全量展开和快速反转对照
- **THEN** 验证记录 SHALL 包括应用主线程耗时分布、帧间隔、运行环境和重复次数
- **AND** SHALL 证明递归内容布局热点与其造成的慢帧得到消除，同时保持本规格规定的视觉与交互

#### Scenario: Delayed frame under load
- **WHEN** CPU 或系统负载使一次显示更新延迟
- **THEN** 下一次应用更新 SHALL 从一致的运动时刻推进全部关联几何
- **AND** 在受测环境中不得出现内容与窗口分别追赶形成的两段跳变

#### Scenario: Motion is settled or the panel is hidden
- **WHEN** 所有展开运动已经收敛或面板被隐藏
- **THEN** 展开功能 SHALL 不再保留持续的逐帧驱动工作

