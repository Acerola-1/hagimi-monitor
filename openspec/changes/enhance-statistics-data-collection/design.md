# Design: Enhance Statistics Data Collection

> 参考实现：`docs/stats/Modules/RAM/readers.swift`、`docs/stats/Modules/CPU/readers.swift`。Stats 证明下列指标都能以**原始数值**直接获取，本提案的数据来源可行性已验证。

## Phase 0：数值暴露策略（所有 Phase 的前置）

### 问题

现有 `MonitorMetric.value` 是**格式化字符串**（`"23%"`、`"1.2 GB"`、`"35°C"`、`"normal"`），而 `StatisticsRecorder.metricInt64/metricDouble`（`StatisticsRecorder.swift:231-240`）只能解析纯数字。当前 20 个目标字段里只有 `cycle-count`（`BatterySampler.swift:53`，裸数字）能被提取，其余全部返回 nil。

**这不是数据本身的限制，是 sampler 的暴露方式问题**。Stats 的 RAM reader 直接拿 `stats.swapins`、`xsw_usage.xsu_used`、`kern.memorystatus_vm_pressure_level` 的原始数值。HagimiMonitor 的 sampler 内部也已算出这些原始值（如 `MemorySampler.swapUsage()` 返回 `SwapUsage(used:total:available:)` Double bytes），只是格式化后塞进 metric 字符串。

### 方案：给 MonitorMetric 增加 numericValue

```swift
struct MonitorMetric: Identifiable, Equatable {
    let id: UUID
    let name: String
    let value: String        // 保持不变，供面板/Settings 显示
    var numericValue: Double? // 新增：原始数值，供 Recorder/Aggregator 提取
}
```

- 现有显示逻辑零改动（继续用 `value`）。
- Sampler 在构造 metric 时同时填 `numericValue`（bytes 用 Double，百分比用 0-100，温度用 °C）。
- Recorder 改用新 helper `metricNumeric(_:key:) -> Double?` 读 `numericValue`，废弃对纯数字字符串的解析依赖。
- 对 Int64 语义字段（bytes/计数器），Recorder 内部 `Int64(numeric)` 转换。

这一步是 enhance 自身、以及 mac-health-score / event-timeline 两个依赖提案的共同前置。

### 前置：MemoryPressureLevel 加 rawValue

`MemoryPressureLevel`（`MonitorModels.swift:24-29`）当前是 `enum MemoryPressureLevel: Equatable`，**无 rawValue**。enhance 和 event-timeline 都要用 `.rawValue` 做数值比较和持久化，照抄会编译失败。

改为：

```swift
enum MemoryPressureLevel: Int, Equatable {
    case normal = 0
    case warning = 1
    case critical = 2
    case unknown = 3
}
```

sysctl `kern.memorystatus_vm_pressure_level` 返回 2=warning、4=critical（见 `MemorySampler.swift:68-84` 已有映射），与 enum rawValue 不同——Sampler 内部已做 `2→.warning`、`4→.critical` 映射，持久化的是 enum rawValue（0/1/2/3），不是 sysctl 原值。

## 新增字段设计

### HourlySample / DailyAggregate 新增字段

| 字段名 | 类型 | 来源模块 | 说明 |
|--------|------|----------|------|
| `cpuSystem` | `Double?` | CPU | system 占比均值 (0-100) |
| `cpuUser` | `Double?` | CPU | user 占比均值 (0-100) |
| `cpuIdle` | `Double?` | CPU | idle 占比均值 (0-100) |
| `cpuTemperature` | `Double?` | CPU | SMC 温度均值 (°C)，仅 DISPLAY_CONTROL |
| `gpuMemoryUsed` | `Int64?` | GPU | VRAM 使用量均值 (bytes) |
| `gpuRenderUtil` | `Double?` | GPU | renderer 利用率均值 (0-100) |
| `gpuTilerUtil` | `Double?` | GPU | tiler 利用率均值 (0-100) |
| `memoryUsed` | `Int64?` | Memory | 物理内存使用量均值 (bytes) |
| `swapUsed` | `Int64?` | Memory | Swap 使用量均值 (bytes) |
| `memoryPressureLevel` | `Int16?` | Memory | 压力等级 (0=normal, 1=warning, 2=critical, 3=unknown) |
| `swapins` | `Int64?` | Memory | 该时段换入页面数增量 |
| `swapouts` | `Int64?` | Memory | 该时段换出页面数增量 |
| `thermalState` | `Int16?` | System | 该时段达到过的最严重热状态 (0=nominal,1=fair,2=serious,3=critical) |
| `diskFree` | `Int64?` | Storage | 磁盘剩余空间 (bytes)，取时段最新值 |
| `netPeakDownload` | `Int64?` | Network | 下载速率峰值 (bytes/sec) |
| `netPeakUpload` | `Int64?` | Network | 上传速率峰值 (bytes/sec) |
| `diskPeakRead` | `Int64?` | Storage | 磁盘读取速率峰值 (bytes/sec) |
| `diskPeakWrite` | `Int64?` | Storage | 磁盘写入速率峰值 (bytes/sec) |
| `batteryHealth` | `Double?` | Battery | 电池健康度均值 (0-100%) |
| `batteryCycleCount` | `Int?` | Battery | 循环次数（取时段最新值） |
| `batteryTemperature` | `Double?` | Battery | 电池温度均值 (°C) |
| `onBatteryPower` | `Double?` | Battery | 使用电池供电的采样占比 (0-1) |

