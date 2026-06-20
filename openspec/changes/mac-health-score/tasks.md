# Tasks: Mac Health Score

## 1. 数据结构与计算逻辑
- [x] 定义 `HealthLevel` 枚举（excellent/good/fair/poor/critical，阈值 85/70/50/30）
- [x] 定义 `DimensionScore` 结构体（name, rawValue, healthValue, weight, level, isAvailable）
- [x] 定义 `HealthScore` 结构体（score, level, dimensions, thermalCapped, timeRange）
- [x] 定义 `HealthScoreWeights` 结构体（默认权重 + 归一化方法）
- [x] 在 `StatisticsAggregator` 中实现 `queryHealthScore(range:)` 方法，复用现有 `query(kind:range:pending:)`
- [x] 实现各维度健康度计算函数
- [x] 实现加权平均 + 热压力硬帽逻辑
- [x] 实现数据缺失时的动态权重降级
- [ ] 编写单元测试覆盖：正常评分、热压力硬帽、数据缺失降级、边界值

## 2. 全局时间范围选择器（共享改动，本提案引入）
- [x] 在 `StatisticsView` 新增 `@State private var range: StatisticsTimeRange`，默认 `.last24Hours`
- [x] 在 header（标题与"详细报告"按钮之间）新增 `Picker(.segmented)`：24小时 / 7天 / 30天 / 1年（**不做 1 小时**）
- [x] 将现有 `summaryGrid` 的 `aggregator.query(..., range: .last24Hours, ...)` 改为绑定全局 `range`，pending 仅 `.last24Hours` 时传入
- [x] 切换 range 时触发 `refreshData()` 重新查询健康评分、summaryGrid、事件时间线（三者共用 range）
- [x] 确认 `StatisticsTimeRange` 无需新增 case（已有 24h/week/month/year）

## 3. StatisticsView 健康评分区域（液态玻璃）
- [x] 新增 `HealthScoreRingView`（SwiftUI 全新组件，`Circle().trim()` 或 `Canvas`，约 120pt，等级着色渐变）
  - 注：`MenuBarComputeRingIcon` 是 AppKit NSImage 18px 不可复用，必须全新绘制
- [x] 容器使用 `GlassEffectContainer` + `.glassEffect(.regular.tint(...))`
- [x] 新增 `DimensionScoreRow`（维度名称 + 原始值 + 健康度条形图 + 等级标签），条形图复用 `ProgressMeter`
- [x] 新增 `HealthScoreSection`（组合 Ring + 分项列表，跟随全局 range，无独立选择器）
- [x] 在 `StatisticsView` VStack 中将 `HealthScoreSection` 插入 summaryGrid 上方
  - VStack 顺序：header → healthScore → summaryGrid → eventTimeline → errorBanner

## 4. 颜色与主题
- [x] 在 `MonitorPalette` 中新增 `healthTint(for: HealthLevel)`（5 级颜色，适配 balanced/vibrant + light/dark）
- [x] `HealthScoreRingView` 使用 palette 颜色
- [x] `DimensionScoreRow` 条形图颜色跟随维度等级
- [x] 注意：`critical` 在 MonitorSeverity/MemoryPressureLevel/HealthLevel 三处语义不同，命名避免混淆

## 5. HTML Report 健康评分
- [x] 在 `StatisticsReportPayload` 中新增 `healthScore` 字段（每 range 一个）
- [x] 在 `StatisticsReportHTMLBuilder` 中新增健康评分卡片（SVG 圆环 + 分项条形图），复用现有 CSS 变量与 light/dark 配色
- [x] 健康评分卡片放在各 range 的 `<section class="grid">` 之前
- [x] **不做健康分趋势线**（payload 无逐天结构，属隐藏工作量，未来再扩展）

## 6. 本地化
- [x] 在 `Localizable.xcstrings` 中添加所有 `health.*` key（zh-Hans + en + ja）

## 7. 验证
- [x] Build 通过
- [x] StatisticsTests 通过
- [ ] 手动验证：运行 app 后 StatisticsView 显示健康评分（液态玻璃风格）
- [ ] 手动验证：切换全局时间范围后，健康评分、卡片、事件时间线三者同步更新
- [ ] 手动验证：HTML Report 包含健康评分卡片
- [ ] 手动验证：热压力为 serious/critical 时评分显著下降

## 依赖
- **enhance-statistics-data-collection** Phase 1 必须先落地：需要 `swapUsed`, `memoryPressureLevel`, `thermalState`, `swapins/swapouts` 字段及 `MonitorMetric.numericValue`
