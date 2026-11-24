# Tasks

## 1. P0 后台采集与维护修复

- [x] 1.1 在 `StatisticsRecorder.recordProcesses` 中分离 `lastFastProcessSampleAt` 与 `lastNetworkProcessSampleAt` 游标并在唤醒/暂停时同时重置，配合 `MonitorStore.sampleProcessesForStatistics` 扩大内存 Top 数量至 12 并传入显式 `providedMetrics`；通过 `ProcessSampleIntervalTests.interleavedFastAndNetworkPipelinesKeepIndependentCursorsAndMetrics()` 验证网络总量按真实 ~60s 积分且不中断或虚推 CPU 事件。
- [x] 1.2 在 `StatisticsRecorder.rangeMetricRows` 中为 `week` / `month` 在已完成小时桶后追加当前小时分钟聚合桶并统一驱动 `refreshOverview` 与 `rangeSeries`；通过 `StatisticsRecorderTests.weekRangeIncludesCurrentHourMinutesWithoutFalseInterrupted()` 验证整点后周视图包含当前小时桶且维持 `.ongoing`。
- [x] 1.3 增加 `StatisticsRecorder.setOverviewObservationActive(_:)` 门控并在 `StatisticsSettingsView.onAppear/onDisappear` 绑定生命周期，保持构造与 `resume()` 首次刷新，避免设置窗口默认页或后台无展示时每分钟重算概览；通过 `StatisticsStorageLifecycleTests` 与双渠道完整运行验证。
- [x] 1.4 为 `StatisticsProcessStore` 增加 `lastRecordedUsageDay` 内存打卡去重、启动/`resume`/跨日时的 60 天 `StatsAppEvent` 自动清理，并在 `AppDelegate` `willTerminateNotification` 通过 `StatisticsRecorder.flushForTermination()`（依赖 `existingProcessStore` 不触发空库新建）同步冲刷退出前数据；通过 `StatisticsProcessStoreMemoryTests`、`StatisticsStorageLifecycleTests` 与构建测试验证。
- [x] 1.5 在 `ReportDataAggregator` 构建告警分组时对历史事件 `appKey` 套用别名映射，并在 `ProcessAlertCenter.resolveAppKey` 中优先解析稳定身份键；通过 `ReportDataAggregator` 报表测试与 `TargetedRecheckTests` 验证兼容性。

## 2. P1 警报模型、门槛、冷却与白名单

- [x] 2.1 更新 `StatisticsMetricDefinition.attentionThreshold(for: .cpu, logicalCoreCount:)` 为 `max(100, 核数 × 15%)`（未知/0 核回退 100），同步更新 `AppAlertNotificationPolicy.tier` 及受影响测试；通过 `StatisticsMetricDefinitionTests`、全量 `ProcessAlertCenterDurationTests` / `TargetedRecheckTests` / `EpisodeClippingTests` / `BaselineRegressionProbeTests` 验证。
- [x] 2.2 收紧 `SystemPressureSnapshot.hasElevatedPressure`（`thermalLevel >= 2` 才放行，排除 `fair(1)`），并将 `PressureAlertCenter` 与 `ProcessAlertCenter` 改为订阅 `MonitorStore.allModulesPublisher`；通过 `ProcessAlertNotificationGateTests.fairThermalDoesNotCountAsElevatedSystemPressure()` 验证。
- [x] 2.3 为 `PressureAlertStateMachine`（含 `reset(_ kind:)`）与 `ProcessAlertCenter` 增加 15 分钟跨事件冷却与同事件升级例外（投递失败回滚冷却）；通过 `PressureAlertStateMachineTests`（3 项冷却/隔离用例）及 `ProcessAlertNotificationGateTests.crossEpisodeNotificationCooldownSuppressesImmediateRepeatAlert()` 验证。
- [x] 2.4 在 `MonitorSettings` 新增 `alertMemoryPressureEnabled`、`alertThermalPressureEnabled`、`alertHighLoadAppEnabled` 及 `alertIgnoredApps`（`AlertIgnoredApp`），在 `AlertNotificationDelegate` 暴露实时通知授权状态并在应用激活及页面进入时刷新；通过 `SettingsTests` 与 `ProcessAlertNotificationGateTests` 验证开关持久化、分项静音与白名单过滤。

## 3. P2 前端 UI 重构、子页与本地化

- [x] 3.1 在 `StatisticsOverviewModel` 新增 `CoverageSummary`（`coverageSummary(for:row:now:calendar:)`）、纯客观原生档位分布模型 `DimensionStatus`（`dimensionStatus(for:row:events:)`：折叠 `fair(1)`、计算各档位精确占比 `Slice` 及异常降序排序）与 `WorkloadSummary`（`workloadSummary(for:row:)`：计算 CPU/GPU 常规与高负载占比）；通过 `StatisticsOverviewModelTests` 单测验证。
- [x] 3.2 重构 `StatisticsSettingsView` 为四层结构（控制卡含记录天数与警报状态行 → 条件式单行 `ActiveHighLoadBanner` → 「统计概览」主卡含范围+时钟完整度悬浮按钮 `CoverageClockButton`、并排「内存压力｜热压力」环形占比双格 `PressureDonutRing` + `PressureStatusCell` 与共享防抖 `HoverPopoverController` 驱动的 `PressureBreakdownPopover`、自然语序 2×3 均值格、首行占比优先 `WorkloadMetricCell` + `WorkloadBreakdownPopover` 与平权双向网络/磁盘格 → 存储管理入口），并支持单一应用一键「忽略」与「查看」跳转报表。
- [x] 3.3 新增 `AlertSettingsView` 子页并在 `SettingsSidebar` / `SettingsRootView` 接入 `.alerts` 路由高亮维持（同时展示系统通知拒权引导与系统设置跳转、三项开关与正在运行/应用选择器白名单管理）。
- [x] 3.4 在 `Localizable.xcstrings` 补齐中英双语文案（含时钟完整度浮层 `stats.coverage.*`、精简版压力明细浮层 `stats.pressure.*` 与 CPU/GPU 工作负载明细浮层 `stats.workload.*`），保持原有 JSON 结构与顺序。

## 4. 集成构建、全量测试与人工目测

- [x] 4.1 运行 App Store (`HagimiMonitor`) 与直连版 (`HagimiMonitorDirect`) 双渠道 Debug 构建（各自独立 DerivedData `tmp/dd-appstore` 与 `tmp/dd-direct`）。
- [x] 4.2 运行 `HagimiMonitorDirect` 完整测试套件（`xcodebuild test`）。
- [x] 4.3 完成并严格校验 OpenSpec 变更 `redesign-statistics-settings-and-alerts`（`openspec validate "redesign-statistics-settings-and-alerts" --strict`）。
- [x] 4.4 实机启动最新构建的 `HagimiMonitorDirect.app` 与 `HagimiMonitor.app`，由用户在设置 →「数据统计」与「异常警报」子页目测明暗外观、配色方案及交互布局并确认验收。
