## Why

设置页面中「检测项目」的文案不够准确，应为「监测项目」。此外，当前每个指标选项独占一行，在指标数量较多（如 CPU 4 项、GPU 4 项）时列表过长，视觉节奏松散。改为双列布局可以更高效利用空间，让设置页面更紧凑。

## What Changes

- 将 `ModuleSettingsView` 中「检测项目」文案改为「监测项目」
- 将 `MetricSelectionRow` 的单列垂直列表改为双列网格布局（每行两个选项）
- 保持现有的勾选交互和最多4项限制逻辑不变

## Capabilities

### New Capabilities
- `settings-metrics-layout`: 设置页面监测项目区域的双列网格布局

### Modified Capabilities
- （无现有 spec 需要修改，这是纯 UI 布局变更）

## Impact

- `ModuleSettingsView.swift`: 文案修改 + 布局结构调整
- `MetricSelectionRow`: 可能需要调整内边距和尺寸以适应双列
