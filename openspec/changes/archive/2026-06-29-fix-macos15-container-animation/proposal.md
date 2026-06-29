## Why

macOS 15 上的面板容器尺寸变化异常，动画行为不一致，用户体验受损。主要问题包括：容器背景在 macOS 15 上为空操作导致视觉差异、展开/折叠过渡动画定义不统一、进度条缺少过渡动画、以及兼容层代码存在冗余。

## What Changes

- 统一所有展开/折叠区域的过渡动画定义，消除 `MonitorPanelView` 与 `DisplayControlsSection` 之间的差异
- 为 `ProgressMeter` 添加数值变化过渡动画
- 为 `SparklineChart` 数据点更新添加平滑过渡
- 优化 macOS 15 的 `CompatibleGlassEffect` 实现，移除冗余的双重裁剪
- 调整 macOS 15 容器背景的 `NSVisualEffectView` 材质选择
- 修复 `TransparentBackgroundView` 中直接操作窗口层级的潜在风险

## Capabilities

### New Capabilities

- `panel-animation-consistency`: 统一面板内所有展开/折叠、进度条、图表的动画行为
- `macos15-glass-compatibility`: 改善 macOS 15 上毛玻璃效果的兼容层实现

### Modified Capabilities

（无现有 spec 需要修改）

## Impact

**受影响文件：**
- `HagimiMonitor/MonitorPanelView.swift` — 过渡动画定义、header 动画禁用
- `HagimiMonitor/Views/CompatibleGlassContainer.swift` — macOS 15 兼容实现
- `HagimiMonitor/Views/Panel/ProgressMeter.swift` — 添加过渡动画
- `HagimiMonitor/Views/Panel/SparklineChart.swift` — 添加过渡动画
- `HagimiMonitorDirectOnly/DisplayControlsSection.swift` — 过渡动画定义

**无破坏性变更：** 所有修改向后兼容，不影响 macOS 26+ 的原生实现
