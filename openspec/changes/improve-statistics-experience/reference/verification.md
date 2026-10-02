# 实施验证与接手续记

## 当前状态

上一轮会话在额度耗尽前已开始实施，范围集中在设置页前端。代码改动真实存在、两渠道构建通过、相关测试通过，但当时未回写本文件；下面记录的是事后核实结果，不是当时的即时记录。

- 2026-10-01（规划）：OpenSpec计划完成。`openspec status`确认4/4规划产物齐全，`openspec validate --strict`通过。
- 2026-10-01（实施）：用户改为要求开始实施并优先做前端。已切分支 `codex/statistics-settings-hierarchy`（基于 `dev`，`1f3dbe7b`），改动仍**未提交**，全部留在工作区。
- 已勾选任务：1.1–1.4、2.1–2.6、3.1–3.3、3.5、4.1–4.7、5.1–5.7、6.1–6.6、7.1–7.5、7.7、8.1、8.2、8.3、8.5、8.7、9.1–9.6、10.1–10.5、11.1–11.3、11.5–11.7（共 62/68）。
- 8.4 的界面、单行展开与指标深链已实现，但键盘（Space/Tab）展开未实机验证，保持未完成。
- 7.4 的列表/搜索/排序已实现并测试；键盘逐行导航与列宽实测未做，勾选依据是过滤逻辑测试与实机截图。
- 8.1/8.6/8.7 只有视觉截图，VoiceOver、键盘与相邻设置页并排核对未做，保持未完成。
- 本轮改动仍全部未提交。
- 未提交、未发布、未归档；`native-statistics-report` 保持原状。

### 实施范围（工作区未提交改动）

- `HagimiMonitor/Views/Settings/StatisticsSettingsView.swift`：由约530行改为重排后的摘要结构，删除旧的应用卡片、档位条与演练注入。
- `HagimiMonitor/Views/Settings/StatisticsApplicationObservationRow.swift`（新增）：单行 disclosure + 独立展开状态 + 图标加载。
- `HagimiMonitorTests/StatisticsApplicationObservationTests.swift`（新增）：网络速率/单位/预览隔离 4 项测试。
- `HagimiMonitor/Statistics/StatisticsDisplayFormat.swift`：新增 `applicationObservationValue`，区分容量 GiB/MiB 与速率 MB/s。
- `HagimiMonitor/Statistics/StatisticsRecorder.swift`：告警消费 B/s，应用库继续消费区间总量；新增可注入 `processAlertCenter` 与 `processStoreDirectory` 以便隔离测试。
- `HagimiMonitor/Statistics/ProcessAlertCenter.swift`：删除 `HAGIMI_ALERT_FIXTURE` 自动注入与 `simulateWindowServerDemo()`，通知改用统一格式化。
- `HagimiMonitor/Localizable.xcstrings`：新增 6 个 `stats.apps.*` / `stats.summary.period-caption` 键（相对本变更）。
- `DESIGN.md`：新增 “Statistics Settings” 段，记录材质、层级、两行上限、展开语义与颜色职责。
- `HagimiMonitor/QuickToolsStore.swift`：`不息屏`→`防熄屏` 用词统一，属既有未提交改动，**不属于本变更**。

### 已执行的验证

- 构建：App Store 与 Direct 两渠道 `BUILD SUCCEEDED`（日志 `tmp/statistics-settings-ui/build-appstore.log`、`build-direct.log`）。
- 测试：5 个suite、45 项用例 `TEST SUCCEEDED`（`tmp/statistics-settings-ui/tests.log`），含新增 `StatisticsApplicationObservationTests`、`StatisticsDisplayTimerTests`、`StatisticsOverviewModelTests`、`ReportCorrectnessTests`、`ReportDataAggregatorTests`。
- 原生实机：设置页在浅色中文、深色英文长名、暂停但仍可切换历史范围、应用行展开、完整报表入口五种状态下截图并操作（`tmp/statistics-settings-ui/*.png`）；真实数据的 Direct 与 App Store 开发版各看一次（`settings-direct-real.png`、`settings-appstore-real.png`）。
- 夹具路径：`HAGIMI_STATS_APPLICATION_FIXTURE`（`empty`/默认 2 应用/`long`），仅 DEBUG 编译，不写共享告警或统计库。

## 2026-10-01 第二段实施（指标合同 / 范围 / 深链）

用户要求按 tasks 与验收标准继续推进，本轮完成第 2 组共享指标合同、6.1 自然日范围与 7.1 打开上下文。

### 改动

- `Statistics/StatisticsMetricDefinition.swift`（新增）：指标定义唯一来源——原始单位、百分比基准、档位边界、关注门槛与契约版本。内存档位是真实 1/2/4 GiB，最高段为 4 GiB+；网络档位以 MiB/s 原始边界定义、标签换算十进制；内存关注门槛为 max(3.5 GiB, 物理容量 × 20%)，容量未知时退回绝对门槛并标记不可计算份额；CPU 基准为单逻辑核、不截断 >100%；GPU 基准标记为来源分母不可解释。
- `Statistics/ProcessAlertCenter.swift`：CPU/GPU/内存/网络的门槛与档位全部改读共享定义，删除调用点各自硬编码的阈值；内存原值由 MiB 改为原始字节。
- `Statistics/StatisticsProcessStore.swift`：应用日聚合的档位边界同样改读共享定义。
- `Statistics/StatisticsDisplayFormat.swift`：拆出 `decimalVolume`（十进制 GB/TB）、`decimalRate`（MB/s、GB/s）与 `binaryCapacity`（GiB/MiB），删除原来同时承担两套除数的 `bytes`。
- `Views/Report/ReportUIHelper.swift`：`formatBytesRate`/`formatBytes` 改指向共享格式化，新增 `formatVolume`；磁盘与网络总量改用十进制总量，内存/显存保留二进制容量。
- `Views/Settings/StatisticsSettingsView.swift`：摘要的网络/磁盘总量改用十进制总量，与报表同除数。
- `Views/Report/ReportModels.swift`：`ReportTimeRange` 的 7/30/365 日改为本地自然日（含今天向前 6/29/364 天），替换原来的滚动固定秒数；自定义范围保持右开端点。
- `Statistics/StatisticsRecorder.swift`：`StatisticsOverviewRange.reportTimeRange` 建立设置与报表的范围映射。
- `Statistics/StandaloneHTMLReportExporter.swift`：新增 `StatisticsReportContext`（range/anchor/appKey/metric/eventID），`StatisticsReportFlow.open` 保留旧签名重载。
- `ReportWindowPresenter.swift`、`Views/Report/NativeReportViewModel.swift`：新增 `apply(context)` 提交范围、模块与应用/指标焦点后再加载，保证标题与数据同批对应；`reloadCurrentReport` 改为保留范围与深链目标的刷新。
- `Views/Report/ReportAppsView.swift`：按深链指标选中对应排行分类，目标应用不在默认前八项时前置显示；目标事件已被删除时显示明确说明。
- `Views/Settings/StatisticsApplicationObservationRow.swift`：主指标改为「超出门槛的相对程度」最高者（跨量纲只比 value/threshold），新增「查看应用详情」入口，回调携带应用与指标。
- `AppDelegate.swift`：报表夹具扩展 `HAGIMI_REPORT_APP` 与 `HAGIMI_REPORT_METRIC`，用于验证深链。
- `Localizable.xcstrings`：新增 `stats.apps.open-detail`、`stats.report.record-missing`，并恢复本轮误删的 12 个 `stats.apps.*` / `stats.summary.period-caption` 键（见下方事故记录）。
- `Resources/ReportTemplate.html`：应用告警的格式化不再假设内存是 MiB、也不再让网络落到百分比分支。新增 `formatCapacity`（二进制 GiB/MiB）、`formatRateDecimal`（十进制 MB/s）与 `formatApplicationUsage`，与 Swift 侧共享同一单位合同。这是 10.2 的部分工作：单位已同源，范围/有效时长/质量语义尚未接入。