### 设计决策

- **thermalState 取"最严重状态"而非均值**：枚举值求均值得 1.3 这类无意义数。健康评分硬帽和事件检测关心的是"是否触及 critical/serious"，取 `max` 最实用。一次 critical 比平均 fair 更值得记录。SampleBucket 用 `thermalStateMax`。
- **swapins/swapouts 存增量**：`vm_statistics64.swapins` 是系统启动以来累计计数器，直接存会放大 N 倍。参照 network/storage 的 `lastCumulative` 机制算 delta。
- **diskFree / batteryCycleCount 取最新值**：这两个是单调/长期值，均值无意义，取时段内最后一次采样值。

## 采集方式

### 已在 sampler 内部算出，需通过 numericValue 暴露

Sampler 内部已有原始值，只需在构造 metric 时补 `numericValue`，Recorder 即可提取：

| metric name | 来源 Sampler | 内部已有原始值 | 新增字段 |
|-------------|-------------|---------------|----------|
| `system` | CPUSampler | `systemLoad` | `cpuSystem` |
| `user` | CPUSampler | `userLoad` | `cpuUser` |
| `idle` | CPUSampler | `idleLoad` | `cpuIdle` |
| `temperature` | CPUSampler (DISPLAY_CONTROL) | SMC 温度 | `cpuTemperature` |
| `gpu-memory` | GPUSampler | VRAM bytes | `gpuMemoryUsed` |
| `render` | GPUSampler | renderer% | `gpuRenderUtil` |
| `tiler` | GPUSampler | tiler% | `gpuTilerUtil` |
| `used` | MemorySampler | `used` (bytes) | `memoryUsed` |
| `swap-used` | MemorySampler | `swapUsage().used` (bytes) | `swapUsed` |
| `free` | StorageSampler | free bytes | `diskFree` |
| `health` | BatterySampler | health% | `batteryHealth` |
| `cycle-count` | BatterySampler | 循环次数 | `batteryCycleCount` |
| `temperature` | BatterySampler | 电池温度 | `batteryTemperature` |
| `upload` | NetworkSampler | 上传速率 bytes/sec | `netPeakUpload`（取 peak） |
| `download` | NetworkSampler | 下载速率 bytes/sec | `netPeakDownload`（取 peak） |

注意：
- `swap-used` 当前 value 是 `swapUsedText()` 返回的 `"2.3 GB"` 或 `"--"`，**无法被解析**。补 `numericValue: swap?.used` 后即可。
- `render`/`tiler` 在 GPUSampler 是**条件性暴露**（reading 为空时不追加），Recorder 提取返回 nil 属正常，count 跳过。
- Network `upload`/`download` 是瞬时速率（bytes/sec），取 peak 语义正确。

### 需新增采集的指标

**1. 内存压力等级（pressure-level）**
`MemorySampler.memoryPressure()`（`MemorySampler.swift:67-85`）已读 sysctl 并映射为 `MemoryPressureLevel`。新增 metric：
```swift
metrics.append(MonitorMetric(name: "pressure-level", value: pressure.title,
                             numericValue: Double(level.rawValue)))
```
`level` 是 `MemorySampler` 私有 enum，需映射到 `MemoryPressureLevel.rawValue`。

**2. 热压力等级（thermal-state）**
`ProcessInfo.processInfo.thermalState`（macOS 10.10.3+，零成本，返回 `.nominal/.fair/.serious/.critical`，已有 rawValue 0-3）。

> 与 Stats 的区别：Stats 不用 `ProcessInfo.thermalState`，走 SMC 温度传感器（`docs/stats/Modules/CPU/readers.swift` 的 `TemperatureReader`）。HagimiMonitor 采用 `ProcessInfo.thermalState` 作为系统级热节流状态（简单可靠），SMC 温度另行用于 `cpuTemperature`，两者分开。

