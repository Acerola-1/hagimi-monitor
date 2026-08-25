# Design: Event Timeline

## 事件类型定义

### SystemEvent 模型

```swift
enum SystemEventType: String, Codable {
    // CPU 事件
    case cpuSustainedHigh      // CPU 持续高负载
    case cpuSpike              // CPU 瞬时峰值

    // GPU 事件
    case gpuSustainedHigh      // GPU 持续高负载

    // 内存事件
    case memoryPressureUpgrade // 内存压力等级升级 (normal→warning, warning→critical)
    case memoryPressureDowngrade // 内存压力等级降级
    case swapUsageSpike        // Swap 使用量突增

    // 热压力事件
    case thermalUpgrade        // 热压力升级 (nominal→fair, fair→serious, serious→critical)
    case thermalDowngrade      // 热压力降级

    // 电池事件
    case batteryOverheat       // 电池温度过高
    case batteryHealthLow      // 电池健康度低
    case powerSourceChange     // 电源切换 (AC↔电池)

    // 磁盘事件
    case diskSpaceLow          // 磁盘空间不足
    case diskIOSpike           // 磁盘 I/O 峰值

    // 网络事件
    case networkSpike          // 网络流量峰值
}

@Model
final class SystemEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var eventType: String      // SystemEventType.rawValue
    var severity: Int16        // 0=info, 1=warning, 2=critical
    var title: String          // 本地化标题
    var detail: String         // 详细描述
    var topProcesses: String?  // JSON array: ["Xcode", "swift-frontend"]
    var value: Double?         // 触发值 (e.g., 92.3 for CPU%)
    var previousValue: Double? // 变化前的值 (e.g., 45.0 for previous pressure level)
    var duration: Double?      // 持续时长 (秒), 用于 sustained 事件
}
```

## 事件检测逻辑

### 检测时机

事件检测发生在两个时机：

1. **实时检测**（每次采样时）：检测瞬时状态变化
   - 内存压力等级变化
   - 热压力等级变化
   - 电源切换
   - 电池温度过高

2. **批量检测**（flush 时，每小时一次）：检测趋势性事件
   - CPU 持续高负载
   - Swap 突增
   - 磁盘空间不足

### 实时检测设计

在 `MonitorStore.applySamplingResult()` 中，采样完成后检查状态变化：

```swift
// 内存压力等级变化检测
let currentPressure = memoryModule.pressure  // MemoryPressureLevel
if currentPressure != previousPressure {
    let isUpgrade = currentPressure.rawValue > previousPressure.rawValue
    let eventType: SystemEventType = isUpgrade ? .memoryPressureUpgrade : .memoryPressureDowngrade
    let severity: Int16 = (currentPressure == .critical) ? 2 : (currentPressure == .warning ? 1 : 0)
    recordEvent(eventType, severity: severity, value: Double(currentPressure.rawValue),
                previousValue: Double(previousPressure.rawValue))
    previousPressure = currentPressure
}
```

```swift
// 热压力变化检测
let currentThermal = ProcessInfo.processInfo.thermalState
if currentThermal != previousThermal {
    let isUpgrade = currentThermal.rawValue > previousThermal.rawValue
    let eventType: SystemEventType = isUpgrade ? .thermalUpgrade : .thermalDowngrade
    let severity: Int16 = (currentThermal == .critical) ? 2 : (currentThermal == .serious ? 1 : 0)
    recordEvent(eventType, severity: severity, value: Double(currentThermal.rawValue),
                previousValue: Double(previousThermal.rawValue))
    previousThermal = currentThermal
}
```

```swift
// CPU 持续高负载检测（使用滑动窗口）
private var cpuHighLoadStartTime: Date?
private let cpuHighLoadThreshold: Double = 85.0  // 85%
private let cpuHighLoadMinDuration: TimeInterval = 300  // 5 分钟

func checkCPUHighLoad(currentCPU: Double) {
    if currentCPU >= cpuHighLoadThreshold {
        if cpuHighLoadStartTime == nil {
            cpuHighLoadStartTime = Date()
        }
        let duration = Date().timeIntervalSince(cpuHighLoadStartTime!)
        if duration >= cpuHighLoadMinDuration {
            let topProcess = topCPUProcesses.first?.name
            recordEvent(.cpuSustainedHigh, severity: 1,
                       value: currentCPU, duration: duration,
                       topProcesses: topProcess.map { [$0] })
            cpuHighLoadStartTime = nil  // 重置，避免重复记录
        }
    } else {
        cpuHighLoadStartTime = nil
    }
}
```

### 批量检测设计

在 `StatisticsRecorder.flushCurrentBuckets()` 中，flush 后检查小时级趋势：

```swift
// Swap 突增检测
if let swapUsed = bucket.swapUsedSum, swapUsed > 0 {
    let previousSwap = previousHourSwapUsed  // 上小时的 Swap 使用量
    if let prev = previousSwap, swapUsed > prev * 2 {  // 增长超过 100%
        recordEvent(.swapUsageSpike, severity: 1,
                   value: Double(swapUsed), previousValue: Double(prev))
    }
}

// 磁盘空间不足检测
if let diskFree = bucket.diskFree, diskFree < 5 * 1024 * 1024 * 1024 {  // < 5GB
    recordEvent(.diskSpaceLow, severity: diskFree < 1_000_000_000 ? 2 : 1,
               value: Double(diskFree))
}
```

### Top Process 关联

当前 Top Process 数据只在面板可见时才采样。为了在事件发生时记录 Top Process：

