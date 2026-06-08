## Why

菜单栏负载环（Halo Ring）目前硬编码为 CPU 60% + GPU 40% 的综合算力，用户无法选择关注其他指标。不同使用场景下用户最关心的指标不同（如开发关注 CPU，视频编辑关注 GPU，容器化关注内存），应允许自定义。

## What Changes

- 新增 `HaloRingSource` 枚举（combined / cpu / gpu / memory），表示圆环监测的数据源
- 在设置-常规中新增"负载环"section，提供 Picker 选择监测项目，默认"综合"
- `MonitorStore.combinedComputeLoad` 改为根据 `ringSource` 选择数据源
- 内存作为数据源时，圆环弧度用已用/总量百分比，核心颜色按系统内存压力等级（sysctl）显示而非按占比阈值
- `MonitorModule` 新增可选 `pressure` 属性，用于承载内存压力等级
- `MenuBarComputeRingIcon` 支持外部传入颜色等级，不再仅依赖 load 数值推断

## Capabilities

### New Capabilities
- `halo-ring-source`: 负载环数据源可配置，支持综合/CPU/GPU/内存四种监测模式，内存模式下颜色按系统压力等级显示

### Modified Capabilities
- `menu-bar`: 菜单栏圆环不再硬编码综合算力，改为读取用户配置的数据源

## Impact

- `MonitorSettings.swift`: 新增 `ringSource` 持久化属性
- `MonitorModels.swift`: `MonitorModule` 新增 `pressure` 属性，`MonitorStore` 修改 `combinedComputeLoad` 逻辑
- `MenuBarComputeRingIcon.swift`: 支持外部传入 `loadLevel`，内存模式下不再从 load 值推导颜色
- `SettingsView.swift`: 常规设置新增"负载环"section
- `MemorySampler.swift`: 采样时将 `MemoryPressureState` 映射到 `MonitorModule.pressure`
