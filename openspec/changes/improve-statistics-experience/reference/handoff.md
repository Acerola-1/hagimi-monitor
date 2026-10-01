# 接手入口

## 阅读顺序与授权

1. [proposal.md](../proposal.md)：用户采纳的范围与为什么做。
2. [baseline-review.md](baseline-review.md)：本轮实际发现、源码依据和验证边界。
3. [design.md](../design.md)：D1–D9目标设计，包括布局、默认政策、状态机和迁移。
4. `../specs/*/spec.md`：可测试的行为合同。
5. [tasks.md](../tasks.md)：按依赖执行的任务，每项自带完成依据。
6. [acceptance-matrix.md](acceptance-matrix.md)、[verification.md](verification.md)：夹具与验收记录。

用户原话：希望从页面设计、打开大报表、统计口径、前后端代码和数据采集全面评估，最不满意高负载应用的一行行指标视图，因为“信息很全，但第一时间可能不知道该看什么”。评估后用户于2026-10-01采纳“这轮说的所有值得优化的地方”，请求详细OpenSpec计划供另一Agent接手。本轮授权的是计划；本计划准备完成不代表已经实施。后续收到明确实施授权时使用 `openspec-apply-change`，指定 `improve-statistics-experience`，不要误选已完成的原生报表迁移。

## 不得丢失的设计意图

- 简洁来自默认层级和渐进展开，完整信息仍在报表详情；不是删掉指标、图表或原始数据。
- 设置先回答“系统状态怎样、哪个应用值得关注、哪里看详情”，默认最多两行应用摘要，不铺档位分布。
- 正常高占用与真实系统压力是不同概念；降低吓人的警报语气，但真实严重状态仍要清晰可见。
- 摘要→应用→指标/事件详情要准确，不只跳CPU排行；历史范围和当前状态分开。
- 单位、时间、均值、档位、事件计数和数据质量先正确，再做界面；不能只修字符串包装错误数据。
- 旧日数据和前列采样有限制，必须明说；重启前没有持久化的事件不能凭空恢复。
- 经典毛玻璃和现有模块令牌是产品方向，HTML原型只能验证信息结构，不能代替原生材质/滚动/交互验收。
- 默认门槛、120秒资格、90秒瞬时maxGap、60日新数据保留和通知门控是计划中的具体默认，不能写成此前实测产品事实；如有技术证据要求修订，说明修改理由并保持用户可观察合同。

## 2026-10-01工作区边界

计划开始时已有修改：`HagimiMonitor/Localizable.xcstrings`、`HagimiMonitor/QuickToolsStore.swift`；另有未跟踪 `premium-audit.json`。这些不属于本轮计划。尤其后续本地化会碰同一个catalog，必须定点编辑、保留原差异，不整份覆写或统一重排。实施者重新核实live status，不能假设该列表一直不变。

实机观察开发版路径：`tmp/quicktools-sleep-audit/HagimiMonitorDirect.app`；同时有`/Applications/HagimiMonitorDirect.app`运行。当前用户数据未删、通知未启用、没有点“演练示例”。菜单栏后台应用可能不会出现在普通应用清单，需先核实实际进程路径再选窗口；不要凭bundle ID含混地启动旧版本。

活动change `native-statistics-report` 在本次`openspec list`显示41/41任务完成但未归档。本计划接续其当前实现；旧project.md描述和部分历史spec参数已落后，最新AGENTS.md及这次明确产品决策优先。不要顺手修改旧change/无关spec或归档它们。

## 源码索引（基线行号，先CodeGraph刷新）

