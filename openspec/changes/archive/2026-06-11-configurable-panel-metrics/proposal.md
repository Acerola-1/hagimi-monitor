## Why

主面板各模块展开后显示的详细指标目前是硬编码的（如电池固定显示「充电功率、健康度、循环数、温度」），用户无法自定义。设置页面虽已预留「检测项目」区域，但每个模块的 `availableMetrics` 仅有1个占位项，未与实际展开指标关联。用户需要能自主选择展开后显示哪些详细指标。

## What Changes

- 扩充各 `MonitorKind` 的 `availableMetrics`，将当前展开区域硬编码的所有指标纳入可配置范围
- 设置页面的「检测项目」变为真正的多选列表，默认全勾选，最多选4项
- 主面板展开时，仅显示用户勾选的指标（按勾选顺序排列）
- 各 Sampler 返回的 `metrics` 需保证指标名称与 `availableMetrics` 中的 `id` 一致
- 电池模块的展开逻辑需适配：无外接电源时隐藏「充电功率」，此逻辑在视图层根据实时数据动态过滤

## Capabilities

### New Capabilities
- `configurable-panel-metrics`: 主面板展开区域指标的可配置化，包括指标定义、设置 UI、面板渲染过滤

### Modified Capabilities
- `monitor-panel`: 展开区域详细指标的渲染逻辑从硬编码改为基于 `enabledMetrics` 过滤

## Impact

- `MonitorModels.swift`: `MonitorKind.availableMetrics` 需大幅扩充
- `MonitorSettings.swift`: `enabledMetrics` 的默认值逻辑需改为默认全选
- `MonitorPanelView.swift`: `MetricDetailGrid`、`NetworkGlassRow`、`BatteryGlassRow` 的展开内容需根据 `enabledMetrics` 过滤
- `ModuleSettingsView.swift`: UI 无需大改，但「检测项目」列表将显示真正的多选项
- 各 Sampler: 确保 `MonitorMetric.name` 与 `availableMetrics` 的 `id` 匹配
