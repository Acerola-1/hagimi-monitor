## 1. 本地化与数据采样层（Direct 分项功耗、电池补码与静态宽度）

- [x] 1.1 使用 Python 脚本编辑 `HagimiMonitor/Localizable.xcstrings`，新增中英双语文案（Liquid Glass 设置项标题/副标题、屏幕功耗、CPU 功耗、GPU 功耗标签）
- [x] 1.2 在 `HagimiMonitorDirectOnly` 引入 `IOReportPowerSampler.swift` 并在 `DisplayBridgingHeader.h` 声明私有 C 接口，验证 Direct 构建成功且 App Store 构建无符号泄漏
- [x] 1.3 在 `BatterySampler.swift` 接入 `InstantAmperage` 优先与有符号 Double 补码转换，并增加容量/电压多级回退；**严格确认流向判定始终仅依据 IOPS 状态键**，运行 `BatterySamplerTests` 验证通过
- [x] 1.4 在 `MonitorModels.swift` 和 `StaticMetricSizing.swift` 登记分项功耗指标，更新 `halfCellContentWidth` 从 106pt 至 120pt（全宽顶格），胶囊 68pt 纳入最坏值审计，运行 `MetricWidthAuditTests` 验证双语审计通过

## 2. 功耗指标 UI 呈现与模块设置项闭环

- [x] 2.1 在 `MonitorPanelView.swift`（`BatteryGlassRow`）展开区接入分项功耗（屏幕/CPU/GPU 功耗）的指标格渲染（`#if DIRECT_DISTRIBUTION`），在沙盒 App Store 下自动降级隐藏
- [x] 2.2 在 `ModuleSettingsView.swift` 的电源模块配置组中新增分项功耗的独立勾选开关与持久化存储，支持按需展示

## 3. 性能与主线程防唤醒门控

- [x] 3.1 在 `MenuBarLoadAnimator` 增加 `setPanelVisible(_:)` 门控并在 `MonitorStore`（`panelDidAppear`/`panelDidDisappear`）绑定面板显隐，面板可见时暂停平滑定时器
- [x] 3.2 将 `CompatiblePulseEffect` 改造为面板呼出时单次脉冲触发，验证不再持续占用显示刷新时钟

## 4. 电源流向图 GPU 虚线流光管线

- [x] 4.1 移除 `PowerFlowDiagram.swift` 中的 `TimelineView` 逐帧驱动
- [x] 4.2 基于 `NSViewRepresentable` + `CAShapeLayer`（配合 `CABasicAnimation(keyPath: "lineDashPhase")`）实现硬件合成的大脉冲段流光管线（8pt 虚线 + 12pt 间距），验证主线程 CPU 占用降为 0%
- [x] 4.3 将汇流点呼吸辉光改造为独立 Core Animation / 声明式动画（呼吸缩放/透明度变化），消除 Canvas 逐帧重绘依赖
- [x] 4.4 接入充电/放电硬件物理流向反转，并采用固定动画时长 + 净功率 ±0.3W 启停门控，杜绝速率频繁重置导致的相位跳变抖动

## 5. 全宽顶格排版、几何解算器联动与防抖胶囊

- [x] 5.1 移除 CPU 进程列表、网络/磁盘列表、风扇、蓝牙、电源流向图中的 28pt 缩进，以及 `ModuleMetricGrid` 的 `leadingInset: 28`，改造为两端 10pt 对称的全宽顶格排版
- [x] 5.2 将 `DisplaySection.swift` 的 `PanelChildGroup` 登记值由 `leading: 38` 更新为 `leading: 10`，验证单宿主弹簧与滚动揭示几何解算完全正常
- [x] 5.3 为网络速率与电源功率实现统一定宽（70×20，间距 6pt）的 `Capsule(theme.trackFill)` 衬底，两行结构完全同构，邻近网络接口标题增加尾部省略截断，验证高频跳动时布局零抖动且上下严格对齐

## 6. Liquid Glass 双轨切换与持久化设置

- [x] 6.1 在 `MonitorSettings.swift` 新增 `liquidGlassEnabled: Bool = false` 持久化设置（默认关闭）
- [x] 6.2 在 `GeneralSettingsView.swift` 的外观组提供 Liquid Glass 开关（仅 macOS 26+ 显示），附带可读性说明
- [x] 6.3 在 `Views/CompatibleGlassContainer.swift` 中新建 `CompatiblePanelGlassHost`，在 `FluidPanelController` 与 `PinnedPanelController` 接入：开启时用 `NSGlassEffectView`，关闭或旧系统时用 `.popover + .behindWindow` 模糊桌面，行卡片严格保持 `.withinWindow` 毛玻璃
- [x] 6.4 在 `CompatibleGlassContainer.swift` 中优化：当关闭 Liquid Glass 时直接透传 content，消除容器冗余计算

## 7. 构建、测试与集成验收

- [x] 7.1 运行 `HagimiMonitor`（App Store）与 `HagimiMonitorDirect`（Direct）双 scheme 隔离构建，验证两端构建均成功且 DerivedData 隔离
- [x] 7.2 运行完整 `HagimiMonitorDirect` 单元测试（重点覆盖 `MetricWidthAuditTests` 与 `BatterySamplerTests`），保证全部测试全绿
- [x] 7.3 分别启动 Direct 与 App Store 两版本进行冒烟验证：验证全宽顶格排版、流向图流动质感（与 1.5.4 dev A/B 对比目测）、定宽胶囊防抖、设置开关即时生效
- [x] 7.4 运行 autotest 探针与 Instruments Time Profiler，验证面板展开动画无掉帧，流向图渲染时主线程 CPU 保持在 0%~0.1% 极限区间
