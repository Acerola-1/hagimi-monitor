# Proposal

## Why

设置页「数据统计」此前同时堆叠历史均值、压力警告/严重嵌套时长与无边界的「应用观测」明细，导致长周期下正常轻载应用与历史偶发严重压力在视觉上反客为主、缺少清晰重心。同时，后端存在进程快速/网络游标互相覆盖、周/月序列缺少当前小时分钟桶、事件键与报表别名不一致、CPU 固定 60% 门槛在多核芯片下误报偏高及后台无条件重算概览等问题。

## What Changes

- 重构设置页「数据统计」信息架构：控制卡片（含已记录天数与异常警报入口）→ 条件式独立单行实时高占用提示条（支持单应用一键忽略与跳转报表）→ 作为唯一视觉重心的「统计概览」卡片（时段切换与右侧时钟完整度悬浮图标、并排「内存压力｜热压力」环形占比图 + 原术语占比展示与悬浮详情弹窗、自然语序的等分 2×3 指标宫格与对等双向网络/磁盘展示）→ 存储管理入口。
- 新增独立「异常警报」设置子页：系统通知总开关（含系统拒权诊断与一键跳转系统设置）、内存严重压力 / 系统过热 / 应用长期高负载三项分项开关、以及通过正在运行列表或 `.app` 选择器维护的「忽略的应用」白名单。
- 治理警报判定与降噪规则：CPU 关注门槛按逻辑核数自适应（`max(100%, 核数 × 15%)`）；热压力 `fair(1)` 不再作为高占用通知放行依据；压力与进程告警改为订阅未过滤全量模块快照；两路告警均引入 15 分钟跨事件冷却（同事件升级不阻断）。
- 修复后端采样与存储维护缺陷：拆离快样本与网络进程游标并传入显式 `providedMetrics`；扩大进程内存采样上限；`week`/`month` 时间序列在已完成小时桶后拼接当前小时分钟聚合；限制概览重算仅在设置统计页可见时随分钟封口触发；增加当日打卡内存去重、60 天确认事件清理、退出前落盘及报表别名归一化。

## Capabilities

### New Capabilities

- `statistics-alert-governance`: 统一度量门槛、系统压力伴随放行、跨事件冷却、分项开关与忽略应用白名单等异常警报判定与降噪契约。

### Modified Capabilities

- `settings-window`: 更新设置侧栏统计域子路由高亮（新增 `.alerts`），以及「数据统计」主页布局、实时高占用提示条与「异常警报」设置子页行为。
- `statistics-background-maintenance`: 新增分离式进程采样游标、周/月当前小时拼接、可见门控概览刷新、打卡内存去重、60 天事件保留清理与退出前冲刷要求。

## Impact

- UI 与本地化：`SettingsSidebar`、`SettingsRootView`、`StatisticsSettingsView`、`StatisticsApplicationObservationRow`、新增 `AlertSettingsView` 与 `Localizable.xcstrings`；`StatisticsOverviewModel` 新增 `PressurePresentation`。
- 采样、告警与存储：`MonitorModels`、`MonitorSettings`、`StatisticsMetricDefinition`、`AppAlertNotificationPolicy`、`PressureAlertStateMachine`、`PressureAlertCenter`、`ProcessAlertCenter`、`StatisticsRecorder`、`StatisticsProcessStore`、`ReportDataAggregator`、`AlertNotificationDelegate`、`AppDelegate`。
- 验证：`HagimiMonitor`（App Store）与 `HagimiMonitorDirect`（直连）双渠道构建及 `HagimiMonitorTests` 单测套件。

## Non-goals

- 不改动独立原生报表窗口与 HTML 导出报表的整体版式与图表交互。
- 不开放 SMC 风扇转速控制或每个应用的自定义阈值滑块。
- 不在未获明确指令时自动提交或推送 git 变更。
