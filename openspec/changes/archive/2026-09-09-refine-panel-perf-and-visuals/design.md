## Context

本变更基于 HagimiMonitor v1.5.4 的当前底座（`dev` 分支，包含单宿主物理弹簧架构、合并后的 `DisplaySection`、双页拓扑电源模块及静态指标审计体系）。
将社区 PR #105 中的优秀特性与性能优化，在严格遵从 1.5.4 架构规范、设计令牌与技术红线的前提下移植并合入。
动机与总体背景见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 将电源流向图的能量流动动画升级为基于 GPU/Metal 的虚线相位（Dash Phase）管线（首选 `NSViewRepresentable` + `CAShapeLayer`），主线程占用降为 0%，并保留汇流点独立呼吸辉光，维持 1.5.4 的大脉冲段视觉质感。
- 将展开区各组件（进程列表、网络/磁盘列表、风扇、蓝牙、电源流向图、显示器档案 `DisplaySection`）及指标网格（`ModuleMetricGrid`）的 28pt 左侧缩进改造为全宽顶格对称排版（两端 10pt 内衬），最大化横向可用空间。
- 同步更新单宿主几何解算器输入：`DisplaySection` 的 `PanelChildGroup` 登记值对齐为 `leading: 10, trailing: 10`，指标格半格预算从 106pt 调整为 120pt 并通过双语构建期静态审计。
- 为网络行速率与电源行功率提供统一定宽（70×20，间距 6pt）的 `theme.trackFill` 胶囊（Capsule）衬底，两行结构与度量严格统一（RowHeaderPillMetrics），彻底消除数字高频跳动时的排版推挤与行间错位。
- 在面板打开期间暂停/销毁菜单栏负载环的平滑推进定时器（对齐 1.5.4 既有收敛即停逻辑，作为防唤醒保险），降频为 1Hz 数据驱动。
- 在 Direct 版引入 `libIOReport` 屏幕、CPU、GPU 功耗差分采样，并在展开区呈现、设置页提供独立勾选；修复电池电流 UInt64 有符号补码与多级容量回退，且**严格保证流向判定始终仅看 IOPS 状态**。
- 在「设置 → 常规」提供持久化 Liquid Glass 开关（macOS 26+，默认关闭）；新建 `CompatiblePanelGlassHost` 实现窗口底座材质切换（开启用 `NSGlassEffectView`，关闭用 `.popover + .behindWindow`），行卡片严格保持 `.withinWindow` 毛玻璃。
- 全量维护中英双语 `Localizable.xcstrings`。

**Non-Goals:**
- 不重构 1.5.4 已定型的单宿主物理弹簧解算器（`SingleHostMotionCoordinator` / `PanelGeometrySolver`）。
- 不破坏双渠道沙盒隔离：`libIOReport` 绝不进入 App Store target。
- 不强制改变既有配色语义与文本高对比度系统。
- 不允许行卡片（Row Cards）使用 `.behindWindow` 或绑回液态玻璃容器，严防展开 resize 闪烁。

## Decisions

### 1. GPU 虚线相位（Dash Phase）替代 30fps TimelineView

- **背景与痛点**：原有 `PowerFlowDiagram` 展开期间常驻 `TimelineView(1/30s)`，每秒 30 次在主线程执行 Swift 闭包并重绘 Canvas，对主线程构成持续唤醒负担。
- **技术选型与实现路径**：
  - **首选硬件合成路径**：采用 `NSViewRepresentable` 封装 `CAShapeLayer`，通过 Core Animation 的 `CABasicAnimation(keyPath: "lineDashPhase")` 实现虚线平移动画。该动画完全运行在 WindowServer / Render Server 进程中，主线程 CPU 占用真正降为 0%。
  - **大脉冲段形态**：虚线段配置为 8pt 虚线 + 12pt 间距，线宽 2.2pt，端点圆角，完美继承 1.5.4 的大脉冲段视觉质感。
  - **流向与反转**：充电时由适配器向右/下推进；放电时电池垂直段反转向上。
  - **动态速率防跳变策略**：为避免频繁动态改变动画时长导致 Core Animation 重置相位产生视觉抖动，采用「固定循环时长（如 1.8s）+ 净功率 ±0.3W 门控」策略——低于阈值平滑静止，高于阈值匀速流转。
  - **汇流点呼吸辉光保留**：汇流点脱离 Canvas 逐帧计算，改用独立声明式/Core Animation 呼吸动画（对 `opacity` / `transform.scale` 执行 `easeInOut` 重复缓动），保持视觉灵动感。
  - **A/B 视觉验收**：在集成阶段必须与当前 1.5.4 dev 原版展开状态进行 A/B 目测对比，确保脉冲体量与质感无退步。

### 2. 全宽顶格对称排版与几何解算器联动

- **排版决策**：
  - 展开区明细全量去缩进：CPU 进程列表、网络/磁盘列表、风扇、蓝牙列表、电源流向图、显示器档案（`DisplaySection`）以及指标网格（`ModuleMetricGrid`）彻底移除 28pt 缩进。
  - 统一采用卡片两端 10pt 对称内边距（`padding(.horizontal, 10)`），可用宽度从 292pt 扩展至 320pt。
