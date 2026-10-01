# 数据统计体验与口径统一

## Why

设置中的高负载应用卡片把结论、均值、峰值、时间和档位分布同时展开，普通用户难以判断应该关注什么；当前还存在内存标签错误、网络速率放大、时长按次数计算及事件范围失真。用户于 2026-10-01 已采纳本轮全部优化建议，本变更将可信的数据口径、清晰的设置摘要和能追溯的完整报表作为同一条产品链路改进。

## What Changes

- 统一指标定义、百分比基准、容量/流量单位、档位、阈值与格式化；网络速率与区间总量分离，修复卡片、通知和导出中的错误单位。
- 应用高占用事件采用有效观测驱动的纯状态机，按真实区间累计；区分连续、累计、跨度，明确恢复、中断、退出、缺失与休眠，禁止未知被判为恢复。
- 引入稳定应用身份、事件持久化和可查询的应用时间桶，处理旧库兼容、区间裁剪、重启与存储管理联动；排行标明前列采样的局限和估算性质。
- 设置页改为一句结论、紧凑应用行和按需展开；当前占用与历史范围分开，默认不展示多段分布条，真实系统压力与正常高占用采用不同语气。
- 打开报表携带时间范围、应用、指标及事件上下文；提供完整应用/事件详情、可排序的完整应用榜，补齐摘要到详情的闭环。
- 总览先呈现结论，解释压力评分的边界，减少默认曲线数量，明确历史快照/当前读数；设置、报表、通知、HTML/PDF 对齐语义。
- 统计首屏与硬件资料分阶段发布，保护现有缓存、后台门控、关闭清理和高频交互；以实机性能证据决定优化，不用编译成功替代验收。
- 正式页面移除修改共享真实告警状态的演练入口；示例使用隔离预览数据源。

这会有意改变旧的错误展示和部分预设范围语义；存量数据不得清空、伪造回填或冒充新口径。无最低系统版本、远端服务或权限范围的扩大。

## Capabilities

### New Capabilities

- `statistics-metric-contract`: 指标单位、分母、容量相关关注门槛、时间范围与跨表面格式化契约。
- `application-resource-events`: 稳定应用身份、有效采样、时间加权累计、事件状态机、持久化、保留与旧数据兼容。
- `statistics-report-experience`: 原生报表的上下文跳转、应用/事件详情、可比较排行、总览结论及分阶段加载。

### Modified Capabilities

- `settings-window`: 增加数据统计摘要的信息层级、紧凑高占用行、当前/历史边界及示例隔离。
- `report-data-accuracy`: 统一自然日预设和右开区间，明确部分日、事件裁剪、真实时长与前列样本口径。
- `statistics-background-maintenance`: 增加应用时间桶和事件的有界维护、持久化/迁移及删除联动要求。
- `html-report-export`: 增加选定范围、单位、事件与来源质量在原生、HTML 和打印中的一致性。

## Impact

- 核心链路：`MonitorModels.swift` 的统计采样；`StatisticsRecorder.swift`；`StatisticsProcessStore.swift`；`ProcessAlertCenter.swift`；系统指标的 `StatisticsDatabase.swift` 与既有压力状态机作为可复用参考。
- 展示：`StatisticsSettingsView.swift`、`StatisticsOverviewModel.swift`、`StatisticsDisplayFormat.swift`、`Views/Report/`、`ReportWindowPresenter.swift` 和 `StandaloneHTMLReportExporter.swift`。
- 数据：应用库增加带版本的身份/时间桶/事件存储；系统指标库结构是否扩展由详细迁移设计决定。旧日汇总保留，不能逆推不存在的分钟数据。
- 内容与验收：`Localizable.xcstrings`、统计/报表/迁移/事件测试、原生操作截图和性能记录、HTML/PDF 样本及维护文档。
- 渠道：共享能力验证 App Store 与 Direct；网络/磁盘等受限来源遵循现有编译与沙盒边界，不把不支持的指标补零。
- 与已有变更：`native-statistics-report` 已列为任务完成但未归档；本变更接续其当前原生架构，不重开、改写或代为归档它，也不牵连其他活动 change。

详见 [design.md](design.md)、[tasks.md](tasks.md) 和 [交接背景](reference/handoff.md)。本轮只完成计划，所有实施任务保持未勾选。
