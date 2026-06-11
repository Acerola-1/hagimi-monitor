## Why

用户希望在 CPU 和 GPU 模块中加入温度监控。目前 GPU 已采集温度数据但未暴露到 UI，CPU 完全没有温度采集。温度是硬件监控的重要维度，用户要求作为可选监测项目，默认不勾选。

## What Changes

- **GPU 温度暴露**: `GPUSampler` 已读取 `"Temperature(C)"`，将其加入 `metrics` 数组
- **CPU 温度采集**: 新增基于 SMC（System Management Controller）的温度读取，适配 Apple Silicon
- **设置页面可选**: CPU/GPU 的 `availableMetrics` 新增「温度」选项，`isDefault: false`
- **面板展示**: 展开区域根据 `enabledMetrics` 动态显示温度（已有过滤机制支持）

## Capabilities

### New Capabilities
- `cpu-gpu-temperature`: CPU/GPU 温度监控，包括 SMC 采集、设置可选、面板展示

### Modified Capabilities
- `monitor-panel`: 展开区域增加温度指标展示

## Impact

- `GPUSampler.swift`: 将已读取的 `temperature` 加入 `metrics`
- `CPUSampler.swift`: 新增 SMC 温度读取逻辑
- `MonitorModels.swift`: CPU/GPU `availableMetrics` 新增「温度」选项（默认不勾选）
- `SMC.swift` (新增): SMC 通信层，参考 `docs/stats/SMC/smc.swift`