| 区域 | 文件/符号 | 阅读目的 |
|---|---|---|
| 排期与批次 | MonitorModels.swift:813–897，sampleProcessesForStatistics | 每分钟采样、CPU/GPU/网络分批回调、独立游标与渠道条件 |
| 网络输入 | Statistics/StatisticsRecorder.swift:300–335，recordProcesses | 当前速率×60被同时交给应用库和告警的错误链 |
| 系统时间参考 | StatisticsRecorder.swift:424–522，accrueSeconds/noteObservation | 已有freshKinds、maxGap、有效秒和交集处理，复用其原则而非拷贝一套参数 |
| 应用落库 | StatisticsProcessStore.swift:289–367、428–462 | 显示名作key、样本计数、阈值、队列/保存失败语义 |
| 应用事件 | ProcessAlertCenter.swift:153–353 | 时间按次数、未知即恢复、网络单位和通知，纯状态机拆分边界 |
| 设置摘要 | Views/Settings/StatisticsSettingsView.swift:269–379、585–765、958 | 卡片层级、默认1组/展开、错误档位标签及不传范围入口 |
| 报表范围 | Views/Report/ReportModels.swift:24 | 当前滚动秒数范围，需与设置自然日统一 |
| 聚合 | Views/Report/ReportDataAggregator.swift:504–753 | 结束日包含、排行截断、事件未过滤、均值/累计逻辑 |
| 原生展示 | ReportAppsView.swift、ReportOverviewView.swift、NativeReportView.swift | 排行/告警缺详情、总览评分/趋势/导航复用 |
| 后台加载 | NativeReportViewModel.swift:260–388 | 统计等待硬件、请求取消/generation、提交范围 |
| 窗口/导出 | ReportWindowPresenter.swift、Statistics/StandaloneHTMLReportExporter.swift | 锚点、导出上下文、打印清理 |
| 格式化 | StatisticsDisplayFormat.swift:54；ReportUIHelper.swift:78 | 十进制/二进制除数却同名GB |
| 探针缓存 | Hardware/SystemProfilerRunner.swift:22–64 | 已有共享5分钟缓存，不要误称为无缓存后重写 |

新增类型名是候选，允许复用当前已有模型；行为、单位和有效观测语义是验收合同。不可把这张2026-10-01行号表当永远新鲜的源码。

## 已有验证证据与复现

本轮Direct测试：ReportDataAggregatorTests、ReportCorrectnessTests，以及StatisticsRecorderTests/StatisticsSecondsTests/StatisticsDatabaseTests/StatisticsOverviewModelTests/StatisticsDisplayFormatTests，两次实际执行均为`TEST SUCCEEDED`。完整日志在`tmp/statistics-review-2026-10-01-tests.log`、`tmp/statistics-review-2026-10-01-recording-tests.log`；临时路径可能被清理，所以此记录仅证明当时结果，接手应重跑。

独立告警验证使用真实`ProcessAlertCenter.swift`与外部依赖替身。证据代码保存为[baseline-probe/main.swift](baseline-probe/main.swift)，不属于产品实现。复现时从仓库根执行：

```bash
mkdir -p tmp/statistics-plan-probe/cache
swiftc -module-cache-path tmp/statistics-plan-probe/cache \
  HagimiMonitor/Statistics/ProcessAlertCenter.swift \
  openspec/changes/improve-statistics-experience/reference/baseline-probe/main.swift \
  -o tmp/statistics-plan-probe/audit
tmp/statistics-plan-probe/audit
```

基线输出：60秒观测间隔显示2分钟；59分钟缺口后旧开始时间不变、计数3分钟；真实1MiB/s按旧转换输入触发网络告警并显示averageUsage=60。探针只用于重现旧算法，修复后应通过新状态机的正式测试表达正确结果，不能为了保留旧输出而调整新实现。未来API改变导致此探针不编译应记录为基线接口漂移，不能视为功能失败。

当前没有保存实机截图文件，不得把聊天中的临时截图当作已交付持久证据；实施阶段重新捕获并保存命名路径。没有Instruments基线、全暗色/英文矩阵或HTML/PDF全量等价性结论。

## 中断时如何交接

只勾选已完成且有证据的任务。在verification里写：已完成任务ID、未完成与原因、最新产物和日志路径、库版本及是否触及真实数据、正在运行哪个bundle、下一项任务ID。测试失败区分本次和已有问题；遇到环境限制明确记录，不标通过。未经用户要求不提交、不发布、不创建外部PR，也不额外自动创建聊天或分派Agent。
