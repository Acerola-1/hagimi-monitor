# Tasks: Mac Health Score

## 1. 数据结构与计算逻辑
- [x] 定义 `HealthLevel` 枚举（excellent/good/fair/poor/critical，阈值 85/70/50/30）
- [x] 定义 `DimensionScore` 结构体（name, rawText, rawValue, healthValue, weight, level, isAvailable）
- [x] 定义 `HealthScore` 结构体（score, level, dimensions, thermalCapped, timeRange, isDataAvailable, trend）
- [x] 定义 `HealthScoreWeights` 结构体（默认权重 + 归一化方法）
- [x] 在 `StatisticsAggregator` 中实现 `queryHealthScore(range:)` 方法，复用现有 `query(kind:range:pending:)`
- [x] 实现各维度健康度计算函数（`HealthCalc`：CPU 分段、内存/GPU 线性、磁盘阈值、Swap 占比、压力/热状态插值）
- [x] 实现加权平均 + 热压力硬帽逻辑（基于平均热状态 ≥2.0 时软帽到 40）
- [x] 实现数据缺失时的动态权重降级
- [x] **空数据检测**：range 无持久化/未落库数据时返回 `isDataAvailable=false`，UI 显示「数据不足」（修复空数据=100 的 bug）
- [x] **sticky max 修复**：压力/热状态改用按采样数加权均值（`avgMemoryPressureLevel`/`avgThermalState`），替代逐层 max
- [x] **范围可比性**：daily 查询排除今天的 DailyAggregate，改由今天 HourlySample + pending 实时拼出，使 24h/7d/30d/1年 在「今天」口径一致
- [x] **趋势线**：`buildTrend` 按时间桶复算分量分（`HealthTrendPoint`），UI 与 HTML 报告均渲染
- [x] 编写单元测试覆盖：空数据、正常评分、热压力硬帽、CPU 分段公式、磁盘阈值、趋势线

## 2. 全局时间范围选择器（共享改动，本提案引入）
- [x] 在 `StatisticsView` 新增 `@State private var range: StatisticsTimeRange`，默认 `.last24Hours`
- [x] 在 header（标题与"详细报告"按钮之间）新增 `Picker(.segmented)`：24小时 / 7天 / 30天 / 1年（**不做 1 小时**）
- [x] 将现有 `summaryGrid` 的 `aggregator.query(..., range: .last24Hours, ...)` 改为绑定全局 `range`，pending 仅 `.last24Hours` 时传入
- [x] 切换 range 时触发 `refreshData()` 重新查询健康评分、summaryGrid、事件时间线（三者共用 range）
- [x] 确认 `StatisticsTimeRange` 无需新增 case（已有 24h/week/month/year）

## 3. StatisticsView 健康评分区域（液态玻璃）
- [x] 新增 `HealthScoreRingView`（SwiftUI 全新组件，`Circle().trim()` 或 `Canvas`，约 100pt，等级着色渐变）
  - 注：`MenuBarComputeRingIcon` 是 AppKit NSImage 18px 不可复用，必须全新绘制
- [x] 容器使用 `GlassEffectContainer` + `.glassEffect(.regular.tint(...))`
- [x] 新增 `DimensionScoreRow`（两行布局：维度名+原始值文案 / 健康度条+健康分），显示原始值修复「看不懂」
- [x] 新增 `HealthScoreSection`（组合 Ring + 趋势 sparkline + 分项列表 + tips 按钮，跟随全局 range）
- [x] 新增 `HealthTipsPopover`（info 按钮触发的评分说明：公式、各维度含义、热节流）
- [x] 新增 `HealthTrendSparkline`（环下方分量分趋势线）
- [x] 数据不足空状态：`!isDataAvailable` 时显示「数据不足」卡片，不再算出 100
- [x] 在 `StatisticsView` VStack 中将 `HealthScoreSection` 插入 summaryGrid 上方
  - VStack 顺序：header → healthScore → summaryGrid → eventTimeline → errorBanner

## 4. 颜色与主题
- [x] 在 `MonitorPalette` 中新增 `healthTint(for: HealthLevel)`（5 级颜色，适配 balanced/vibrant + light/dark）
- [x] `HealthScoreRingView` 使用 palette 颜色
- [x] `DimensionScoreRow` 条形图颜色跟随维度等级
- [x] 趋势线 `HealthTrendSparkline` 使用绿→黄→红渐变
- [x] 注意：`critical` 在 MonitorSeverity/MemoryPressureLevel/HealthLevel 三处语义不同，命名避免混淆

## 5. HTML Report 健康评分
- [x] 在 `StatisticsReportPayload` 中新增 `healthScore` 字段（每 range 一个）
- [x] 在 `StatisticsReportHTMLBuilder` 中新增健康评分卡片（SVG 圆环 + 分项条形图），复用现有 CSS 变量与 light/dark 配色
- [x] 健康评分卡片放在各 range 的 `<section class="grid">` 之前
- [x] HTML 分项行新增 `rawText` 列显示原始值文案，修复 `isAvailable` 字段缺失导致行不显示的 bug
- [x] HTML 趋势线：SVG 折线（绿→黄→红渐变），data 不足时显示空状态文案
- [x] **不做健康分趋势图的历史版本**（payload 仅有聚合分量分，无逐天 healthScore 趋势）

## 6. 本地化
- [x] 在 `Localizable.xcstrings` 中添加所有 `health.*` key（zh-Hans + en + ja）
- [x] 新增 `health.no-data`、`health.no-data.hint`（空状态文案）
- [x] 新增 `health.tips.button`、`health.tips.title`、`health.tips.intro`（评分说明）
- [x] 新增 `health.tips.cpu`/`memory`/`gpu`/`disk`/`swap`/`pressure`/`thermal`（各维度说明）
- [x] 复用 `event.pressure.*`/`event.thermal.*` 作为 pressure/thermal 维度的 rawText 显示文案

## 7. 验证
- [x] Build 通过（`HagimiMonitorDirect` Debug build succeeded）
- [x] StatisticsTests 全部通过（7 个新增健康评分测试 + 原有测试不变）
- [x] 单元测试覆盖：空数据检测、正常评分、热压力硬帽、CPU 分段公式、磁盘阈值、趋势线
- [x] `DimensionScore` 新增 `rawText` 字段，HTML payload 同步修复 `isAvailable` 缺失
- [ ] 手动验证：运行 app 后 StatisticsView 显示健康评分（液态玻璃风格）+ tips 按钮 + 趋势线
- [ ] 手动验证：切换全局时间范围后，健康评分、卡片、事件时间线三者同步更新
- [ ] 手动验证：7d/30d/1y 范围包含今天数据（评分与 24h 在今天口径一致）
- [ ] 手动验证：HTML Report 包含健康评分卡片 + 趋势线
- [ ] 手动验证：热压力持续 serious 以上时评分被限制
- [ ] 手动验证：无数据时显示「数据不足」卡片

## 依赖
- **enhance-statistics-data-collection** Phase 1 必须先落地：需要 `swapUsed`, `memoryPressureLevel`, `thermalState`, `swapins/swapouts` 字段及 `MonitorMetric.numericValue`