Recorder 直接读取，无需改 sampler：
```swift
let thermal = ProcessInfo.processInfo.thermalState.rawValue  // 0-3
bucket.thermalStateMax = max(bucket.thermalStateMax, Int16(thermal))
```

**3. Swap 换入换出（swapins/swapouts）**
`MemorySampler` 已调用 `host_statistics64` 拿到 `vm_statistics64`（`MemorySampler.swift:11-17`），但只提取了 7 个字段，未读 `swapins/swapouts`。新增提取并暴露：
```swift
let swapins = Int64(stats.swapins)
let swapouts = Int64(stats.swapouts)
metrics.append(MonitorMetric(name: "swapins", value: String(swapins), numericValue: Double(swapins)))
metrics.append(MonitorMetric(name: "swapouts", value: String(swapouts), numericValue: Double(swapouts)))
```

**4. 电池/AC 供电占比（onBatteryPower）**
`BatterySampler` 已暴露 `type` metric（`"battery"`/`"ac-power"`）。SampleBucket 新增 `onBatteryCount`，每次采样检查 `type` 是否为 `"battery"`，flush 时 `onBatteryPower = onBatteryCount / count`。

**5. 磁盘瞬时读写速率（disk-peak-read/disk-peak-write）**
当前 StorageSampler 只暴露累计字节（`cumulativeBytesRead/Written`），无瞬时速率。需 StorageSampler 维护 previous 状态算 `delta/time`（参照 NetworkSampler 速率计算），暴露 `disk-read-rate`/`disk-write-rate` metric（bytes/sec），Recorder 取 peak。

### SampleBucket 扩展

基于真实现有结构（`StatisticsRecorder.swift:6-42`），注意现有字段初始值：`peak = -.greatestFiniteMagnitude`、`low = .greatestFiniteMagnitude`、字节字段名为 `bytesInSum/bytesOutSum/bytesReadSum/bytesWrittenSum`。

```swift
private struct SampleBucket {
    // ---- 现有字段（勿改）----
    var sum: Double = 0
    var peak: Double = -.greatestFiniteMagnitude
    var low: Double = .greatestFiniteMagnitude
    var count: Int = 0
    var bytesInSum: Int64 = 0
    var bytesOutSum: Int64 = 0
    var bytesReadSum: Int64 = 0
    var bytesWrittenSum: Int64 = 0
    var powerSum: Double = 0
    var powerCount: Int = 0

    // ---- Phase 1 新增 ----
    var swapUsedSum: Double = 0       // bytes，numericValue 求和后 /count
    var swapUsedCount: Int = 0
    var pressureLevelMax: Int16 = -1  // -1 = 无数据；取 max（最严重）
    var thermalStateMax: Int16 = -1   // -1 = 无数据；取 max（最严重）
    var swapinsDelta: Int64 = 0
    var swapoutsDelta: Int64 = 0

    // ---- Phase 2 新增 ----
    var cpuSystemSum: Double = 0
    var cpuUserSum: Double = 0
    var cpuIdleSum: Double = 0
    var cpuTempSum: Double = 0
    var cpuTempCount: Int = 0
    var memoryUsedSum: Double = 0
    var memoryUsedCount: Int = 0
    var diskFree: Int64 = 0           // 取最新值
    var diskFreeCount: Int = 0
    var netPeakDownload: Double = 0   // bytes/sec
    var netPeakUpload: Double = 0
    var diskPeakRead: Double = 0      // bytes/sec
    var diskPeakWrite: Double = 0

    // ---- Phase 3 新增 ----
    var gpuMemorySum: Double = 0
    var gpuMemoryCount: Int = 0
    var gpuRenderSum: Double = 0
    var gpuTilerSum: Double = 0
    var gpuUtilCount: Int = 0
    var batteryHealthSum: Double = 0
    var batteryHealthCount: Int = 0
    var batteryCycleCount: Int = 0
    var batteryCycleCountSet: Bool = false
    var batteryTempSum: Double = 0
    var batteryTempCount: Int = 0
    var onBatteryCount: Int = 0
}
```

`lastCumulative`（`StatisticsRecorder.swift:55`）需扩展，增加 `swapins/swapouts` 上次累计值，用于算 delta：

```swift
private var lastCumulative: [String: (bytesIn: Int64, bytesOut: Int64,
                                       bytesRead: Int64, bytesWritten: Int64,
                                       swapins: Int64, swapouts: Int64)] = [:]
```

### SwiftData Migration