**方案 A（推荐）**：事件检测时按需获取
- 在 `recordEvent()` 中，如果 `topCPUProcesses` / `topMemoryProcesses` 非空，取 Top 1-3
- 如果面板不可见导致进程列表为空，topProcesses 字段为 nil
- 这是"尽力而为"——有最好，没有也不影响事件记录

**方案 B**：始终采样 Top Process（不推荐）
- 即使面板不可见也保持 Top Process 采样
- 会增加 CPU 开销，与"优化 CPU 使用"目标冲突

## 事件数据保留策略

| 事件严重度 | 保留时间 | 说明 |
|-----------|----------|------|
| info (0) | 30 天 | 如压力降级、电源切换 |
| warning (1) | 90 天 | 如持续高负载、Swap 突增 |
| critical (2) | 永久 | 如热压力 critical、电池过热 |

清理逻辑在 `flushCurrentBuckets()` 中执行，与 HourlySample 清理同步。

## UI 设计

> 实现原则：**复用 mac-health-score 提案引入的全局时间范围选择器**，事件时间线跟随同一 `range`，无独立选择器。新增 UI 采用 macOS 26 液态玻璃（`GlassEffectContainer` + `.glassEffect()`）与 Apple 设计风格。

### StatisticsView 时间线区域

在 `StatisticsView.swift:17` 的 VStack 中，summaryGrid 之后、errorBanner 之前插入事件时间线（VStack 顺序详见 mac-health-score 提案）：

- **范围联动**：时间线通过 `queryEvents(range:)` 复用全局 `range`，与卡片/健康评分同步切换
- **布局**：整块用 `.glassEffect()` 液态玻璃容器包裹，与设置页既有玻璃质感一致

**组件设计**：
- `EventTimelineSection` — 顶部容器：标题（"系统事件"）+ 当前范围事件计数 + 事件列表
- `EventTimelineDay` — 按天分组，显示日期头和该天事件（24h 范围按"今天/昨天"分组，7d/30d/1年按日期分组）
- `EventTimelineRow` — 单个事件行：时间 + 严重度图标 + 标题 + 详情 + Top Process
- 严重度图标使用 SF Symbol（与 Apple 风格一致）：
  - critical: `exclamationmark.triangle.fill` 红色
  - warning: `exclamationmark.circle.fill` 黄色
  - info: `info.circle.fill` 灰色
- 时间线竖线 + 节点用 SwiftUI `Canvas` 或 `Path` 绘制，节点颜色按严重度
- "显示更多"按钮加载更早的事件（分页）

### HTML Report 时间线

在 `StatisticsReportHTMLBuilder` 每个 range 的 `<section class="grid" id="cards">` 之后追加事件时间线区域：
- 复用报告现有 CSS 变量与 light/dark 双套配色
- 竖线 + 节点的时间线样式
- 每个节点显示时间、事件类型、详情
- 严重度用颜色区分（红/黄/灰）


## 事件去重

同类事件在短时间内可能频繁触发（如 CPU 持续高负载每 5 分钟触发一次）。去重策略：

1. **cpuSustainedHigh**：记录后重置 `cpuHighLoadStartTime`，下一次需重新积累 5 分钟
2. **memoryPressureUpgrade / thermalUpgrade**：只在等级实际变化时记录，不会重复
3. **swapUsageSpike**：每小时 flush 时最多检测一次
4. **batteryOverheat**：每次温度从正常范围进入过热范围时记录一次，降回正常后才能再次触发

## 本地化

新增以下本地化 key：

| Key | zh-Hans | en |
|-----|---------|-----|
| `event.title` | 系统事件 | System Events |
| `event.cpu-sustained-high` | CPU 持续高负载 | CPU Sustained High Load |
| `event.cpu-spike` | CPU 瞬时峰值 | CPU Spike |
| `event.gpu-sustained-high` | GPU 持续高负载 | GPU Sustained High Load |
| `event.memory-pressure-upgrade` | 内存压力升级 | Memory Pressure Escalation |
| `event.memory-pressure-downgrade` | 内存压力缓解 | Memory Pressure Relief |
| `event.swap-usage-spike` | Swap 使用突增 | Swap Usage Spike |
| `event.thermal-upgrade` | 散热压力升级 | Thermal Pressure Escalation |
| `event.thermal-downgrade` | 散热压力缓解 | Thermal Pressure Relief |
| `event.battery-overheat` | 电池温度过高 | Battery Overheating |
| `event.battery-health-low` | 电池健康度低 | Low Battery Health |
| `event.power-source-change` | 电源切换 | Power Source Changed |
| `event.disk-space-low` | 磁盘空间不足 | Low Disk Space |
| `event.disk-io-spike` | 磁盘 I/O 峰值 | Disk I/O Spike |
| `event.network-spike` | 网络流量峰值 | Network Traffic Spike |
| `event.top-processes` | Top 进程 | Top Processes |
| `event.today` | 今天 | Today |
| `event.yesterday` | 昨天 | Yesterday |
| `event.show-more` | 显示更多 | Show More |
| `event.duration` | 持续 {value} | Duration: {value} |
| `event.pressure.normal` | 正常 | Normal |
| `event.pressure.warning` | 警告 | Warning |
| `event.pressure.critical` | 严重 | Critical |
| `event.thermal.nominal` | 正常 | Nominal |
| `event.thermal.fair` | 较热 | Warm |
| `event.thermal.serious` | 过热 | Hot |
| `event.thermal.critical` | 严重过热 | Critical |
