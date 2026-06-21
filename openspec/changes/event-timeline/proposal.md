# Proposal: Event Timeline

## Summary
在统计数据中引入事件检测和记录机制，将"数值变化"转化为"发生了什么"，为用户提供可理解的历史叙述而非单纯的数字趋势。

## Problems
- 当前统计只记录数值（avg/peak/low），不记录"事件"——用户无法知道"昨天下午 CPU 为什么那么高"
- 高负载时段缺少 Top Process 关联——知道 CPU 92% 但不知道是谁导致的
- 内存压力从 normal 升到 warning 是重要的状态转换，但当前只记录平均百分比，等级变化被淹没
- 电池温度过高、Swap 突增等异常情况没有被标记
- 竞品 iStat Menus 有强大的 Rules 告警系统，Stats 有基础阈值通知，HagimiMonitor 没有任何告警

## Goals
- 定义可检测的系统事件类型（持续高负载、压力等级变更、Swap 突增、热压力升级、电池温度过高等）
- 在 StatisticsRecorder 的 flush 路径上检测事件
- 持久化事件到 SwiftData（EventType + 时间戳 + 详情 + Top Process）
- 在 StatisticsView 中以时间线方式展示事件，新增 UI 采用 macOS 26 液态玻璃 + Apple 设计风格
- 在 HTML Report 中以时间线方式展示事件
- 时间线**复用 mac-health-score 引入的全局时间范围选择器**，跟随同一 range 联动，无独立选择器
- 事件检测阈值可配置（后续版本）

## Non-Goals
- 不做实时推送通知（macOS UserNotifications），这是后续 change
- 不做自定义事件规则（如 iStat Menus 的 Rules 系统）
- 不做进程级别的长期追踪（只记录触发事件时的 Top 1-3 进程名）
- 不做事件过滤/搜索

## Impact
- `StatisticsModels.swift` — 新增 `SystemEvent` SwiftData 模型
- `StatisticsRecorder.swift` — flush 路径上新增事件检测逻辑
- `StatisticsStore.swift` — schema 新增 SystemEvent
- `StatisticsView.swift` — 新增时间线展示区域（复用全局 range）
- `StatisticsReportExporter.swift` — HTML Report 新增时间线
- `MonitorStore` — 事件检测可能需要 Top Process 信息（当前 Top Process 数据在面板可见时才采样）

## Dependencies
- **enhance-statistics-data-collection** (Phase 1): 需要 `memoryPressureLevel`, `thermalState`, `swapUsed` 字段用于事件检测
- **mac-health-score**: 复用其引入的全局时间范围选择器（StatisticsView header）
