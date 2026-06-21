# Design: Mac Health Score

## 评分公式

### 核心思路

采用**算术加权平均 + 热压力硬帽**策略：

1. 每个维度计算一个 0-1 的"健康度"（越高越健康）
2. 加权平均得到总分
3. 热压力为 critical 时硬帽到 20 分（即使其他维度正常，热节流意味着系统已严重降频）

选择算术平均而非几何平均的原因：
- 算术平均更直觉，用户容易理解"CPU 占了 25% 权重"
- 几何平均对极端值过于敏感，一个维度为 0 会导致整体为 0，不够实用
- 热压力硬帽已经处理了"瓶颈惩罚"的需求

### 维度定义

macOS 内存管理哲学：主动填满 RAM 做文件缓存、压缩非活跃页面，内存占用% 无意义；Swap 也是正常内存管理手段。内存健康只看压力等级。

| 维度 | 健康度计算 | 权重 | 数据来源 |
|------|-----------|------|----------|
| CPU | **分段曲线**（见下） | 0.35 | `HourlySample.avg` (kind=cpu) |
| GPU | `(100 - avg%) / 100` | 0.20 | `HourlySample.avg` (kind=gpu) |
| Disk | **阈值扣分**：剩余≥15%满分，<15%线性下降 | 0.15 | `HourlySample.avg` (kind=storage) |
| Memory Pressure | **插值**：avg 0→1.0, 1→0.5, 2→0.0 | 0.25 | `HourlySample.memoryPressureLevel` 加权均值 |
| Thermal | **插值**：avg 0→1.0, 1→0.75, 2→0.5, 3→0.0 | 0.05 | `HourlySample.thermalState` 加权均值 |

**总分公式：**
```
rawScore = 0.35*s_cpu + 0.20*s_gpu + 0.15*s_disk + 0.25*s_pressure + 0.05*s_thermal

score = avgThermalState >= 2.0 ? min(rawScore * 100, 40) : rawScore * 100
```

### 热压力硬帽

原设计硬帽到 20 分（一旦触及 .critical 即触发），实测导致评分剧烈跳变。改为：
- 基于整段窗口的**加权平均热状态**（而非出现过的峰值）
- 阈值 `avgThermalState >= 2.0`（平均处于 serious 及以上）——单次 critical 在 24h 窗口里对均值影响仅约 0.125，不会误触
- 硬帽分数从 20 提升到 **40**——过低的帽值会让分数瞬间从优秀跌到糟糕，缺乏区分度

**CPU（分段曲线）**：低负载接近满分，重载时急剧下降：
```
usage ≤ 70%: health = 1.0 - (usage/70) * 0.15    → 0%→1.0, 70%→0.85
70–90%:      health = 0.85 - ((usage-70)/20) * 0.55 → 90%→0.30
90–100%:     health = 0.30 - ((usage-90)/10) * 0.30  → 100%→0.0
```
选择分段而非线性是因为 CPU 50% 和 90% 的体验差距远大于 40 个百分点，线性无法区分。

**磁盘（阈值扣分）**：磁盘占用本身不等于不健康，只在剩余空间不足时才扣分：
```
free ≥ 15%: health = 1.0
free < 15%: health = free / 15   → 0%→0, 15%→1.0
```

**压力/热状态（连续插值）**：基于整段时间的**加权均值**（排除 unknown=3），而非逐层 max。避免一次瞬时峰值把整个窗口的评分钉死。

### 降级策略

当某些维度数据不可用时（nil），动态调整权重：

```swift
// 示例：thermalState 为 nil 时
var weights: [(value: Double, weight: Double)] = [
    (s_cpu, 0.25),
    (s_mem, 0.20),
    (s_gpu, 0.15),
    (s_disk, 0.10),
    (s_swap, 0.10),
    (s_pressure, 0.15),
    // thermal 缺失，跳过
]
let totalWeight = weights.reduce(0) { $0 + $1.weight }
let rawScore = weights.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
```

