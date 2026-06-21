# Proposal: Mac Health Score

## Summary
引入一个 0-100 的 Mac 健康评分，将 CPU、GPU、内存、Swap、热压力等多维指标聚合为一个直观的数字，让用户一眼判断"我的 Mac 现在状态如何"。评分基于历史统计数据，而非实时瞬时值。

## Problems
- 用户看到 6 个独立百分比，需要自己在脑中合成"整体好不好"
- 没有一个指标能反映"木桶效应"——某个维度极端恶化时整体体验已很差，但其他维度正常会掩盖问题
- 热节流（thermal throttling）是 Mac 用户最关心的体验问题之一，但没有被量化反映
- 竞品（iStat Menus、Stats、Eul、RunCat）均无健康评分功能，这是差异化机会

## Goals
- 设计一个算术加权平均 + 热压力硬帽的健康评分公式
- 评分基于 `enhance-statistics-data-collection` change 新增的持久化数据
- 在 StatisticsView 中展示健康评分（大圆环 + 分项条形图），新增 UI 采用 macOS 26 液态玻璃 + Apple 设计风格，**保留现有 SummaryCard 卡片设计不动**
- 在 HTML Report 中展示健康评分卡片
- 在 StatisticsView header 引入**全局时间范围选择器**（24h / 7d / 30d / 1年），健康评分、SummaryCard、事件时间线共用同一范围联动切换
- 为未来可能的同机型绝对阈值调优预留扩展点

## Non-Goals
- 不做同机型比对或相对百分位评分（需要服务器和用户数据）
- 不做实时健康评分（评分基于历史统计，不是瞬时值）
- **不做 1 小时范围**（hourly 粒度不足以支撑卡片网格）
- 不做告警/通知（由 event-timeline change 负责）
- 不改变现有 ring icon 的 ComputeLoadModel（ring icon 是实时负载，健康评分是历史状态，两者独立）
- 不做健康分趋势线（payload 无逐天结构，隐藏工作量，未来再扩展）

## Impact
- `StatisticsAggregator.swift` — 新增 `queryHealthScore(range:)` 计算逻辑
- `StatisticsView.swift` — 新增全局范围选择器 + 健康评分区域；现有 SummaryCard 改为绑定全局 range
- `StatisticsReportExporter.swift` — HTML Report 新增健康评分卡片
- `MonitorPalette.swift` — 新增 `healthTint(for:)` 健康评分颜色映射
- 依赖 `enhance-statistics-data-collection` change 的 Phase 1 数据（含 `MonitorMetric.numericValue`）

## Dependencies
- **enhance-statistics-data-collection** (Phase 1): 需要 `swapUsed`, `memoryPressureLevel`, `thermalState`, `swapins/swapouts` 字段及 `MonitorMetric.numericValue`