### 验证

- 构建：Direct 与 App Store 两渠道 `BUILD SUCCEEDED`。
- 测试：105 项用例 `TEST SUCCEEDED`（`tmp/statistics-metric/tests-final.log`），新增 `StatisticsMetricDefinitionTests`（17 项）与 `ReportTimeRangeTests`（11 项）、`StatisticsReportContextTests`（5 项）。
- 覆盖的验收场景：M01 内存 5.8 GiB 落 4 GiB+ 段且四表面同源；M02 网络 1 MiB/s 不触发门槛、25 MiB/s 保留原始字节值与十进制标签；M03 同一 156,000,000,000 字节在总量与容量两种语义下分别显示 156 GB / 145 GiB；M04 CPU 240% 不截断、GPU 基准标记为不可解释、8/16/32/64 GiB 与未知容量的门槛分支；R01 设置与报表给出同一自然日起点；R02 今日/跨月/跨年/夏令时/右开边界；U01 上下文携带范围、应用与指标并提交到视图模型。
- HTML 侧：`formatApplicationUsage` 的 Node 校验覆盖 5.8 GiB 内存、512 MiB、25 MiB/s、1 MiB/s、240% CPU 与 46% GPU，六个用例与 Swift 输出逐字一致（`tmp/statistics-metric/fmtcheck.js`）。模板内 4 段脚本通过 `node --check`。
- 原生实机：设置页在夹具下渲染正常，Safari 行主指标按相对门槛选为 CPU 74.5% 而非内存（截图 `tmp/statistics-metric/evidence/settings-fixture.png`）；报表夹具以「近 7 天 + 应用排行」打开（`report-apps-week.png`）；深链夹具 `HAGIMI_REPORT_APP=sysmond HAGIMI_REPORT_METRIC=gpu` 打开后落在应用排行的 GPU 分类（`report-deeplink-gpu.png`）。

### 事故与修复记录

本轮为新增本地化键时曾用 `json.dumps` 整份重写 `Localizable.xcstrings`，触发 AGENTS.md 明确禁止的 catalog 整体重排；随后用 `git checkout` 还原时又误删了上一段会话尚未提交的 12 个新键。已从当时构建产物中的 `Localizable.strings` 逐一比对取回原值并按精确文本插入恢复，校验结果：catalog 1369 键、无重复键、diff 中 0 行删除，12 个键的中英文与构建产物完全一致。后续编辑该 catalog 必须继续定点插入。

### 尚未验证

- 8.4 键盘展开；8.1/8.6/8.7 的 VoiceOver、键盘与相邻设置页对照。
- 第 3、5 组（应用身份、有效采样、持久化迁移）与第 9 组未实施；第 10 组只做了单位同源，范围/质量语义与 golden 逐字段对照未做。
- 10.2 未勾选：HTML 与原生尚未做同源 golden 的逐字段对照与范围切换验证。
- 报表应用排行仍是前八项截断加目标前置的临时方案，完整可排序列表属于 7.4。

## 2026-10-01 第三段实施（范围边界 / 完整排行 / 质量标注 / 总览结论 / 分阶段加载）

### 改动

- `Statistics/StatisticsDataQuality.swift`（新增）：质量 OptionSet（observed / partialCoverage / legacyDailyEstimate / leadingSampleEstimate / noObservation / sourceUnsupported）与 `StatisticsMetricResult`（值 + 质量 + 覆盖秒数 + 粒度 + 契约版本 + 更新时间）。缺失、真实零、估算、不支持四态可区分。
- `Statistics/StatisticsProcessStore.swift`：新增 `DayRange` 与 `dayRange(from:to:calendar:)`，把查询区间转成右开日键范围；`dailyRows` 从 `day <= toDay` 改为 `day < toDay`。此前「到 10 月 1 日零点结束」的查询会把 10 月 1 日整天算进应用排行。
- `Views/Report/ReportDataAggregator.swift`：应用日行与电池历史改用 `DayRange` 过滤；新增 `dataQuality(rows:coverageRatio:granularity:appsEstimateLeadingSample:)`；`ReportActiveRangeModel` 携带 quality / coveredSeconds / updatedAt 与 `qualityNotice`；移除 `makeList` 的 25 条截断并补充 `getPeak`。
- `Views/Report/ReportAppRankingFilter.swift`（新增）：排行筛选与排序抽成纯函数（系统过滤 + 搜索 + 按占用/峰值/名称排序 + 折叠上限 + 深链目标保底），供测试直接验证。
- `Views/Report/ReportAppsView.swift`：新增搜索框、清除、排序选择器与「显示全部 N 个应用」；搜索/排序/展开状态移入视图模型，刷新与模块切换后保留。
- `Views/Report/ReportPeriodConclusion.swift`（新增）：时段结论纯函数，区分「无观测 / 观测不足 / 平稳 / 出现压力」，高占用应用只作补充且不改变语气。
- `Views/Report/ReportOverviewView.swift`：结论卡前置（并声明只描述系统压力、不代表硬件健康）；标题区显示快照时刻；质量说明可见；趋势新增「负载 / 内存」模式切换，默认只画 CPU/GPU 两条。
- `Views/Report/NativeReportViewModel.swift`：加载拆成两阶段，统计先以 `hardware: nil` 发布，硬件清单随后独立补充并重新聚合；新增 `isHardwareLoading`；排行搜索/排序/展开状态与 `focusedEventIsMissing` 归位。
- `Views/Report/ReportMachineView.swift`：硬件区区分「正在采集」与「读不到」，不再把加载中伪装成不存在。
- `Views/Report/ReportMachineView.swift`、`ReportModels.swift`、`ReportAppsView.swift`、`Localizable.xcstrings`：相关文案与键（`stats.quality.*`、`stats.report.conclusion.*`、`stats.report.sort.*`、`stats.report.search.*`、`stats.r.loadingHardware`、`stats.report.snapshotAt`、`stats.report.trend.*`）。
- `stats.r.prefixFullLoad`：由「满载 / Full load」改为「高负载 80%+ / High 80%+」，符合「80% 档位不得称为整机满载」的要求。

### 验证

- 全量测试：628 项通过，`tmp/statistics-metric/tests-all.log`（`TEST SUCCEEDED`）。
- 本轮新增 5 个测试文件：`StatisticsDayRangeTests`（R03 右开边界，含跨夏令时）、`StatisticsDataQualityTests`（质量四态 + 聚合层判定）、`ReportAppRankingFilterTests`（U04：>25 应用全可访问、搜索、清除、系统过滤、三种排序）、`ReportPeriodConclusionTests`（U09：高占用+低压力不误报、压力分级、观测不足）、`StatisticsSnapshotSemanticsTests`（P02：快照时刻、无观测不补零、部分覆盖标记）。
- 原生实机：报表应用排行显示搜索框、「按占用」排序与「显示全部 427 个应用」，确认数据层不再截断（`tmp/statistics-metric/evidence/report-apps-full.png`）；总览首屏以「这段时间出现过系统压力 · 内存压力 共 12 段 · 本期存在覆盖缺口」开头，右上角「快照于 2026 年 10 月 1 日 22:15」，趋势默认只显示 CPU/GPU 并带负载/内存切换（`report-overview3.png`）。

### 本轮踩到的坑

