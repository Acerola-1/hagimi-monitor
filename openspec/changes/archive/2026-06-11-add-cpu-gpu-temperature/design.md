## Context

当前代码状态：
- `GPUSampler` 已读取 `PerformanceStatistics["Temperature(C)"]` 到 `GPUReading.temperature`，但未加入 `metrics`
- `CPUSampler` 完全没有温度读取
- `docs/stats/SMC/smc.swift` 提供了完整的 SMC 通信实现，支持 Apple Silicon 温度密钥
- Apple Silicon CPU 温度密钥：`Tp09`, `Tp0T`, `Tp01`, `Tp05`, `Tp0D`, `Tp0H`, `Tp0L`, `Tp0P`, `Tp0X`, `Tp0b`
- 已有 `enabledMetrics` 过滤机制，新增指标只需加入 `availableMetrics` 即可自动支持

## Goals / Non-Goals

**Goals:**
- GPU 温度：将已采集数据暴露到 UI（最小改动）
- CPU 温度：引入 SMC 读取，计算多传感器平均值
- 设置可选：默认不勾选温度
- 面板展示：利用现有 `enabledMetrics` 过滤机制

**Non-Goals:**
- 不实现 Intel Mac 的 CPU 温度（项目仅支持 Apple Silicon）
- 不添加独立的「温度」监控模块（作为 CPU/GPU 的子指标）
- 不实现风扇控制或温度告警

## Decisions

**Decision: 使用 SMC 读取 CPU 温度（已排除 HID 和 IOReport）**

对比了三种方案后选择 SMC：

| 方案 | 原理 | 复杂度 | 权限 | 结论 |
|------|------|--------|------|------|
| SMC | 读取 SMC 密钥 `Tp09` 系列 | 中等，参考代码完整 | 用户态 IOKit，无需特殊权限 | **选中** |
| HID | IOHID 框架读取热传感器事件 | 高，需 Objective-C 桥接 | 用户态 | 实现成本过高 |
| IOReport Energy | 读取 Energy Model 功耗通道 | 高，需订阅/回调机制 | 用户态 | 读取的是功耗非温度 |

- SMC 代码在 `docs/stats/SMC/smc.swift` 中已有 710 行完整实现，直接借鉴即可
- HID 需要引入 `.m` + `bridge.h` 桥接文件，项目当前无 Objective-C 文件，构建复杂度增加
- IOReport Energy 读取的是功耗数据而非直接温度，且需要异步订阅机制，与现有 Sampler 同步采样模式不匹配

**Decision: CPU 温度取多传感器平均值**
- Apple Silicon 有多个 CPU 核心温度传感器（`Tp09` ~ `Tp0b` 共 10 个）
- Stats 项目也使用 `average: true` 标记
- 读取所有可用密钥后取平均，失败时返回 `--`

**Decision: 温度指标默认不勾选（`isDefault: false`）**
- 用户明确要求默认不包含温度
- 与现有指标（`isDefault: true`）区分

**Decision: GPU 温度密钥与现有指标区分**
- GPU 已有 "GPU内存"/"已分配"/"渲染"/"分块"，新增 "温度"
- 使用中文名称 "温度" 作为 `id`，与 `MonitorMetric.name` 对齐

## Risks / Trade-offs

- **[Risk]** SMC 读取需要 IOKit 权限，某些系统配置下可能失败
  → **Mitigation**: 失败时返回 `"--"`，不影响其他指标

- **[Risk]** Apple Silicon 不同代（M1/M2/M3/M4）的 SMC 密钥可能不同
  → **Mitigation**: 尝试读取多个密钥，取第一个成功的；参考 Stats 项目的密钥列表已覆盖 M1-M5

- **[Risk]** GPU `Temperature(C)` 在某些 GPU 上不可用
  → **Mitigation**: 已有 `if let` 保护，不可用时不添加指标
