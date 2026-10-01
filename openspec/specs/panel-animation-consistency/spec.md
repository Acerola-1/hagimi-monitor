# panel-animation-consistency Specification

## Purpose
Defines version-aware panel animation behavior so detail disclosure, expansion, and progress-meter transitions stay smooth and consistent across supported macOS versions.

## Requirements

### Requirement: Version-aware detail disclosure transition

面板所有可展开模块及嵌套分区 SHALL 使用一致的揭示运动策略，在 macOS 15 及更新系统上保持相同的运动语义。明细、后续卡片、底部入口、可见外框、圆角描边及阴影 SHALL 在整个过渡中保持对应关系，不出现直线断层、独立跳步或收尾补跳。

#### Scenario: Unified transition on all supported versions
- **WHEN** 用户在任一支持的系统上展开或收起任一可用模块或显示器嵌套分区
- **THEN** 明细从所属行头下方连续揭示或隐藏
- **AND** 后续内容与可见外框的位移保持同一几何关系

#### Scenario: Height change is smooth without flicker
- **WHEN** 面板高度因展开、收起或分页内容变化而改变
- **THEN** 底部圆角、描边和阴影沿可见轮廓连续变化
- **AND** 背景不闪烁，内容不被不匹配的直线边界切断，终态不追加可见尺寸跳变

### Requirement: Version-aware expansion animation

用户展开状态变化 SHALL 采用一致的、可中断的运动；中途反转 SHALL 从当前可见位置及速度续接，正常展开收起采用已认可 Demo 的收敛运动风格。运动 SHALL 保持合法揭示范围，并遵守系统减弱动态效果设置。

#### Scenario: Expansion toggles uniformly
- **WHEN** 用户切换任一模块的展开状态
- **THEN** 所有受该操作影响的内容和外框共同响应
- **AND** 不因系统版本不同引入另一套竞争的高度动画

#### Scenario: Top edge stays anchored during animation
- **WHEN** 菜单栏面板因展开操作变高或缩短
- **THEN** 可见顶边保持菜单栏锚定位置，变化向下发生

#### Scenario: Rapid reversal continues current motion
- **WHEN** 用户在动画中再次切换同一分区或交错切换多个分区
- **THEN** 新运动从当前呈现状态续接，不重播起始帧
- **AND** 速度保持连续；到达合法揭示边界时可消除指向边界外的速度，避免空白露出或行头被压缩

#### Scenario: Reduced motion applies the same final geometry
- **WHEN** 系统启用减弱动态效果
- **THEN** 展开操作直接应用相同的合法终态几何
- **AND** 命中、滚动、外框与辅助功能状态仍一致

### Requirement: Progress meter smooth transition
The system SHALL animate the progress bar width change in `ProgressMeter` when the value changes.

#### Scenario: Progress bar animates value change
- **WHEN** the `value` parameter of `ProgressMeter` changes
- **THEN** the width transition SHALL animate with `.easeInOut(duration: 0.3)`

### Requirement: 多行同时展开时滚动揭示目标确定

双击表头全部展开或全部收起时，面板 SHALL 以首个可见模块为顶部锚点，滚动目标为顶部；从全部收起开始展开时，首个模块 SHALL 在整个运动中保持在主体顶部。单行操作 SHALL 自动揭示该行；其他批量操作的揭示目标 SHALL 根据当前可见顺序确定，指向最后一个本次新展开的可用分区。滚动 SHALL 服从合法范围，用户滚动输入 SHALL 优先于自动揭示。

#### Scenario: 双击展开全部行
- **WHEN** 用户在封顶面板双击表头展开全部行
- **THEN** 滚动目标为顶部，首个可见模块保持在主体开头
- **AND** 从全部收起开始展开时，内容从首个模块向下连续展开；超过视口的内容可继续滚动访问

#### Scenario: 用户在自动揭示期间滚动
- **WHEN** 用户在自动滚动期间操作触控板或鼠标滚轮
- **THEN** 自动揭示让出滚动控制权，保留当前可见位置与用户滚动惯性
- **AND** 展开运动继续，不把用户拉回旧目标

### Requirement: 显示器信息分区参与展开状态重置
面板的显示器信息分区的展开状态 SHALL 与其余分区一致地参与面板隐藏重置与默认展开设置，两种分发构建下行为一致。

#### Scenario: 沙盒构建重开面板
- **WHEN** App Store（沙盒）构建下用户展开显示器信息分区、关闭面板再重新打开
- **THEN** 该分区按当前默认展开设置呈现（与 Direct 构建行为一致）
- **AND** 不保留上次会话的临时展开状态

### Requirement: 动态结构变化保持运动连贯

指标显隐、模块顺序、设备拓扑、嵌套明细、语言或可用宽度变化导致内容尺寸改变时，面板 SHALL 采用更新后的完整几何，并从当前呈现状态连续过渡；过时尺寸或过时完成回调 SHALL NOT 覆盖较新的状态。

#### Scenario: 动画中设备列表或电源分页变化
- **WHEN** 展开期间显示器/蓝牙设备出现或消失，或用户切换不同高度的电源分页
- **THEN** 内容和后续卡片依据最新结构继续运动
- **AND** 不发生一次性补高度跳变、重叠、残留明细或空白尾部

#### Scenario: 电源分页改变自然高度
- **WHEN** 用户在电源明细中切换不同高度的分页
- **THEN** 内容使用新页自然尺寸，卡片和后续模块由统一运动轨迹连续过渡
- **AND** 保留当前合法滚动位置，不重放上次展开的自动揭示目标；新页变短导致位置超界时连续钳制到合法范围
- **AND** 分页状态变更不启动与原生高度轨迹重叠的 SwiftUI 布局动画

#### Scenario: 电源从最短分页切换到较高分页
- **WHEN** 用户从进程排名等较短页面切换到较高的电源页面
- **THEN** 内容承载层保持当前屏幕范围内的预留容量，不随每次换页缩小再扩容
- **AND** 登记的自然高度仍来自真实页面，可见轮廓和后续卡片由统一轨迹连续变化
- **AND** 承载尺寸变化不作废并重播上一版遮罩计划

#### Scenario: 隐藏与重新打开
- **WHEN** 动画中关闭面板，再按现有默认展开设置重新打开
- **THEN** 旧动画不再写入新会话
- **AND** 显示器及其他分区均按新会话的有效状态呈现

### Requirement: 全模块性能与可视验收

新运动 SHALL 在完整可用模块配置下进行同机基线对照及真实背景可视验收，覆盖正常负载、CPU 压力和 CPU/GPU 同时压力。性能报告 MUST 区分应用计算成本、主线程探针、录屏采样及实际可见停顿，不以局部 Demo 数值或构建成功代替全量验收。

#### Scenario: 负载下展开收起验收
- **WHEN** 对两种分发构建执行单模块、交错展开、全部展开及快速反转矩阵
- **THEN** 报告每个可用模块、普通与置顶面板的实际检查结果及未覆盖项
- **AND** 候选的展开归因排版/窗口提交成本应以实测证明下降，可见运动无新增底边断层、跳步或可读性回退
- **AND** 未取得完整证据时不得宣告全部模块通过