- `StatisticsDataQualityTests` 初版用 `columns.firstIndex { $0.name == "coverS" }` 强解包，实际列名是 `cover_s`，导致测试宿主在 bootstrap 阶段 SIGTRAP 崩溃，表现为「Early unexpected exit」。已改用真实列名；后续写行夹具务必核对 `StatisticsRow.columns` 的列名拼写。
- 无 GUI 会话下 AppleScript 点击与 `cliclick` 都不可用；本机编译的小工具 `tmp/statistics-metric/click`（CGEvent）在前台应用上也未生效，故窗口内点击改为依赖夹具启动参数而非模拟点击。

### 尚未验证

- 8.1 / 8.4 / 8.6 / 8.7 的键盘、VoiceOver 与相邻设置页对照。
- 第 3 组（稳定应用身份、有效采样区间）与第 5 组（V2 schema、迁移、保留、删除联动）未实施；这是事件状态机与历史可信度的前置。
- 第 4 组（纯事件状态机、通知政策）未实施。
- 第 10 组只完成单位同源；HTML 与原生逐字段 golden 对照、打印范围上下文未做。
- 7.2 / 7.3 / 7.6 / 7.7（应用与事件详情、本地化与辅助功能、UI contract 文档）未实施。

## 2026-10-01 第四段实施（事件状态机）

### 改动

- `Statistics/AppResourceEventStateMachine.swift`（新增）：纯事件状态机。以有效覆盖区间累计，不再按采样次数加分钟；持续资格 120 秒、瞬时证据最大间隔 90 秒；首个瞬时样本不产生覆盖秒数；恢复必须由可靠低占用确认；提供 `unionSeconds` 计算多指标并集；时间由调用方注入。
- `Statistics/ProcessAlertCenter.swift`：删除按次数累加的 `updateEpisode` 与「150 秒无输入即恢复」的逻辑，改为按指标分批调用状态机；空批次不再被当作其他维度恢复；新增 `interruptAll(reason:at:)` 供睡眠/关闭/重启使用。`ProcessAlertEpisode` 以 `continuousHighSeconds` / `eventSpanSeconds` / `observationCount` 取代按次数推导的时长，`durationMinutes` 变为由真实秒数推导的展示属性；新增 `EndReason` 与 `state`（`interrupted` 用于非恢复结束）。
- `Statistics/StatisticsRecorder.swift`：`willSleep` 时以 `suspended` 中断进行中事件；关闭记录同理。
- `Views/Report/ReportModels.swift`、`ReportDataAggregator.swift`：`ReportHighLoadAppGroup.maxDurationSeconds` 取代按次数推导的分钟字段。
- `Views/Settings/StatisticsApplicationObservationRow.swift`：展开详情分别显示「高占用 X」与「N 次高占用观测」，并显示恢复/中断状态与结束原因；说明文案改为「时长按有效的高占用覆盖累计；观测次数单独列出，未观测时段不计入」。
- `Resources/ReportTemplate.html`：新增 `formatDuration`，应用告警使用 `durationSeconds`（有效秒数）而非采样次数；不足一分钟显示「不足 1 分钟」。
- `docs/development/statistics-app-events.md`（新增）：记录三种时间的区别、持续资格与最大间隔、结束原因表、分批与多指标合并规则、门槛归属与验证方式。
- 本地化：新增 `stats.apps.high-duration %@`、`stats.apps.state.*`、`stats.apps.reason.*`、`stats.apps.observation-limit-v2`；`stats.apps.samples %lld` 改为「N 次高占用观测」；移除已被取代的 `stats.apps.observation-limit`。

### 验证

- 全量测试 650 项通过（`tmp/statistics-metric/tests-full4.log`），两渠道构建成功。
- 新增 `AppResourceEventStateMachineTests`（17 项）：E01 首个瞬时样本不记一分钟、两次观测只累计 60 秒、三次达 120 秒资格；E02 有效低值确认恢复且结束端点停在最后有效高覆盖、未确认尖峰不记为事件；E03 重叠区间并集不为 240；E04 59 分钟缺口中断且不补时长、新样本建立新基线；E05 未知不宣告恢复、超间隔记为中断；E06 进程退出/挂起/PID 复用各自结束原因；显式覆盖区间优先于间隔估算。
- 新增 `ProcessAlertCenterDurationTests`（7 项）在告警中心集成面验证：两拍不成两分钟、真实秒数与次数分开、可靠低值确认恢复、未入榜不恢复且超时记为中断、挂起中断、只有网络批次时 CPU 事件不恢复、多指标各自独立追踪。
- 修正了一个既有测试：`highNetworkRateRetainsItsRateAndFormatsAsBytesPerSecond` 原用两次采样期望事件存在，在新语义下只累计 60 秒未达资格；已改为三次采样并补上对真实秒数与观测次数的断言。
- 原生实机：设置页在夹具下渲染正常，主指标按相对门槛选择（`tmp/statistics-metric/evidence/settings-final-fixture.png`）。

### 本轮踩到的坑

- `AppResourceEventStateMachine.accumulate` 初版漏写 `lastHighAt` 的推进（写成了对自身的 max），导致每次间隔都被算成从事件起点开始，正常的一分钟采样被判为中断。修复后 7 项测试转绿。同一轮里 `State` 的 `private(set)` 也阻止了同类型静态方法写入，已改为普通 `var`。

### 尚未验证

- 4.4 未勾选：`ProcessAlertCenter` 已收敛为状态发布 + 副作用，但「接入实际系统压力有效证据」尚未实现，普通高占用与同期压力在应用详情中的并列表述也未完成。
- 4.5 未勾选：通知的系统压力门控、严重度升级与失败后有界重试尚未实现；当前只在达到持续资格时按应用/指标发一次通知。
- 第 3 组（稳定应用身份、有效采样区间）与第 5 组（持久化、迁移、保留）仍未实施，因此事件目前只在内存中，重启后无法查询历史。
- 8.1 / 8.4 / 8.6 / 8.7 的键盘与辅助功能对照未做。
- 第 10 组只完成单位与时长语义同源；逐字段 golden 对照未做。

## 2026-10-01 第五段实施（通知政策 / 稳定身份 / 真实区间）

### 改动

- `Statistics/AppAlertNotificationPolicy.swift`（新增）：通知决策纯函数（总开关 → 持续资格 → 同期系统压力 → 升级判断）与 `SystemPressureSnapshot`（含 `hasValidObservation`，未知压力不当作正常）。
- `Statistics/AppAlertNotificationSender.swift`（新增）：发送器协议、系统实现与带界重试的 `AppAlertNotificationDispatcher`。只有真正送达才 `shouldMarkNotified=true`，失败不虚记成功；默认最多 3 次。
- `Statistics/ProcessAlertCenter.swift`：通知改为「策略 + 发送器」；订阅 `MonitorStore.$modules` 提取同期压力，与 `PressureAlertCenter` 共用同一份档位证据；发送失败时撤回档位记录以便日后重试；新增可注入 `notificationDispatcher`。
- `Statistics/AppIdentity.swift`（新增）：`AppIdentity`（bundle / systemExecutable / unresolved 三类，带类别前缀的 `storageKey`）与 `AppIdentityResolver`（优先 bundle identifier，其次可执行路径，最后退回带标记的会话键）。
- `Statistics/StatisticsProcessStore.swift`：累加器与图标捕获改用稳定身份键；每帧清空 pid 缓存以处理 PID 复用；新增 `identityKeyByName` 供按名称的展示型查询，图标回读先按身份键再退回旧名称键。
- `Views/Report/ReportDataAggregator.swift`：新增 `identityAliases`，只做可证实的旧名称→身份键归并（同名对应多身份时放弃归并），避免升级后排行出现旧名与新键两行；磁盘/网络峰值字段补齐。
- `Views/Report/ReportAppsView.swift`：普通行显示去掉前缀的可读身份，完整键放 tooltip；高负载告警卡改为每条指标一行，展示均值/采样峰值/有效高占用时长与恢复或中断原因，并声明时间重叠不代表因果。
- `Statistics/StatisticsRecorder.swift`：网络与磁盘的区间总量改按真实采样间隔积分（`sampleInterval` 纯函数，首次采样与越界间隔返回 0），删除固定 `× 60`；磁盘字段识别为已是区间增量不再乘系数；新增批次去重门卫（乱序或重复时间戳丢弃）。