### 空数据处理

当指定时间范围内**完全无数据**（CPU 无 HourlySample 且无 pending）时，`queryHealthScore` 返回：
```swift
HealthScore(score: 0, level: .critical, dimensions: [], thermalCapped: false,
            timeRange: range, isDataAvailable: false, trend: [])
```
UI 展示「数据不足」卡片，而非 100 分。这是防止空数据→满分误判的核心防护。

### 评分等级

| 分数范围 | 等级 | 颜色 | 含义 |
|----------|------|------|------|
| 85-100 | 优秀 | 绿色 | 系统轻松运行，资源充裕 |
| 70-84 | 良好 | 青色 | 系统正常，部分资源使用较高 |
| 50-69 | 一般 | 黄色 | 系统有压力，建议关注 |
| 30-49 | 较差 | 橙色 | 系统负荷重，体验可能受影响 |
| 0-29 | 糟糕 | 红色 | 系统严重过载或热节流 |

### 时间范围

统计页面只读**已入库数据**，不含实时 pending 桶。同一小时内反复切换范围，读到的数据完全一致，分数绝对不变。

| 范围 | 数据源 | UI 标签 | 分数稳定性 |
|------|--------|---------|-----------|
| 过去 24 小时 | 已入库 HourlySample（不含当前未 flush 小时） | 过去24小时 | 绝对稳定 |
| 过去 7 天 | 已入库 DailyAggregate（不含今天） | 过去7天 | 绝对稳定 |
| 过去 30 天 | 已入库 DailyAggregate（不含今天） | 过去30天 | 绝对稳定 |
| 过去 1 年 | 已入库 DailyAggregate | （仅 HTML 报告） | 绝对稳定 |

UI picker 只展示 3 个选项（24h/7d/30d），"过去 1 年"仅在 HTML 详细报告中提供。所有范围的评分基于已入库的死数据，不会因当前小时的采样变化而波动。

### 趋势线

`HealthScore.trend: [HealthTrendPoint]` 按时间桶复算分量分（不含热压力硬帽），用于 UI sparkline 和 HTML 报告：
- **24h**：逐小时（24 个点）
- **7d/30d/1y**：逐天（6+N+1 个点，含今天）

每个桶的分数由该桶的 cpu/mem/gpu/disk/swap/pressure/thermal 原始值通过 `scoreFrom` 加权计算，缺失维度自动剔除重分配。趋势线不应用热压力硬帽（避免单桶过热导致整条线扭曲）。

### 分项原始值展示

`DimensionScoreRow` 采用两行布局（修复初版只显示 healthValue 导致的「看不懂」）：
- **第一行**：维度名（左侧）+ 原始值文案（右侧，如 "32%"、"2.3 GB"、"正常"）
- **第二行**：健康度条形图 + 健康分

原始值文案（`rawText`）在聚合器中计算，每种维度使用最直观的格式：
- CPU/GPU/Memory/Disk：`"\(Int(avg))%"`（利用率百分比）
- Swap：格式化为 KB/MB/GB
- Pressure：`压力等级文案`（正常/警告/严重）
- Thermal：`热状态文案`（正常/较热/过热/严重过热）

### 评分说明 Tips

`HealthScoreSection` 标题栏右侧 info 按钮，点击打开 Popover 说明：
- 总分公式：7 个维度加权平均 + 热节流帽
- 各维度含义与计算方式
- 热节流硬帽逻辑
- 数据不足状态

每个维度使用 `health.tips.<dim>` 本地化 key，如「CPU 利用率越低越健康；70% 以下接近满分，超过 90% 急剧下降」。

### 空数据状态

当 `HealthScore.isDataAvailable == false` 时，`HealthScoreSection` 显示占位卡片而非圆环：
- 图标 `chart.bar.xaxis`
- 标题「当前时间范围数据不足」
- 副标题「请稍后再试，或切换其他时间范围。」

## UI 设计

