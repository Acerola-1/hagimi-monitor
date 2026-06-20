# Tasks: Enhance Statistics Data Collection

## Phase 0 — 前置基础设施（阻塞性，必须先完成）

### 0. 数值暴露机制
- [x] 在 `MonitorMetric` 中新增 `numericValue: Double?` 字段（`MonitorModels.swift`），构造器默认 nil，不影响现有调用
- [x] 在 `StatisticsRecorder` 中新增 `metricNumeric(_:key:) -> Double?` helper，读取 `numericValue`
- [x] 现有 `metricInt64`/`metricDouble` 保留（network/storage/power 的累计裸数字仍用字符串解析），新指标一律走 `metricNumeric`

### 1. MemoryPressureLevel rawValue
- [x] 将 `MemoryPressureLevel`（`MonitorModels.swift:24-29`）改为 `enum MemoryPressureLevel: Int`：normal=0, warning=1, critical=2, unknown=3
- [x] 确认所有使用点（`MemorySampler` 映射、`MonitorModule.pressure`、面板/Settings 比较）不受破坏
- [x] 编译通过 + 运行现有 StatisticsTests

### 2. SwiftData 版本化（建议）
- [x] 为 `HourlySample`/`DailyAggregate` 引入 `VersionedSchema` + `SchemaMigrationPlan`
- [x] 确认 `StatisticsStore` 初始化走 versioned container
- [x] 验证轻量迁移对新增 Optional 字段自动生效

### 3. Recorder 内部重构
- [x] 扩展 `lastCumulative` 增加 `swapins: Int64`、`swapouts: Int64` 槽位（`StatisticsRecorder.swift:55`）
- [x] 将 `buildSummary` 的 9 元素元组重构为 `struct SummaryRow`（`StatisticsAggregator.swift:177`），queryHourly/queryDaily 三处共用
- [x] 确认重构后现有聚合结果不变（运行 StatisticsTests）

## Phase 1 — 高优先级（健康评分/事件检测直接依赖）

### 4. 扩展 SwiftData 模型 Phase 1
- [x] `HourlySample` 新增：`swapUsed: Int64?`, `memoryPressureLevel: Int16?`, `thermalState: Int16?`, `swapins: Int64?`, `swapouts: Int64?`
- [x] `DailyAggregate` 新增相同字段
- [x] 确认轻量迁移生效，运行 StatisticsTests 不破坏

### 5. MemorySampler 暴露 Phase 1 指标
- [x] `swap-used` metric 补 `numericValue: swap?.used`（bytes）
- [x] 新增 `pressure-level` metric，`numericValue: Double(level.rawValue)`
- [x] 提取 `vm_statistics64.swapins/swapouts`，新增 `swapins`/`swapouts` metric（numericValue 为累计计数）

### 6. StatisticsRecorder 提取 Phase 1 指标
- [x] SampleBucket 新增 Phase 1 字段：`swapUsedSum/swapUsedCount`、`pressureLevelMax`、`thermalStateMax`、`swapinsDelta/swapoutsDelta`
- [x] `record(modules:)` 中从 memory module 提取 `swap-used`、`pressure-level`，累加/取 max
- [x] `record(modules:)` 中从 memory module 提取 `swapins`/`swapouts`，用 `lastCumulative` 算 delta 存入 bucket
- [x] `record(modules:)` 中直接读 `ProcessInfo.processInfo.thermalState.rawValue`，取 max 存入 bucket
- [x] `flushCurrentBuckets()` 写入 `HourlySample` 新字段
- [x] `cleanupOldSamples(context:)` 聚合写入 `DailyAggregate` 新字段（thermalState/pressureLevel 取 max，swapins/swapouts 求和）

### 7. StatisticsAggregator 扩展 Phase 1
- [x] `StatisticsDataPoint` 新增 Phase 1 字段
- [x] `StatisticsSummary` 新增：`avgSwapUsed`、`peakMemoryPressureLevel`、`peakThermalState`、`totalSwapins`、`totalSwapouts`
- [x] queryHourly / queryDaily 填充新字段
- [x] `pendingSnapshot()` 的 `PendingBucket` 新增 Phase 1 字段并填充

## Phase 2 — 中优先级（丰富分析维度）

### 8. 扩展 SwiftData 模型 Phase 2
- [x] 新增：`cpuSystem: Double?`, `cpuUser: Double?`, `cpuIdle: Double?`, `cpuTemperature: Double?`, `memoryUsed: Int64?`, `diskFree: Int64?`, `netPeakDownload: Int64?`, `netPeakUpload: Int64?`, `diskPeakRead: Int64?`, `diskPeakWrite: Int64?`

### 9. Sampler 暴露 Phase 2 指标
- [x] CPUSampler：`system`/`user`/`idle`/`temperature` 补 numericValue
- [x] MemorySampler：`used` metric 补 numericValue
- [x] StorageSampler：`free` metric 补 numericValue
- [x] NetworkSampler：`upload`/`download` 补 numericValue
- [x] StorageSampler：新增瞬时读写速率 metric（`disk-read-rate`/`disk-write-rate`，bytes/sec），需维护 previous 累计值算 delta/time

### 10. StatisticsRecorder 提取 Phase 2 指标
- [x] SampleBucket 新增 Phase 2 字段
- [x] CPU metrics 求均值，temperature 求均值（count 跳过 nil）
- [x] memoryUsed 求均值，diskFree 取最新
- [x] network upload/download 取 peak，disk read/write 速率取 peak
- [x] flush / aggregate 路径填充

### 11. StatisticsAggregator 扩展 Phase 2
- [x] DataPoint / Summary 新增 Phase 2 字段
- [x] 查询路径填充

## Phase 3 — 低优先级（补充完善）

### 12. 扩展 SwiftData 模型 Phase 3
- [x] 新增：`gpuMemoryUsed: Int64?`, `gpuRenderUtil: Double?`, `gpuTilerUtil: Double?`, `batteryHealth: Double?`, `batteryCycleCount: Int?`, `batteryTemperature: Double?`, `onBatteryPower: Double?`

### 13. Sampler 暴露 Phase 3 指标
- [x] GPUSampler：`gpu-memory`/`render`/`tiler` 补 numericValue（注意 render/tiler 条件性暴露）
- [x] BatterySampler：`health`/`cycle-count`/`temperature` 补 numericValue（cycle-count 已是裸数字，确认即可）

### 14. StatisticsRecorder 提取 Phase 3 指标
- [x] SampleBucket 新增 Phase 3 字段
- [x] GPU VRAM/利用率求均值（count 跳过 nil）
- [x] Battery health/temperature 求均值，cycle-count 取最新
- [x] `onBatteryPower`：每次采样检查 `type` metric 是否为 "battery"，计数，flush 算占比
- [x] flush / aggregate 路径填充

### 15. StatisticsAggregator 扩展 Phase 3
- [x] DataPoint / Summary 新增 Phase 3 字段
- [x] 查询路径填充

## 验证
- [x] 每个 Phase 完成后 build 确认编译通过
- [x] 每个 Phase 完成后运行 `StatisticsTests` 确认不破坏现有聚合
- [x] Phase 0 完成后：确认 `metricNumeric` 能从带 numericValue 的 metric 提取数值
- [ ] Phase 1 完成后手动验证：运行 app 1 小时后检查 SwiftData 中 `swapUsed`/`memoryPressureLevel`/`thermalState`/`swapins`/`swapouts` 有值
- [ ] 验证旧数据（升级前记录）新字段为 nil，查询不崩溃