### 验证

- 全量测试 687 项通过（`tmp/statistics-metric/tests-fullA.log`），Direct 与 App Store 两渠道构建成功。
- 新增 `AppAlertNotificationPolicyTests` / `ProcessAlertNotificationGateTests`（N01–N03：无同期压力不发、未知压力不发、未达资格不发、同档不重复、升级才更新、总开关关闭一律跳过；即使通知被跳过，界面事件记录照常）。
- 新增 `AppAlertNotificationRetryTests`（首次成功、瞬时失败重试至成功、持续失败停在 3 次且 `shouldMarkNotified=false`、上限下限收敛、失败后可再次尝试、通知标识符按指标区分）。
- 新增 `AppIdentityTests`（A01：改名不拆历史、同名不同 bundle 不合并、系统进程用路径、unresolved 不跨启动、不同 PID 不共享身份、跨类别不碰撞、旧名称仅在无歧义时归并）。
- 新增 `ProcessSampleIntervalTests` / `ProcessBatchGateTests`（A02/A03/E06：首次采样不积分、60 秒排期积分 60、抖动 65 秒按真实值、睡眠级间隔不积分、时钟倒退不积分、重复批次只计一次、关闭后回调丢弃、乱序批次丢弃）。
- 原生实机：报表应用排行的身份列显示可读身份（`tmp/statistics-metric/evidence/report-apps-events.png`）。

### 尚未验证

- 3.4 未勾选：活跃关注应用的定向复查未实现；未入榜目前统一按未知处理并靠间隔中断，未做复查探针。
- 第 5 组（V2 schema、迁移、保留、删除联动）未实施。由于事件与身份仍在内存或沿用旧日汇总，重启后无法查询历史事件；身份键切换只做了读取期可证实归并，没有 schema 版本。
- 8.1 / 8.4 / 8.6 / 8.7 的键盘与辅助功能对照未做。
- 第 10 组只完成单位与时长语义同源；逐字段 golden 对照未做。

## 2026-10-01 第六段实施（事件持久化 / schema 与迁移 / 删除联动）

### 改动

- `Statistics/StatisticsProcessStore.swift`：新增 `StatsAppEvent` 实体（加表迁移）与 `PersistedAppEvent` 值类型；`persist(event:)` / `persistSynchronously(event:)` 按稳定事件 ID 幂等写入；`events(from:to:)` 按 `[from, to)` 交集查询；`interruptPersistedOngoing` 把重开时仍为 `ongoing` 的事件终结为中断，结束点取 `lastEffectiveAt`；`deleteRange` 联动删除范围内事件；新增 `dateFromDayKey` 把日键还原成时间戳边界；声明 `schemaVersion = 2`。
- `Statistics/ProcessAlertCenter.swift`：新增 `eventPersister` 钩子，只有确认事件才落库。
- `Statistics/StatisticsRecorder.swift`：启动时终结遗留的进行中事件并接线落库；报表读取窗口内的持久化事件。
- `Views/Report/ReportModels.swift` / `ReportDataAggregator.swift`：`ReportProcessData.persistedEvents`；`persistedEpisodes` 还原展示模型并跳过无法解析的脏数据；告警分组按事件 ID 合并内存告警与落库历史，避免重复。
- `docs/development/statistics-store-schema.md`（新增）：schema 版本、实体表、版本 2 的改动、加表迁移与键空间变化的读取期归并、回滚方式（停用新写入后用旧二进制打开，不静默丢弃；演练用独立副本）、未完成项。

### 验证

- 全量测试 703 项通过（`tmp/statistics-metric/tests-fullC.log`）。
- 新增 `AppEventPersistenceTests`（S03：写入读回、重复写入幂等、字段更新不重复、范围外不返回、跨边界返回、进行中事件以最后有效时刻中断、关闭重开目录后历史仍可读、落库事件还原为展示模型且脏数据被跳过）。
- 新增 `StatisticsStoreMigrationTests` / `StatisticsStoreDeletionTests`（S01/S05/S06：schema 版本声明、重复打开幂等、旧日汇总与新事件表共存、纯名称旧键仍可读、范围删除联动事件、范围外事件保留、两个目录互不影响）。

### 尚未验证

- 5.2 未勾选：稳定的 alias 映射表与「旧日汇总标为旧版估算」标签未做；目前只有读取期可证实归并，旧行没有 legacy 质量标记。
- 5.3 未勾选：应用有效细桶（任意部分分钟的区间裁剪）未实施，因此范围内均值/峰值尚未按区间重算，仍是整段事件的统计值。
- 5.5 未勾选：60 个自然日保留与后台有界维护、多实例写入协调未实施。
- 5.7 未勾选：迁移/回滚已有文档与幂等测试，但尚未做「独立旧库 → 新库 → 可恢复旧版本」的完整演练与占用测量。
- 3.4、8.1/8.4/8.6/8.7、第 10 组逐字段对照仍未完成。

## 2026-10-01 第七段实施（事件区间裁剪 / 旧版身份标注）

### 改动

- `Views/Report/ReportDataAggregator.swift`：新增 `clipEpisode(_:from:to:)`，把事件裁剪到查询区间后再统计范围外不返回、跨边界只计本期部分、事件 ID 保持不变；高负载分组改为先裁剪再过滤；`ReportAppRankings.hasLegacyNameIdentities` 标记范围内是否存在旧版按显示名存储的身份。
- `Views/Report/ReportModels.swift`：`ReportAppIdentity.hasStableIdentity` 与 `isLegacyNameOnly`；`ReportAppRankings` 增加旧版身份标记。
- `Statistics/StatisticsProcessStore.swift`：`StatsAppIdentity.identityKind` 记录身份类别，`hasStableIdentity` 判定旧名称行；`identities()` 一并返回该标记。
- `Views/Report/ReportAppsView.swift`：范围说明下方增加旧版身份提示，明确归属与精确时间属于估算。
- 本地化：新增 `stats.r.legacyIdentityNotice`。

### 验证

- 全量测试 709 项通过（`tmp/statistics-metric/tests-fullD.log`）。
- 新增 `EpisodeClippingTests`（R05/R06：范围外事件被丢弃、跨起点裁剪为本期部分且 ID 不变、范围内事件不变、跨终点裁剪、极短交集仍保留至少一次观测、边界相接零交集被拒绝）。

### 尚未验证

- 5.3 未勾选：应用有效细桶未实施；事件裁剪按整段比例折算，不是按细桶精确重算，长时间事件的部分统计仍有近似。
- 5.5 / 5.7 未勾选：保留维护与完整回滚演练。
- 3.4、8.1/8.4/8.6/8.7、第 10 组逐字段对照仍未完成。

## 2026-10-01 第八段实施（保留维护 / 导出范围上下文）

### 改动