> 实现原则：**保留现有 SummaryCard 卡片设计不动**，仅新增健康评分区域。新增 UI 统一采用 macOS 26 液态玻璃（`GlassEffectContainer` + `.glassEffect()`）与 Apple 设计风格，与设置页既有玻璃质感一致。

### 全局时间范围选择器（共享改动，本提案引入）

现有 `StatisticsView` 固定 `.last24Hours`、无时间选择器（`StatisticsView.swift:114`）。本提案在 header（标题与"详细报告"按钮之间）新增一个**页面级** segmented 选择器：

- 选项：24 小时 / 7 天 / 30 天 / 1 年（**不做 1 小时**——hourly 粒度不足以支撑卡片网格，且当前小时数据仅 PendingBucket 覆盖）
- 绑定 `StatisticsView` 新增的 `@State private var range: StatisticsTimeRange`
- 切换时三块（健康评分 / summaryGrid / 事件时间线）共用同一个 `range`，统一 `refreshData()` 重新查询，**视觉与交互统一，不割裂**
- `StatisticsTimeRange`（`StatisticsAggregator.swift:6`）已有 last24Hours/lastWeek/lastMonth/lastYear/custom，**无需新增 case**；现有 SummaryCard 把写死的 `.last24Hours` 改为绑定全局 `range`，pending 仅 24h 传入

### StatisticsView VStack 顺序

`StatisticsView.swift:17` 的 `VStack(alignment:.leading, spacing:18)` 改为：

```
header            // 标题 + 副标题 + [新增]全局范围选择器 + 详细报告按钮
healthScore       // ← 本提案新增，summaryGrid 上方
summaryGrid       // 现有 SummaryCard，保留设计，跟随全局 range
eventTimeline     // ← event-timeline 提案新增，summaryGrid 下方
errorBanner       // 现有，不动
```

### 健康评分区域（液态玻璃）

**大圆环 `HealthScoreRingView`**（全新 SwiftUI 组件，非复用）：
- `MenuBarComputeRingIcon` 是 AppKit NSImage 18px、绑定 MenuBarComputeLoadLevel，**不可复用**，须用 SwiftUI（`Circle().trim()` 或 `Canvas`）全新绘制
- 进度弧颜色按等级渐变（优秀绿 → 良好青 → 一般黄 → 较差橙 → 糟糕红）
- 中心显示分数（rounded 字体）与等级文字
- 容器使用 `GlassEffectContainer` + `.glassEffect(.regular.tint(...))`，尺寸约 120pt

**分项条形图 `DimensionScoreRow`**：
- 两行布局：第一行维度名 + 原始值文案，第二行健康度条形图 + 健康分
- 条形图复用 `Capsule` 实现，颜色跟随维度等级
- 颜色取自 `MonitorPalette.healthTint(for: HealthLevel)`

**信息按钮 `HealthTipsPopover`**：
- 标题栏右侧 info.circle 按钮，点击打开 Popover（width: 280, maxHeight: 360）
- 内容：总分说明 + 各维度含义 + 热节流说明
- 本地化 key：`health.tips.button`、`health.tips.title`、`health.tips.intro`、`health.tips.<dim>`

**趋势线 `HealthTrendSparkline`**：
- 圆环下方、分项上方，宽度同圆环（100pt），高度 22pt
- SwiftUI Path 折线，颜色从绿→黄→红渐变
- 仅在 `trend.count >= 2` 时显示

**空数据状态**：
- `!isDataAvailable` 时渲染占位卡片：图标 + 「数据不足」+ 提示文字
- 不再将空数据算为 100 分

**范围联动**：健康评分通过 `queryHealthScore(range:)` 复用全局 `range`，无独立选择器。

### HTML Report 中的健康评分

在 `StatisticsReportHTMLBuilder` 每个 range 的 `<section class="grid" id="cards">` 之前插入健康评分卡片：
- 复用报告现有 CSS 变量（`--c-cpu` 等）与 light/dark 双套配色
- 显示该 range 的平均健康分 + SVG 圆环 + 各维度分项条形图
- **不做"健康分趋势线"**（payload 无逐天 healthScore 点结构，Aggregator 无按天逐算能力，属隐藏工作量）——若未来需要再扩展 `StatisticsReportPayload`


