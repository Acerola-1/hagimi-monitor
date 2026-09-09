## ADDED Requirements

### Requirement: 面板可见期菜单栏平滑定时器暂停
当监控面板处于打开（可见）状态时，系统 SHALL 暂停菜单栏负载环的平滑定时器，将菜单栏状态项重绘降频为随采样数据更新（1Hz），全量让渡主线程与合成器余量。

#### Scenario: 打开面板时暂停菜单栏高频重绘
- **WHEN** 用户点击菜单栏图标呼出监控面板
- **THEN** 菜单栏负载环的平滑推进定时器停止触发，直接发布量化目标值
- **AND** 面板关闭收起后，平滑定时器按需恢复

### Requirement: GPU 硬件加速虚线流向管线与汇流点呼吸
电源流向图中的活跃导管 SHALL 移除 30fps `TimelineView` 驱动，改由 `CAShapeLayer`（配合 `CABasicAnimation(keyPath: "lineDashPhase")`）在 Render Server 独立硬件加速呈现大脉冲段流动（8pt 虚线 + 12pt 间距）；汇流点 SHALL 采用独立声明式呼吸动画（缩放与透明度缓动）；空载待机状态下流光管线 SHALL 自动平滑静止。

#### Scenario: 充电与放电方向感流动
- **WHEN** 设备处于充电或放电状态
- **THEN** 导管虚线按对应电流物理方向平滑涌动，视觉质感与 1.5.4 原版大脉冲段一致
- **AND** 动画由合成器直接执行，主线程 CPU 占用保持在 0%~0.1% 极限区间
- **AND** 汇流点保持呼吸发光，不因移除 TimelineView 变为静态死点

#### Scenario: 待机空载静止
- **WHEN** 系统净功率波动在 ±0.3W 以内
- **THEN** 流光管线平滑停止流动，保持静态底轨呈现，杜绝空载绘制消耗

### Requirement: 面板唤出单次脉冲
面板展开或唤出时，状态角标指示器（如 `SYSTEM·LIVE`）SHALL 执行单次平滑呼吸脉冲，而非持续性循环逐帧动画。

#### Scenario: 唤出触发单次呼吸
- **WHEN** 用户点击唤出面板
- **THEN** 状态角标完成 1 次轻微脉冲高亮后稳定在常态
- **AND** 后续展示期间不占用 CADisplayLink 或定时器