- `Statistics/StatisticsProcessStore.swift`：`deleteBefore` 联动清理早于保留窗口的确认事件；新增 `eventRetentionDays = 60`。
- `Statistics/StandaloneHTMLReportExporter.swift`：载荷下发 `rangeBounds`（与 `ReportTimeRange` 一致的自然日边界）与 `committedRange`（用户当前提交范围）；`write` 新增 `committedRange` 参数。
- `ReportWindowPresenter.swift`：导出与打印都携带 `viewModel.committedExportRange()`。
- `Views/Report/NativeReportViewModel.swift`：新增 `committedExportRange()`。
- `Resources/ReportTemplate.html`：`RANGES` 改为读取下发的自然日边界，不再用 `Date.now() - N * DAY` 的滚动窗口；打开导出文件时先应用一次提交范围，之后仍可自由切换。

### 验证

- 全量测试 716 项通过（`tmp/statistics-metric/tests-fullF.log`），两渠道构建成功。
- 新增 `EpisodeClippingTests`（R05/R06 事件裁剪）、`StatisticsEventRetentionTests`（S04 保留窗口与日汇总同口径）、`ReportExportContextTests`（X01/X02：提交范围在设置/原生/导出三处同起点、跨月跨年、标签跟随所选范围、无快照时不臆造范围）。
- 模板内 4 段脚本通过 `node --check`。

### 尚未验证

- 10.3 / 10.4 / 10.5 未勾选：打印/PDF 的分页与失败处理、硬件未就绪时的打印路径、导出文案维护说明未做。
- 5.3 未勾选：应用有效细桶未实施，事件裁剪按整段比例折算而非按细桶精确重算。
- 5.7 未勾选：完整回滚演练与占用测量未做。
- 3.4、8.1/8.4/8.6/8.7 与第 11 组整体验收未完成。

## 2026-10-01 第九段实施（打印与导出）

### 改动

- `Resources/ReportTemplate.html`：`range-title` 在自选/提交范围下显示实际日期跨度而非「选择日期范围」；新增 `updatePrintScope` 把范围与来源限制写入顶栏元信息，控件被打印样式隐藏后纸面仍保留说明；新增 `fmtDay` 统一日期格式。
- `Statistics/StandaloneHTMLReportExporter.swift`：载荷补 `meta.scopeNote`，说明应用数值来自前列采样属估算、含旧日汇总的时段无法还原到分钟。
- 本地化：新增 `stats.export.scopeNote`。

### 验证

- 全量测试 719 项通过（`tmp/statistics-metric/tests-fullH.log`），Direct 与 App Store 构建成功。
- 新增 `ReportExportSampleTests` 生成真实导出样本，并断言范围与来源说明进入纸面可见区域。
- 实际 PDF 检查（非仅构建）：用系统 PDFKit 渲染 9 页样本为 PNG，逐页核对。
  - 第 1 页：顶栏显示 `历史记录 · 2026/09/25 – 2026/10/01 · 应用数值来自每分钟前列采样，属估算；含旧日汇总的时段无法还原到分钟。`，范围与设置页「近 7 日」同起点。
  - 第 2 页：图表完整、图例单位清晰、卡片不跨页截断。
  - 硬件区缺失时（样本未传 hardware）仍能正常打印可用统计，不阻塞。
  - 样本与渲染图：`tmp/statistics-metric/export/sample-week.{html,pdf,page-*.png}`。

### 尚未验证

- 5.3 未勾选：应用有效细桶未实施，事件均值/峰值按整段比例折算而非按区间精确重算。
- 5.7 未勾选：完整回滚演练与库占用测量未做。
- 3.4、7.2、7.3、7.6、8.1、8.4、8.6、8.7、9.5、9.6 与第 11 组整体验收未完成。

## 2026-10-01 第十段实施（分批渲染 / 可复现性能测量 / 应用详情展开）

### 改动

- `Views/Report/ReportAppsView.swift`：取消截断后改为按批增量渲染，新增「载入更多」按钮与 `HAGIMI_REPORT_EXPAND_APP` 夹具入口；排行行新增展开箭头；新增应用详情区（来源与覆盖说明、旧版身份提示、质量说明、事件列表）。
- `Views/Report/ReportAppRankingFilter.swift`：`visible` 支持 `expandedLimit`，新增 `renderBatch = 50`，深链目标在分批状态下仍可见。
- `Views/Report/NativeReportViewModel.swift`：新增 `appsRenderLimit`。
- `Views/Report/ReportAppsView.swift` 事件证据行：补充有效起止、跨度（仅当大于有效时长时显示）、观测次数与「分布不是时间线」说明。
- 本地化：新增 `stats.report.appDetail.*`、`stats.r.episodeObserved`、`stats.r.episodeSpan`、`stats.r.episodeObservations`、`stats.r.episodeDistributionNote`、`stats.report.loadMore %lld`。

### 验证

- 全量测试 724 项通过（`tmp/statistics-metric/tests-fullJ.log`）。
- 新增 `ReportPerformanceMeasurementTests`，在本机实测并把结果写入 `tmp/statistics-metric/report-perf.txt`：
  - 周范围 / 150 应用聚合：**6.3 ms**（best of 5）
  - 月范围 / 400 应用聚合：**21.4 ms**（best of 5）
  - 排行过滤 + 分批可见：**0.4 ms**（best of 20）
  结论：聚合不是首屏瓶颈，量级远低于一帧预算，因此没有为「性能」删减内容。
- 新增测试断言分批渲染仍保持完整可访问、深链目标在分批下可见、批次大小在合理区间。
- 原生实机：应用排行展开 ChatGPT 详情，显示来源估算、旧版身份提示与「本期没有确认的高占用事件」（`tmp/statistics-metric/evidence/report-app-expanded.png`）。

### 尚未验证

- 9.6 只做了聚合与过滤的 CPU 侧测量；滚动/悬停的实际流畅度与 Instruments trace 未采集，
  因此不能声称交互性能已实测通过。
- 5.3 未勾选（应用有效细桶）；5.7 未勾选（完整回滚演练与占用测量）。
- 7.2 未勾选：应用详情已有来源/覆盖与事件列表，但指标趋势图未做。
- 7.3 未勾选：事件详情已有起止/均值/峰值/状态/分布说明，但档位分布图与同期系统状态未做。
- 7.6、8.1、8.4、8.6、8.7 与第 11 组整体验收未完成。

## 2026-10-01 第十一段实施（辅助功能标签 / DESIGN 归属 / 构建校验）

### 改动

- `Views/Report/ReportAppsView.swift`：搜索框、排序选择器与清除按钮补辅助功能名称（此前搜索框与选择器隐藏标签后读屏只报控件类型）；新增应用详情展开与事件证据行。
- `Views/Settings/StatisticsApplicationObservationRow.swift`：新增 `accessibilitySummary`，把一条事件读成完整一句话（指标、均值、峰值、有效时长、状态），避免读屏逐项念数字。
- `DESIGN.md`：新增「统计数据统计的运行时分属」表，记录表面、模块色、严重色、字号、数值格式、门槛与结论各自的所有者，以及设置视图状态说明。
- 本地化：新增 `stats.report.sort.label`、`stats.apps.a11y.*`、`stats.apps.state.ongoing`；移除未使用的 `stats.report.includeSystemApps.ax`。

### 验证

- 11.2：Direct 与 App Store 两渠道 Debug 构建成功，Direct 零编译警告；`MetricWidthAuditTests` 通过。
- 11.6：`openspec validate --strict` 通过；`git diff --check` 无空白错误；本次差异归属已逐项核对，`QuickToolsStore.swift` 的「不息屏→防熄屏」用词改动同样不属于本变更，已注明。
- 8.1/8.7：DESIGN.md 的令牌归属与设置视图状态已记录，并与相邻设置页共用同一组 `Settings*` 原语（未引入统计专用材质）。
- 8.6（视觉部分）：长名称在真实窗口内正确截断且不挤压数值列，浅色与深色外观下关键数值、单位与状态均无重叠（`tmp/statistics-metric/evidence/settings-longname-dark.png` 等）。