- **几何解算器联动**：
  - `DisplaySection` 的 `PanelChildGroup` 登记值从 `leading: 38, trailing: 10` 同步调整为 `leading: 10, trailing: 10`。
  - `SingleHostMotionCoordinator` 与 `PanelGeometrySolver` 自动以 320pt 开展开高度与滚动几何解算，无错位风险。
- **静态指标宽度审计（106pt → 120pt）**：
  - 半格内容宽推导更新：`300 - 10*2 = 280`，两列减 8pt 列距得 272pt，每列 136pt，减格子左右内衬 8×2 = 120pt。
  - 更新 `StaticMetricSizing.halfCellContentWidth = 120` 并刷新推导注释。
  - 运行 `MetricWidthAuditTests` 全量审计，确保所有指标在两语最窄 300pt 下均稳定满足契约。

### 3. 面板可见期菜单栏 30fps 负载环静默（防唤醒保险）

- **决策与定位**：
  - 1.5.4 底座中 `MenuBarLoadAnimator` 在负载数值收敛后已能自动取消定时器。此优化的定位是「低成本保险」：消除面板展开期间因背景负载高频微小波动而反复拉起 30fps 定时器的风险。
  - 在 `MenuBarLoadAnimator` 增加 `setPanelVisible(_ visible: Bool)`。面板处于可见状态时直接停用平滑定时器、发布量化目标值；面板完全关闭后按需恢复。
  - 与 `MonitorStore` 的 `panelDidAppear` 和 `panelDidDisappear` 生命周期严格绑定。

### 4. Direct 专用分项功耗（libIOReport）、电池修复与完整闭环

- **底层采样**：
  - 新增 `HagimiMonitorDirectOnly/IOReportPowerSampler.swift`，通过私有动态链接 `libIOReport.dylib` 订阅 `DCP/display stats/power` 与 `Energy Model/CPU Energy/GPU Energy`。
  - 在 `DisplayBridgingHeader.h` 声明 C 接口，App Store 构建完全隔离且无符号泄漏。
- **电池流向红线与补码修复**：
  - 修复 `BatterySampler.swift` 中放电负电流 UInt64 溢出导致的超大数值（进行有符号补码转换）；
  - **严守红线**：电池流动方向（充电 vs 放电）**始终且仅以 IOPS 状态键（`kIOPSIsChargingKey`/`kIOPSPowerSourceStateKey`）为唯一判定依据**，补码修复仅作用于绝对安培/功率幅值显示。
- **UI 呈现与设置项闭环**：
  - 在 `BatteryGlassRow`（`MonitorPanelView.swift`）展开区接入三个分项功耗指标（屏幕功耗、CPU 功耗、GPU 功耗）；
  - 在 `ModuleSettingsView.swift` 电源模块设置组增加分项功耗的独立开关与持久化存储；
  - 统一更新 `Localizable.xcstrings`（中英双语）。

### 5. Liquid Glass 双轨切换与材质分层纪律

- **持久化设置**：
  - `MonitorSettings` 新增 `@Published var liquidGlassEnabled: Bool = false`（默认关闭，存入 UserDefaults）。
  - 在 `GeneralSettingsView` 的外观设置组提供切换开关（仅 macOS 26+ 呈现）。
- **新建 `CompatiblePanelGlassHost`**：
  - 在 `Views/CompatibleGlassContainer.swift` 中新建 `CompatiblePanelGlassHost`（包装 NSPanel 的背景宿主视图）。
  - **严格遵守材质分层纪律**：
    - **窗口底座宿主（Window Backdrop）**：开 Liquid Glass 时用 `NSGlassEffectView`（`.regular`）；关 Liquid Glass 或 macOS 15 时用 `NSVisualEffectView(material: .popover, blendingMode: .behindWindow)`。此层透过窗口模糊桌面壁纸，完全合法且无闪烁。
    - **内部行卡片（Row Cards）**：严格保持 `CompatibleGlassEffect` 的 `.withinWindow` 毛玻璃，**绝不回退或绑定为 `.behindWindow`**，亦不参与 Liquid Glass 的几何合并，杜绝展开 resize 闪烁。
  - 切换材质时仅原地替换底座 layer/view，SwiftUI 树与展开状态零跳变。
- **容器与胶囊优化**：
  - 关闭 Liquid Glass 时 `CompatibleGlassContainer` 直接透传 content，消除多余开销；
  - 定宽（68×20）`NetworkRatePill` 与电池功率胶囊加入最坏值文本契约（如 `↑ 999.9 MB/s`、`1.2 GB/s`），建立文本单行截断与 scale factor 规则，邻近网络接口标题设置尾部省略，互不挤压。

## Risks / Trade-offs

- **[私有符号合规风险]** → 仅限 `HagimiMonitorDirect` 编译，共享代码使用 `#if DIRECT_DISTRIBUTION` 隔离，App Store scheme 编译产物不包含任何私有符号。
- **[新指标导致排版溢出]** → 半格预算提升至 120pt，新指标在 `StaticMetricSizing` 严格登记并由 `MetricWidthAuditTests` 拦截。
- **[全宽顶格边界贴合]** → 外框保持 `rowCornerRadius(14)`，内衬保持 10pt 水平边距，内容与圆角弧顶自然切齐，规避直角裁切破绽。
