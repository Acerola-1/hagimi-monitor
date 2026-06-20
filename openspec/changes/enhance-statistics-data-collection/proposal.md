# Proposal: Enhance Statistics Data Collection

## Summary
扩展统计数据的采集维度，将现有采样但未持久化的关键指标写入 SwiftData，为健康评分、事件检测和更丰富的历史分析提供数据基础。

## Problems
- CPU 只记录总利用率，丢失了 system/user/idle 分解和温度数据
- Memory 只记录百分比，丢失了 Swap 使用量（macOS 性能杀手）和压力等级
- GPU 只记录总利用率，丢失了 VRAM 使用量和 render/tiler 利用率
- Battery 完全没有统计记录（健康度、循环次数、温度等）
- Power 只记录瓦特数，没有电池/AC 切换事件
- Network/Storage 只记录累计字节增量，没有瞬时速率峰值
- 热压力等级（`ProcessInfo.thermalState`）零成本可获取但完全未采集
- Swap 换入换出率（`vm_statistics64.swapins/swapouts`）已在调用 `host_statistics64` 但未提取

## Goals
- 在 `HourlySample` 和 `DailyAggregate` 模型中新增字段，持久化上述遗漏指标
- 在 `StatisticsRecorder` 中提取并记录这些指标
- 保持向后兼容：旧数据中新增字段为 nil，不影响现有查询和展示
- 优先级排序：Swap 使用量 > 内存压力等级 > 热压力等级 > CPU 分解 > CPU 温度 > Battery > GPU VRAM > 瞬时速率峰值

## 数据来源可行性
参考实现 `docs/stats/Modules/RAM/readers.swift`、`docs/stats/Modules/CPU/readers.swift` 已验证下列指标均能以**原始数值**直接获取：Swap 使用量（`vm.swapusage` → `xsw_usage.xsu_used`）、swapins/swapouts（`vm_statistics64`）、内存压力等级（`kern.memorystatus_vm_pressure_level`，2=warning/4=critical）、CPU system/user/idle（`host_cpu_load_info` ticks 差值）、CPU 温度（SMC）。

HagimiMonitor 的 sampler 内部也已算出这些原始值（如 `MemorySampler.swapUsage()` 返回 Double bytes），只是格式化后塞进 `MonitorMetric.value` 字符串。因此本提案的前置工作是给 `MonitorMetric` 增加 `numericValue` 字段暴露原始数值，而非改造数据采集方式。

热压力等级采用 `ProcessInfo.processInfo.thermalState`（系统级热节流状态，零成本），与 Stats 走 SMC 温度传感器的路径不同——HagimiMonitor 用 thermalState 做系统级状态，SMC 温度另行用于 CPU 温度指标，两者分开。

## Non-Goals
- 不改变现有数据的聚合逻辑（avg/peak/low/sampleCount）
- 不改变 StatisticsView 或 HTML Report 的展示（后续 change 负责）
- 不引入新的采样频率或采样器
- 不做同机型比对或云端数据上报

## Impact
- `MonitorModels.swift` — `MonitorMetric` 新增 `numericValue: Double?`；`MemoryPressureLevel` 加 `: Int` rawValue
- `StatisticsModels.swift` — 新增 SwiftData 模型字段
- `StatisticsRecorder.swift` — 新增 `metricNumeric` helper，从 `numericValue` 提取新指标；扩展 `lastCumulative` 支持 swapins/swapouts 增量
- `StatisticsAggregator.swift` — 查询结果结构体新增字段；`buildSummary` 元组重构为 struct
- `StatisticsStore.swift` — （建议）引入 VersionedSchema + SchemaMigrationPlan
- `CPUSampler.swift` / `MemorySampler.swift` / `GPUSampler.swift` / `StorageSampler.swift` / `NetworkSampler.swift` / `BatterySampler.swift` — 为现有 metric 补 `numericValue`，MemorySampler 新增 `pressure-level`/`swapins`/`swapouts` metric，StorageSampler 新增瞬时读写速率 metric