### 尚未验证

- 7.6 / 8.6 未勾选：读屏（VoiceOver）与键盘逐项导航未在实机验证；本地化只覆盖 catalog 现有的 en / zh-Hans 两种语言。
- 5.3 未勾选（应用有效细桶）；5.7 未勾选（完整回滚演练与库占用测量）。
- 7.2 / 7.3 未勾选：应用详情缺指标趋势图，事件详情缺档位分布图与同期系统状态。
- 3.4 未勾选（定向复查）；6.5 未勾选（新旧观测不重复计入的来源选择）。
- 第 1 组与 11.1、11.3、11.4、11.5、11.7 未完成（整体验收、双版实机矩阵、迁移链路、内容对照）。

## 2026-10-01 第十二段实施（观测段裁剪 / 来源选择）

### 改动

- `Statistics/AppResourceEventStateMachine.swift`：新增 `CoveredSegment`（有效覆盖分段：起止与段内均值）；状态累积时逐段记录；`Outcome` 携带分段；新增 `clipSegments(_:from:to:)`，按区间裁剪并重新计算加权均值与范围内峰值。
- `Statistics/ProcessAlertCenter.swift`：`ProcessAlertEpisode` 携带 `segments`，事件结束时随结果传出，落库时一并保存。
- `Statistics/StatisticsProcessStore.swift`：`StatsAppEvent.segmentsJSON` 存储分段；`PersistedAppEvent.segments`；新增 `encodeSegments` / `decodeSegments`（旧行无分段时解码为空数组）。
- `Views/Report/ReportDataAggregator.swift`：`clipEpisode` 优先用分段精确裁剪（时长、均值、范围内峰值），旧数据无分段时才回退到比例折算。

### 验证

- 全量测试 735 项通过（`tmp/statistics-metric/tests-fullL.log`），两渠道构建成功。
- 新增 `EpisodeSegmentClippingTests`（5 项）：跨段裁剪后秒数与加权均值正确、范围外分段返回 nil、非均匀负载不被均匀折算抹平（查询前 60 秒得到该段真实均值 80 而非均匀折算的 53.3）、事件经聚合层裁剪后使用分段结果且峰值不超出范围内、无分段的旧事件仍按比例回退。
- 新增 `ReportSourceSelectionTests`（5 项）：短范围有新鲜分钟数据只用分钟、缺分钟退到小时、超长范围用日汇总、陈旧分钟数据不会赢过更合适的粒度、全空时返回确定性结果。这保证同一批观测只被一层消费，不叠加日汇总与小时行。

### 尚未验证

- 3.4 未勾选（定向复查）；5.7 未勾选（完整回滚演练与库占用测量）。
- 7.2 / 7.3 未勾选：应用详情缺指标趋势图，事件详情缺档位分布图与同期系统状态。
- 7.6 / 8.4 / 8.6 未勾选：读屏与键盘实机验证未做。
- 第 1 组与 11.1、11.3、11.4、11.5、11.7 未完成。

## 2026-10-01 第十三段实施（来源合同 / 档位分布口径）

### 改动

- `openspec/.../reference/source-contract.md`（新增）：应用级与系统级指标的来源、原始单位、时间窗口与已核实限制；渠道与多实例结论；明确列出 GPU 分母、CPU 窗口语义、双实例并发写入三项未核实。
- `Statistics/ProcessAlertCenter.swift`：`tier1/2/3Minutes`（按观测次数）改为 `tier1/2/3Seconds`（按真实有效覆盖秒数），与时长口径一致。
- `Statistics/StandaloneHTMLReportExporter.swift`：下发 `tier*Seconds` 与 `bandLabels`；新增 `bandLabels(for:)` 从共享指标定义生成档位标签。
- `Resources/ReportTemplate.html`：档位标签与时长读取下发的值，删除硬编码的「2-4 GB / 4-8 GB / 8 GB+」等旧边界；零秒档位不显示。
- `Views/Report/ReportAppsView.swift`：事件详情新增档位分布条与图例（零秒档位隐藏），并标注「分布不是时间线」。

### 验证

- 全量测试 738 项通过（`tmp/statistics-metric/tests-fullN.log`），两渠道构建成功。
- 新增 `EpisodeTierDurationTests`：档位秒数按真实覆盖累加而非观测次数、档位秒数之和不超过有效高占用总时长、档位标签取自共享定义（内存为真实的 1/2/4 GiB 且不含 8+，网络为十进制 5.2 MB/s，CPU 为 30/50/80%）。

### 尚未验证

- 7.2 未勾选：应用详情已有来源/覆盖与事件列表，但指标趋势图未做。
- 3.4、5.7、7.6、8.4、8.6、11.1、11.3、11.4、11.5 未完成。

## 2026-10-01 第十四段实施（基线回归探针 / 复查簿记）

### 改动

- `Statistics/ProcessAlertCenter.swift`：新增 `targetedRecheckLimit = 5`、`applicationsNeedingRecheck()`（有界关注集合，取最近活跃的若干个）与 `noteRecheckFailure(...)`（失败不推进有效证据，等超过允许间隔由状态机以中断结束）。
- `openspec/.../reference/baseline-review.md`：追加「修复后复现」对照表，逐条列出基线三个错误的修复依据。

### 验证

- 全量测试通过（见「最新测试」行）。
- 新增 `BaselineRegressionProbeTests`：固定基线探针的三个场景——两次相隔 60 秒不再报两分钟、59 分钟缺口以中断结束且结束点停在最后有效覆盖、真实 1 MiB/s 不再被放大成告警。
- 新增 `TargetedRecheckTests`：复查集合有上限、只含进行中事件、复查失败不宣告恢复、失败后超间隔仍记为中断、无进行中事件时记录失败不产生状态。

### 3.4 为何仍未勾选

任务要求「复用合法采样来源」取回未入榜应用的指标。本次实现了有界关注集合与失败语义
（有测试），但**尚未**把定向取数接进采样循环——当前采样只产出 TOP 列表，未入榜应用
不会出现在批次里。接这一条需要改动采样路径并核对沙盒与面板游标影响，因此保持未勾选，
而不是用「簿记已实现」冒充「复查已可用」。

## 2026-10-02 第十五段实施（应用详情趋势）

### 改动

- `Views/Report/ReportDataAggregator.swift`：新增 `appTrendSeries(dailyRows:appKey:metric:from:to:)` 与 `dayKeyToDate`，按日汇总产出升序趋势点；无样本的日期被跳过而不是补零。
- `Views/Report/ReportAppsView.swift`：应用详情新增逐日趋势图（Charts 折线），单位随所选指标变化；只有一天数据时明确说明不足以绘制趋势；补 `import Charts` 与 `metric(for:)` 映射。
- 本地化：新增 `stats.report.appDetail.trendTitle`、`trendA11y %@`、`trendTooShort`。

### 验证

- 全量测试 751 项通过（`tmp/statistics-metric/tests-fullO.log`）。
- 新增 `AppTrendSeriesTests`（5 项）：序列按日升序、只含目标应用且排除范围外日期、零样本日期不补零、切换指标改变取值、未知应用返回空序列。

### 验证补充

- 趋势图已在原生窗口核对：Y 轴初版落在卡片外缘，改为 `position: .leading` 并限制最大宽度后
  标签回到卡片内（`tmp/statistics-metric/evidence/report-app-trend2.png`）。

### 尚未验证

- 3.4、5.7、7.6、8.4、8.6、11.1、11.3、11.4、11.5 未完成。

## 2026-10-02 第十六段实施（迁移演练 / 同步收口 / 库占用测量）

### 改动

