# 提案：面板性能优化、视觉精进与分项功耗监控（基于 1.5.4）

## Why

在 HagimiMonitor v1.5.4 的单宿主物理弹簧架构基础之上，我们进一步梳理并吸收了社区 PR #105 中有价值的战术发现：
1. **主线程高频重绘门控**：面板可见期间，菜单栏负载环原有的 30fps 平滑推进与状态项绘图占用了宝贵的主线程与窗口合成预算；将其彻底静默降频能为面板交互腾出最大余量。
2. **GPU 虚线相位电流管线**：原电源流向图依赖 30fps 的 `TimelineView + Canvas` 逐帧重绘，通过改用 GPU 硬件加速的虚线相位（Dash Phase）动画，既能以类似 1.5.4 的大脉冲段展现生动流向，又能将主线程开销降为 0%。
3. **顶格全宽排版**：移除展开明细原先的 28pt 缩进，改为全宽（320pt）对称对齐，提升横向空间利用率，彻底消除长进程名截断，并让电源流向图更从容舒展。
4. **视觉定宽防抖胶囊**：为网络行速率与电源行功率增加定宽 68×20 胶囊衬底，彻底解决数值位数跳动时的左右推挤。
5. **分项功耗与电池底层加固**：在 Direct 版引入 `libIOReport` 屏幕/CPU/GPU 实时功耗采样，并修复放电电流 UInt64 补码负数解析。
6. **Liquid Glass 双轨切换**：在设置中引入 Liquid Glass 持久化开关（macOS 26+，默认关闭），保留经典毛玻璃作为默认，支持用户自主尝鲜原生材质。

## What Changes

- **分项功耗监测（Direct 版）**：新增 `IOReportPowerSampler`，通过 `libIOReport` 差分读取内建屏、CPU、GPU 实时功耗，在 Direct 版电池展开区与设置项开放。
- **电池数据加固**：电流指标优先读取 `InstantAmperage` 并修复 UInt64 补码负数问题；电压与容量补充 `AppleRawBatteryVoltage` / `AppleRawCurrentCapacity` 及多级回退。
- **菜单栏 30fps 门控**：当监控面板处于可见状态时，通过 `loadAnimator.setPanelVisible(true)` 彻底销毁 30fps 平滑定时器，降频至 1Hz 数据驱动，面板关闭后自动恢复。
- **GPU 虚线流光管线**：电源流向图移除 30fps `TimelineView`，改为基于 GPU 硬件加速的虚线相位（Dash Phase）流动管线，保留大脉冲段视觉质感，且在 ±0.3W 空载时平滑静默。
- **展开区全宽顶格排版**：移除 CPU 进程列表、网络/磁盘列表、风扇、蓝牙、电源流向图中的 28pt 缩进，统一使用全宽对称对齐（两端 10pt 内边距），更新 `AGENTS.md` 规范。
- **定宽药丸胶囊（Pills）**：网络行（↑/↓）与电源行（⚡/仪表）采用定宽 68×20、`theme.trackFill` 衬底的胶囊，彻底防止数字位数跳动时的左右推挤。
- **顶部脉冲优化**：`SYSTEM · LIVE` 绿点由持续循环脉冲改为面板打开时单次触发。
- **Liquid Glass 持久化开关**：在「设置 → 常规 → 外观」增加开关（macOS 26+，默认关闭）。开启时使用系统 `NSGlassEffectView` 与 `.glassEffect`，关闭时使用经典毛玻璃。

## Capabilities

### New Capabilities
- `component-power-metrics`: 在 Direct 版提供基于 `libIOReport` 的内建屏、CPU、GPU 实时分项功耗指标。
- `liquid-glass-preference`: 提供系统 Liquid Glass 与经典毛玻璃的持久化切换开关（默认关闭）。

### Modified Capabilities
- `monitor-panel`: 展开区明细改为全宽顶格排版；网络与电源行右侧采用定宽胶囊衬底。
- `panel-animation-consistency`: 面板可见期静默菜单栏 30fps 负载环；电源流向图接入 GPU 硬件加速虚线流向管线。
- `settings-window`: 常规设置页外观组增加 Liquid Glass 开关。

## Impact

- **代码影响**：
  - `HagimiMonitor/MonitorModels.swift`（菜单栏动画生命周期门控）
  - `HagimiMonitor/PowerFlowDiagram.swift`（GPU Dash Phase 连线流向）
  - `HagimiMonitor/MonitorPanelView.swift`（全宽顶格对齐、胶囊衬底、材质适配）
  - `HagimiMonitor/Samplers/BatterySampler.swift`（分项功耗注入、电流补码修复）
  - `HagimiMonitorDirectOnly/IOReportPowerSampler.swift`（新增分项功耗采样器）
  - `HagimiMonitorDirectOnly/DisplayBridgingHeader.h`（声明 libIOReport 接口）
  - `HagimiMonitor/Views/CompatibleGlassContainer.swift`（Liquid Glass 开关分流）
  - `HagimiMonitor/Views/CompatibleSymbolEffect.swift`（单次脉冲触发）
  - `HagimiMonitor/Views/Settings/GeneralSettingsView.swift`（设置开关）
  - `HagimiMonitor/Views/Panel/MetricCellSizing.swift`（审计分项功耗指标宽度）
  - `AGENTS.md`（更新 28pt 缩进为全宽顶格规范）
- **构建目标隔离**：`libIOReport` 仅由 `HagimiMonitorDirect` target 链接，App Store target 保持只读沙盒合规。