## 数据流

```
StatisticsAggregator
  ├─ queryHealthScore(range: .last24Hours)
  │   ├─ 查询各 kind 的 HourlySample / DailyAggregate
  │   ├─ 查询 swapUsed, memoryPressureLevel, thermalState
  │   ├─ 计算各维度健康度
  │   ├─ 加权平均
  │   └─ 应用热压力硬帽
  │
  └─ 返回 HealthScore {
       score: Double          // 0-100
       level: HealthLevel     // excellent/good/fair/poor/critical
       dimensions: [DimensionScore]  // 各维度详情
     }
```

### HealthScore 数据结构

```swift
enum HealthLevel: String {
    case excellent  // 85-100
    case good       // 70-84
    case fair       // 50-69
    case poor       // 30-49
    case critical   // 0-29
}

struct DimensionScore {
    let name: String           // "CPU", "Memory", etc.
    let rawValue: Double       // 原始值 (e.g., 72%)
    let healthValue: Double    // 健康度 0-1
    let weight: Double         // 权重
    let level: HealthLevel     // 该维度等级
    let isAvailable: Bool      // 数据是否可用
}

struct HealthScore {
    let score: Double          // 0-100
    let level: HealthLevel
    let dimensions: [DimensionScore]
    let thermalCapped: Bool    // 是否被热压力硬帽限制
    let timeRange: StatisticsTimeRange
}
```

## 权重可配置性

当前版本使用固定权重。为未来扩展预留：

1. 权重定义在一个 `HealthScoreWeights` 结构体中，而非硬编码在计算逻辑里
2. `MonitorSettings` 中预留 `healthScoreWeights` 属性（当前不暴露 UI）
3. 未来可根据设备型号自动调整权重（如 MacBook Air 更关注热压力，Mac Studio 更关注 GPU）

```swift
struct HealthScoreWeights {
    var cpu: Double = 0.25
    var memory: Double = 0.25
    var gpu: Double = 0.15
    var disk: Double = 0.10
    var swap: Double = 0.10
    var pressure: Double = 0.10
    var thermal: Double = 0.05

    var allWeights: [Double] { [cpu, memory, gpu, disk, swap, pressure, thermal] }
    var total: Double { allWeights.reduce(0, +) }

    /// 归一化权重（确保总和为 1.0）
    func normalized() -> HealthScoreWeights {
        let t = total
        guard t > 0 else { return Self() }
        return HealthScoreWeights(
            cpu: cpu/t, memory: memory/t, gpu: gpu/t,
            disk: disk/t, swap: swap/t, pressure: pressure/t, thermal: thermal/t
        )
    }
}
```

## 本地化

新增以下本地化 key：

| Key | zh-Hans | en |
|-----|---------|-----|
| `health.title` | Mac 健康评分 | Mac Health Score |
| `health.level.excellent` | 优秀 | Excellent |
| `health.level.good` | 良好 | Good |
| `health.level.fair` | 一般 | Fair |
| `health.level.poor` | 较差 | Poor |
| `health.level.critical` | 糟糕 | Critical |
| `health.dimension.cpu` | CPU | CPU |
| `health.dimension.memory` | 内存 | Memory |
| `health.dimension.gpu` | GPU | GPU |
| `health.dimension.disk` | 磁盘 | Disk |
| `health.dimension.swap` | Swap | Swap |
| `health.dimension.pressure` | 内存压力 | Memory Pressure |
| `health.dimension.thermal` | 散热 | Thermal |
| `health.thermal-capped` | 热节流中 | Thermal Throttling |
| `health.range.1h` | 1 小时 | 1 Hour |
| `health.range.7d` | 7 天 | 7 Days |
| `health.range.30d` | 30 天 | 30 Days |