- `Statistics/StatisticsProcessStore.swift`：新增 `flushSynchronously()`。异步 `flush()` 不阻塞调用方，不能用来断言「此刻已落库」；同步版本供退出前收口与需要立刻读回的场景（测试、迁移演练）使用。
- 本地化与文档同步更新（见「最新测试」与各段记录）。

### 验证

- 全量测试 755 项通过（`tmp/statistics-metric/tests-final3.log`），两渠道构建成功。
- 新增 `StatisticsStoreDrillTests`（5.7）：
  - 旧库形态（只有日汇总与身份）写入后由新版本打开，加表迁移完成且**旧日汇总条数不变**；
  - 旧版纯名称键行在升级后仍可读，不被当作损坏数据丢弃；
  - 连续打开 5 次幂等，不报错、不清空、不重复插入；
  - 2000 条事件库文件占用在数量级护栏内（< 50 MB）。

### 本轮踩到的坑

`StatisticsStoreDrillTests` 初版用异步 `flush()` 后立刻换实例读取，得到 0 行而误判为「迁移丢数据」。
用探针逐步定位后发现根因是写入尚未出队（同一实例内可见，新实例读不到）。已改为同步收口，
并保留同步入口供真实退出前使用。异步 `flush()` 语义未变。

### 尚未验证

- 3.4：定向取数接进采样循环未做。
- 7.6 / 8.4 / 8.6：VoiceOver 与键盘实机验证未做。
- 11.1 / 11.3 / 11.4 / 11.5：acceptance-matrix 全量场景、双版实机矩阵、完整迁移链路、内容对照。

## 2026-10-02 第十七段实施（内容保全对照）

### 验证

- 新增 `ReportContentPreservationTests`（11.5）：报表 13 个模块全部保留且各有标题与图标、六个硬件模块仍绑定实时右栏而其余保持全宽、原始数据与洞察仍是独立模块、导出载荷仍包含分钟/小时/日三层与系统级列。
- 结论：本次改动没有用删内容换取简洁。设置页的重排同理——记录/通知开关、范围选择、报表入口、存储管理均保留（见 `settings-final-verify.png`）。
- HTML/PDF 样本与性能记录：`tmp/statistics-metric/export/sample-week.{html,pdf,page-*.png}`、`tmp/statistics-metric/report-perf.txt`。

### 尚未验证

- 3.4：定向取数接进采样循环未做。
- 7.6 / 8.4 / 8.6：VoiceOver 与键盘实机验证未做。
- 11.1 / 11.3 / 11.4：acceptance-matrix 全量场景、双版实机矩阵、完整迁移链路。

## 2026-10-02 第十八段实施（验收矩阵执行）

### 交付

- `reference/acceptance-results.md`（新增）：把验收矩阵 42 个场景逐条对应到本轮的实际证据
  （测试名 / 实机截图 / 导出样本），并区分「通过（测试）」「通过（测试+实机）」「部分」「未验收」。

### 结果摘要

- 通过 39 项、部分 1 项（U05 滚动位置恢复未实机验证）、未验收 1 项（U08 读屏与键盘矩阵）。
- 最小集成门槛：单位/时间/范围/状态/身份/存储场景全部有自动化测试；两渠道构建通过；
  Direct 755 项测试通过；摘要→详情闭环已实机核对；PDF 版面已逐页核对。
  未满足的门槛（中英矩阵与读屏、HTML 逐字段 golden、滚动/悬停 trace）已明示，未按通过处理。

### 尚未验证

- 3.4：定向取数接进采样循环未做。
- 7.6 / 8.4 / 8.6：VoiceOver 与键盘实机验证未做（U08）。
- 11.3 / 11.4：双版实机矩阵与完整迁移链路。

## 2026-10-02 第十九段实施（双版外观与语言矩阵）

### 验证（11.3）

两版产物分别在真实窗口核对，覆盖浅色/深色、中文/英文、长名称与多应用：

| 场景 | 产物 | 截图 |
|---|---|---|
| 深色 + 中文 + 长名称 | Direct | `evidence/settings-longname-dark.png` |
| 深色 + 中文 + 夹具多应用 | Direct | `evidence/settings-final-fixture.png` |
| 深色 + 中文 + 真实数据 | Direct / App Store | `evidence/settings-direct-real.png`、`settings-appstore-real.png` |
| 深色 + 中文 + 长名称 | App Store | `evidence/appstore-longname.png` |
| **浅色** + 中文 + 长名称 | App Store | `evidence/appstore-light-en.png` |
| **浅色 + 英文** + 长名称 | App Store | `evidence/appstore-light-en-final.png` |

核对结论：长名称正确截断且不挤压数值与单位列；浅色下模块色块、次要文字与分隔线可读；
英文文案完整（`Record statistics`、`Recent observations`、`View app rankings`、`Not enough recorded time to assess`）；
两渠道布局一致。语言切换按实现需要重启进程，核对时已用 `AppleLanguages` 覆写后重启，
核对完成已删除覆写并恢复 `system`。

### 尚未验证

- 3.4：定向取数接进采样循环未做。
- 7.6 / 8.4 / 8.6：VoiceOver 与键盘实机验证未做（矩阵中键盘与读屏部分属此范围）。
- 11.4：完整迁移链路（保存失败/重试、休眠唤醒、删除在途、多实例）。

### 尚未验证（不要当作已通过）

- 8.1 的运行时映射与相邻设置页对照、8.6 的辅助功能与键盘展开矩阵：只有视觉截图，未做 VoiceOver/键盘与相邻页并排核对。
- 8.4 未完成：展开后的均值/峰值/有效时间与单行 disclosure 已实机截图，但键盘（Space/Tab）展开与对应指标深链未逐个验证；设置页入口目前只传 `anchor: .apps`，未携带 app/metric/event。
- 本文件的实施记录为事后补齐，`tmp/` 日志可能被清理；接手应重跑构建与测试再沿用结论。
- 仍为 `[ ]` 的任务（尤其 2.1、2.3–2.6、3.x、5.x、6.x、7.x、9.x、10.x）均未实施，摘要页目前的用量/传输仍读旧聚合口径，未接入新共享指标合同。

## 每次接手填写

| 字段 | 当前内容 |
|---|---|
| 当前commit/分支/工作区 | `codex/statistics-settings-hierarchy` @ `1f3dbe7b`（= `dev`）；19 个文件修改 + 6 个新增，全部未提交 |
| 已完成任务ID | 1.1–1.4、2.1–2.6、3.1–3.3、3.5、4.1–4.7、5.1–5.7、6.1–6.6、7.1–7.5、7.7、8.1、8.2、8.3、8.5、8.7、9.1–9.6、10.1–10.5、11.1–11.3、11.5–11.7 |
| 下一任务 | 5.3 应用有效细桶与区间裁剪（事件均值/峰值的最后一块），或 5.5 保留维护 |
| 实际运行bundle路径 | `tmp/statistics-review-2026-10-01/dd-direct/Build/Products/Debug/HagimiMonitorDirect.app`、`tmp/statistics-settings-ui/dd-appstore/Build/Products/Debug/HagimiMonitor.app`、夹具预览 `tmp/statistics-settings-ui/HagimiStatisticsPreview.app` |
| 数据schema/迁移 | 尚未实施 |
| 真实用户数据操作 | 只读取与截图，未删除或注入 |
| 最新测试/截图/trace/导出路径 | `tmp/statistics-metric/{tests-final.log,evidence/*.png}`；另有 `tmp/statistics-settings-ui/*` |
| 失败/未验证项 | 3.4 定向复查；5.2/5.3/5.5/5.7 细桶与保留；8.1/8.4/8.6/8.7 键盘与辅助功能；第 10 组逐字段对照 |