新增字段全部 Optional，SwiftData 轻量迁移自动处理（旧记录新字段为 nil，无需手动 migration plan）。`StatisticsStore`（`StatisticsStore.swift`）用 `ModelContainer(for:configurations:)` 初始化，已支持。

**长期建议**：趁此机会引入 `VersionedSchema` + `SchemaMigrationPlan`。当前裸 `Schema([HourlySample.self, DailyAggregate.self])` 一旦后续需要改字段类型/重命名（非轻量迁移）会锁死演进路径。Phase 0 顺带建立版本化 schema 基础。

### StatisticsDataPoint / StatisticsSummary 扩展

真实结构（`StatisticsAggregator.swift:25-67`）：DataPoint 字段是 `let` 且有 `id = UUID()`，Summary 字段是 `let`。新增字段保持 `let` 风格，由构造器注入。

```swift
struct StatisticsDataPoint: Identifiable {
    let id = UUID()
    // 现有字段
    let date: Date
    let avg: Double
    let peak: Double
    let low: Double
    let bytesIn: Int64?
    let bytesOut: Int64?
    let bytesRead: Int64?
    let bytesWritten: Int64?
    // 新增字段（let）
    let cpuSystem: Double?
    let cpuUser: Double?
    // ... 其余对应表
}

struct StatisticsSummary {
    // 现有 let 字段
    let kind: MonitorKind
    let avg: Double
    let peak: Double
    let low: Double
    let median: Double
    let points: [StatisticsDataPoint]
    let totalBytesIn: Int64?
    // ...
    // 新增聚合字段（let）
    let avgCpuSystem: Double?
    let avgSwapUsed: Int64?
    let peakMemoryPressureLevel: Int16?
    let peakThermalState: Int16?
    // ...
}
```

**重构建议**：`buildSummary`（`StatisticsAggregator.swift:177`）当前接收 9 元素元组，新增 20+ 字段后元组膨胀到 30 元素不可维护。改为 `struct SummaryRow`，queryHourly/queryDaily/buildSummary 三处共用，避免同步出错。

Aggregator 已有 `sumOptionalInt64`/`avgOptionalDouble`（`StatisticsAggregator.swift:242-257`）会 compactMap 掉 nil，新增 Optional 字段天然跳过 nil 聚合，不破坏现有查询。

## 实施策略

### Phase 0 — 前置基础设施（阻塞性，必须先做）

1. `MonitorMetric` 加 `numericValue: Double?`
2. `MemoryPressureLevel` 加 `: Int` rawValue（0/1/2/3）
3. Recorder 新增 `metricNumeric(_:key:) -> Double?` helper
4. （建议）引入 `VersionedSchema` + `SchemaMigrationPlan`
5. 扩展 `lastCumulative` 增加 swapins/swapouts 槽位
6. `buildSummary` 元组重构为 `struct SummaryRow`

### Phase 1 — 高优先级（健康评分/事件检测直接依赖）

7. `swapUsed` — MemorySampler 补 `swap-used` 的 `numericValue`
8. `memoryPressureLevel` — MemorySampler 新增 `pressure-level` metric，bucket 取 max
9. `thermalState` — Recorder 直接读 `ProcessInfo.thermalState`，bucket 取 max
10. `swapins`/`swapouts` — MemorySampler 提取并暴露，bucket 算 delta

### Phase 2 — 中优先级（丰富分析维度）

11. `cpuSystem`/`cpuUser`/`cpuIdle` — CPUSampler 补 numericValue
12. `cpuTemperature` — CPUSampler 补 numericValue（DISPLAY_CONTROL）
13. `memoryUsed` — MemorySampler 补 `used` 的 numericValue
14. `diskFree` — StorageSampler 补 `free` 的 numericValue，bucket 取最新
15. `netPeakDownload`/`netPeakUpload` — NetworkSampler 补 numericValue，bucket 取 peak
16. `diskPeakRead`/`diskPeakWrite` — StorageSampler 新增瞬时速率 metric，bucket 取 peak

### Phase 3 — 低优先级（补充完善）

17. `gpuMemoryUsed`/`gpuRenderUtil`/`gpuTilerUtil` — GPUSampler 补 numericValue
18. `batteryHealth`/`batteryCycleCount`/`batteryTemperature`/`onBatteryPower` — BatterySampler 补 numericValue

### 向后兼容保证

- 所有新增字段为 Optional，旧数据查询返回 nil
- StatisticsView 和 HTML Report 不做修改，新增字段暂不展示（由 mac-health-score / event-timeline 提案负责展示）
- Aggregator 查询对 nil 字段跳过聚合（已有机制）
