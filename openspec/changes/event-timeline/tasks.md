# Tasks: Event Timeline

## 1. 数据模型与存储
- [x] 定义 `SystemEventType` 枚举（所有事件类型）
- [x] 定义 `SystemEvent` SwiftData `@Model`（id, timestamp, eventType, severity, title, detail, topProcesses, value, previousValue, duration）
- [x] 在 `StatisticsStore.container` schema 中注册 `SystemEvent.self`
- [x] 实现 SwiftData 轻量迁移
- [x] 定义事件保留策略（info=30d, warning=90d, critical=永久）
- [x] 实现 `cleanupOldEvents()` 在 flush 时执行

## 2. 实时事件检测
- [x] 在 `MonitorStore` 中新增 `previousPressureLevel` 状态变量
- [x] 在 `MonitorStore` 中新增 `previousThermalState` 状态变量
- [x] 在 `MonitorStore` 中新增 `cpuHighLoadStartTime` 状态变量
- [x] 实现 `checkMemoryPressureChange(current:)` 检测压力等级变化
- [x] 实现 `checkThermalStateChange()` 检测热压力变化
- [x] 实现 `checkCPUHighLoad(current:)` 检测 CPU 持续高负载（85%, 5min）
- [x] 实现 `checkBatteryOverheat(temperature:)` 检测电池过热（>40°C）
- [x] 实现 `checkPowerSourceChange(type:)` 检测电源切换
- [x] 在 `applySamplingResult()` 中调用以上检测函数

## 3. 批量事件检测
- [x] 在 `StatisticsRecorder.flushCurrentBuckets()` 中新增 Swap 突增检测（增长 >100%）
- [x] 新增磁盘空间不足检测（<5GB warning, <1GB critical）
- [x] 新增磁盘 I/O 峰值检测
- [x] 新增网络流量峰值检测

## 4. 事件记录
- [x] 实现 `recordEvent()` 方法，写入 SystemEvent 到 SwiftData
- [x] 实现事件去重逻辑（cpuSustainedHigh 重置计时器、swapUsageSpike 每小时一次等）
- [x] Top Process 关联：在 recordEvent 时从 MonitorStore 的 topProcess 列表获取（尽力而为）

## 5. 事件查询
- [x] 在 `StatisticsAggregator` 中新增 `queryEvents(range:severity:)` 方法
- [x] 返回 `[SystemEvent]`，按时间倒序排列
- [x] 支持 severity 过滤

## 6. StatisticsView 时间线 UI（液态玻璃）
- [x] 实现 `EventTimelineSection`（标题 + 当前范围事件计数 + 事件列表），跟随 mac-health-score 引入的全局 range，无独立选择器
- [x] 实现 `EventTimelineDay`（24h 按"今天/昨天"分组，7d/30d/1年按日期分组）
- [x] 实现 `EventTimelineRow`（时间 + 严重度图标 + 标题 + 详情 + Top Process），图标用 SF Symbol
- [x] 时间线竖线 + 节点用 SwiftUI `Canvas`/`Path` 绘制，节点颜色按严重度
- [x] 整块用 `GlassEffectContainer` + `.glassEffect()` 液态玻璃包裹，与设置页玻璃质感一致
- [x] 在 `StatisticsView` VStack 中将 `EventTimelineSection` 插入 summaryGrid 之后、errorBanner 之前
- [x] "显示更多"按钮分页加载更早的事件

## 7. HTML Report 时间线
- [x] 在 `StatisticsReportPayload` 中新增 `events` 字段
- [x] 在 HTML 中新增时间线区域（竖线 + 节点样式）
- [x] 每个节点显示时间、事件类型、详情
- [x] 严重度用颜色区分（红/黄/灰）

## 8. 本地化
- [x] 在 `Localizable.xcstrings` 中添加所有 `event.*` key（zh-Hans + en + ja）

## 9. 验证
- [x] Build 通过
- [x] StatisticsTests 通过（注：HagimiMonitorTests/computeLoadIncludesMemoryPressure 为预先存在的失败，与本次改动无关）
- [ ] 手动验证：运行 app 后模拟高负载，确认事件被记录
- [ ] 手动验证：StatisticsView 显示事件时间线
- [ ] 手动验证：HTML Report 包含事件时间线
- [ ] 手动验证：事件去重正常（不会每秒产生重复事件）
- [ ] 手动验证：面板不可见时事件仍被记录（Top Process 为 nil 但事件不丢失）