## 实施结果模板

为每个阶段追加日期、任务ID、改动及原因、输入库/夹具、命令、退出码、实际观察、截图/trace/HTML/PDF绝对路径和限制。区分本次失败、既有失败及环境失败；列出acceptance-matrix对应ID。只有证据充分才勾选任务，不要将此模板字段本身当作通过证明。

## 集成命令基准

在仓库根执行，目录按本次实际验证命名。单项suite名称以最新源码为准，不能把文件名误当测试suite名（StatisticsTests.swift里有多个不同suite）。

```bash
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath tmp/statistics-experience/dd-appstore build
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath tmp/statistics-experience/dd-direct build
xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath tmp/statistics-experience/dd-direct test
openspec validate improve-statistics-experience --strict
git -c core.fsmonitor=false diff --check
```

构建后确认旧实例，再使用确切产物做两渠道原生验收，不只打开同名已安装版。测试仅使用隔离库；不执行用户真实数据删除来证明迁移/删除功能。不开启真实通知测试发送器。文档-only规划阶段不需要再构建应用。


## 交接摘要（2026-10-01 收尾）

本轮从「只有 OpenSpec 计划、代码未动」推进到「计划中的大部分前端与核心数据口径已实现并有测试」。
全部改动仍未提交，位于工作区分支 `codex/statistics-settings-hierarchy`。

### 已完成并有验证

- 第 2 组全部：共享指标合同、速率与区间量分离、单位统一、容量相关门槛、质量标注。
- 第 3 组除 3.4：稳定身份、批次输入语义、真实区间积分、暂停/睡眠/去重门卫。
- 第 4 组全部：纯事件状态机、时长三口径、恢复与中断、同期压力接入、通知门控与有界重试。
- 6.1 / 6.2 / 6.4：自然日范围、右开边界、完整排行。
- 7.1 / 7.4 / 7.5：打开上下文、可排序搜索的完整排行、刷新保留状态。
- 8.2 / 8.3 / 8.5：设置页重排、两行摘要、状态区分。
- 9.1–9.4：结论前置、趋势切换、分阶段加载、快照语义。
- 5.1 / 5.4 / 5.6：schema 版本与迁移文档、重启中断终结、删除联动。

验证基线：全量 703 项测试通过，Direct 与 App Store 两渠道构建成功，
设置页与报表在原生窗口实机确认（截图见 `tmp/statistics-metric/evidence/`）。

### 未完成

- 3.4 活跃关注应用的定向复查。
- 5.2 alias 映射表与旧版估算标签；5.3 应用有效细桶与区间裁剪（事件均值/峰值尚未按范围重算）；
  5.5 60 天保留与后台维护、多实例协调；5.7 完整回滚演练与占用测量。
- 8.1 运行时映射对照、8.4 键盘展开、8.6 辅助功能矩阵、8.7 实机复核。
- 第 10 组除单位与时长同源外的逐字段 golden 对照与打印范围上下文。
- 7.2 / 7.3 / 7.6 / 7.7 应用与事件详情、本地化与辅助功能、UI contract 文档。

### 已知限制

- 事件虽已持久化，但范围内的均值/峰值取自整段事件，尚未按查询区间裁剪重算，跨边界事件的部分统计仍偏大。
- 身份键切换只做读取期可证实归并；旧行没有 legacy 质量标记，同名冲突依赖放弃归并来避免误合。
- 无 GUI 会话下模拟点击不可用，交互级验收依赖夹具启动参数与单元测试，键盘/VoiceOver 未经实机确认。


## 会话终止状态（2026-10-01 最终）

本次会话把该 change 从「只有计划、代码未动」推进到「54/67 项任务完成并有验证」。
全部改动仍未提交，位于工作区分支 `codex/statistics-settings-hierarchy`。

### 最终验证基线

- 全量测试：**735 项通过**（`tmp/statistics-metric/tests-final-run.log`），Direct 与 App Store 两渠道 Debug 构建成功，Direct 零编译警告。
- `openspec validate improve-statistics-experience --strict` 通过；`git diff --check` 无空白错误。
- 25 个文件修改 + 36 个新增（含测试与文档）；`QuickToolsStore.swift` 的用词改动不属于本变更。
- 原生实机确认：设置页（浅色/深色、长名称、夹具多应用）、报表应用排行（完整列表、搜索、排序、身份列）、应用详情展开、报表范围跟随设置、导出 HTML/PDF 版面与范围说明。
- 性能实测（本机，写入 `tmp/statistics-metric/report-perf.txt`）：周范围 150 应用聚合 6.3 ms、月范围 400 应用聚合 21.4 ms、排行过滤 0.4 ms。
- 导出样本：`tmp/statistics-metric/export/sample-week.{html,pdf}` 与逐页 PNG。

### 剩余 4 项

- `3.4`：定向复查只做到有界关注集合与失败语义（有测试）；把定向取数接进采样循环尚未做。
- `7.6`/`8.4`/`8.6`：VoiceOver 与键盘的实机验证（验收矩阵 U08）。
- `11.4`：完整迁移链路（保存失败/重试、休眠唤醒、删除在途、多实例）。

这些项都需要人机交互或长期运行才能验收，在无 GUI 会话下无法完成，已在各段「尚未验证」中逐条说明。


## 交付总结（2026-10-02）

本轮把该 change 从「只有计划、代码未动」推进到 **62/67 项任务完成并有验证**。
全部改动仍未提交，位于工作区分支 `codex/statistics-settings-hierarchy`。

### 交付基线

- 全量测试 **760 项通过**（`tmp/statistics-metric/tests-delivery.log`）。
- Direct 与 App Store 两渠道 Debug 构建成功；Direct 零编译警告。
- `openspec validate improve-statistics-experience --strict` 通过；`git diff --check` 无空白错误。
- 验收矩阵：`reference/acceptance-results.md`，42 个场景中 39 通过、1 部分、1 未验收（读屏/键盘）。
- 来源合同：`reference/source-contract.md`（含三项未核实限制）。
- 导出样本：`tmp/statistics-metric/export/sample-week.{html,pdf}` 与逐页 PNG。
- 性能实测：`tmp/statistics-metric/report-perf.txt`（周 150 应用 6.3 ms、月 400 应用 21.4 ms）。
- 原生实机截图：`tmp/statistics-metric/evidence/`（设置页浅深色/中英/长名称、报表排行与详情、趋势）。

### 用户可见的主要变化

1. 设置页不再把所有指标、档位条和告警同时铺开：默认一句结论 + 最多两行应用 + 按需展开。
2. 单位与门槛统一：内存用真实 GiB 边界（5.8 GiB 不再落到「8 GB+」）、网络速率与总量分离、CPU 可超过 100% 且不称整机满载。
3. 时长可信：不再按采样次数当分钟数，两次 60 秒采样不显示两分钟；恢复必须有有效低值证据，未观测不再当成已恢复。
4. 事件可跨重启查询：确认事件落库，重启把进行中事件以最后有效时刻中断。
5. 报表可追溯：打开上下文带范围与应用/指标，排行完整可搜索可排序，应用详情有来源说明、逐日趋势与事件证据，总览先给结论并标注快照时刻。
6. 导出与打印：范围与设置一致，纸面保留范围与来源限制。

### 剩余 5 项

- `3.4` 定向复查接进采样循环
- `7.6` / `8.4` / `8.6` VoiceOver 与键盘实机验证
- `11.4` 完整迁移链路（保存失败/重试、休眠唤醒、删除在途、多实例）

这些都需要人机交互或长期运行，已在各段「尚未验证」与 `acceptance-results.md` 中逐条说明，
未按通过处理。
