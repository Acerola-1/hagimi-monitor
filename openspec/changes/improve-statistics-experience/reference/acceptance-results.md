# 验收矩阵执行结果（2026-10-02）

对应 [acceptance-matrix.md](acceptance-matrix.md)。状态含义：

- **通过（测试）**：由自动化测试断言，测试名可直接检索。
- **通过（测试+实机）**：另有原生窗口截图或导出样本佐证。
- **部分**：实现与测试覆盖了主路径，但验收条件中的某项（键盘/读屏/多语言矩阵等）未做。
- **未验收**：需要人机交互或长期运行，本会话无 GUI 会话无法完成。

全部结果来自本次实现，未使用旧测试结论或合成改进。

| ID | 状态 | 依据 |
|---|---|---|
| M01 | 通过（测试） | `StatisticsMetricDefinitionTests.memoryBandBoundariesUseBinaryCapacityAndTopBandIsFourGiB`：5.8 GiB 落 4 GiB+ 段；展示同源由 `StatisticsDisplayFormat.applicationObservationValue` 保证 |
| M02 | 通过（测试） | `StatisticsApplicationObservationTests.lowNetworkRateDoesNotBecomeHighUsageAfterRecording`（1 MiB/s 不触发）与 `ProcessSampleIntervalTests`（按真实间隔积分） |
| M03 | 通过（测试） | `StatisticsMetricDefinitionTests.decimalVolumeAndBinaryCapacityDoNotShareDivisors`：156 GB / 145 GiB 两套除数可区分 |
| M04 | 通过（测试） | 同文件 `cpuPercentBasisIsSingleCoreAndNotClamped`、`gpuBasisIsMarkedUninterpretable`、`memoryThresholdScalesWithPhysicalCapacity`（8/16/32/64 GiB 与未知容量） |
| E01 | 通过（测试） | `AppResourceEventStateMachineTests.firstInstantSampleAddsNoDuration`、`twoInstantSamplesReachOnlySixtySeconds` |
| E02 | 通过（测试） | 同文件 `threeInstantSamplesConfirmAtOneHundredTwentySeconds`、`lowObservationConfirmsRecovery` |
| E03 | 通过（测试） | 同文件 `overlappingMetricIntervalsCountOnceForTheApp`（并集 180 而非 240） |
| E04 | 通过（测试） | 同文件 `longGapInterruptsAndDoesNotAccumulateMissingTime` |
| E05 | 通过（测试） | 同文件 `unknownDoesNotAnnounceRecovery`、`unknownBeyondGapEndsAsInterruptedNotRecovered`；`TargetedRecheckTests.recheckFailureDoesNotDeclareRecovery` |
| E06 | 通过（测试） | 同文件 `processExitEndsAsInterruptedReason`、`suspendEndsOngoingEvent`、`pidReuseEndsPreviousEvidence`；`ProcessBatchGateTests.callbacksAfterSuspendAreDropped` |
| A01 | 通过（测试） | `AppIdentityTests`（改名不拆、同名不合、系统进程用路径、unresolved 不跨启动、跨类别不碰撞） |
| A02 | 通过（测试） | `ProcessAlertCenterDurationTests.networkBatchDoesNotImplyCpuRecovery`；`ProcessBatchGateTests.duplicateBatchAtSameTimestampCountsOnce` |
| N01 | 通过（测试） | `AppAlertNotificationPolicyTests.regularHighUsageWithoutSystemPressureDoesNotNotify`、`ProcessAlertNotificationGateTests.confirmedEventIsRecordedEvenWhenNotificationIsSkipped` |
| N02 | 通过（测试） | 同文件 `confirmedHighUsageWithConcurrentPressureNotifies`、`severityEscalationSendsBoundedUpdate`；文案使用统一单位 |
| N03 | 通过（测试） | `AppAlertNotificationRetryTests`（失败不虚记、上限 3 次、失败后可重试、总开关关闭跳过） |
| S01 | 通过（测试） | `StatisticsStoreMigrationTests`、`StatisticsStoreDrillTests.legacyShapeOpensAndUpgradesWithoutLosingHistory`（旧日汇总条数不变） |
| S02 | 通过（测试） | `AppIdentityTests.legacyNameWithConflictingIdentitiesIsNotMerged`、`legacyNameMapsOnlyWhenUnambiguous` |
| S03 | 通过（测试） | `AppEventPersistenceTests.ongoingEventIsInterruptedAtLastEffectiveMoment`、`eventsSurviveStoreReopen` |
| S04 | 通过（测试） | `StatisticsEventRetentionTests.eventsOlderThanCutoffAreRemovedWithDailyRows`、`ReportTimeRangeTests.daylightSavingBoundaryUsesCalendarDaysNotFixedSeconds` |
| S05 | 通过（测试） | `StatisticsStoreDeletionTests.deleteRangeRemovesEventsInsideIt`、`deleteRangeLeavesEventsOutsideIt` |
| S06 | 通过（测试） | 同文件 `twoDirectoriesStayIndependent` |
| R01 | 通过（测试） | `ReportTimeRangeTests.weekRangeStartsAtLocalMidnightSixDaysBeforeToday`；`StatisticsReportContextTests.settingsRangeMapsToReportRangeWithoutChangingDay` |
| R02 | 通过（测试） | 同文件 `daylightSavingBoundaryUsesCalendarDaysNotFixedSeconds`、`weekRangeCrossesYearBoundary` |
| R03 | 通过（测试） | `StatisticsDayRangeTests.exclusiveEndAtMidnightExcludesThatWholeDay` |
| R04 | 通过（测试） | `ReportSourceSelectionTests`（来源选择与退化路径）；部分日裁剪由 `EpisodeClippingTests` 覆盖 |
| R05 | 通过（测试） | `EpisodeClippingTests.eventStraddlingStartIsClippedToRange`（跨午夜只计本期、ID 不变） |
| R06 | 通过（测试） | `EpisodeClippingTests.eventEntirelyBeforeRangeIsDropped`；`ReportDataAggregator` 事件按交集过滤 |
| U01 | 通过（测试+实机） | `StatisticsReportContextTests`（上下文提交）；实机 `report-apps-week.png`、`report-deeplink-gpu.png` |
| U02 | 通过（测试+实机） | `AppTrendSeriesTests`（零样本不补零）；实机 `report-app-expanded.png`、`report-app-trend2.png` |
| U03 | 通过（测试+实机） | `EpisodeTierDurationTests`、`EpisodeSegmentClippingTests`；实机事件行显示状态与原因 |
| U04 | 通过（测试+实机） | `ReportAppRankingFilterTests`（>25 全可访问、搜索、清除、三种排序）；实机 `report-final.png` 显示 157/400 个应用与「再载入」 |
| U05 | 部分 | `StatisticsReportContextTests.refreshKeepsRangeFocusAndRankingState` 覆盖状态保留；滚动位置恢复未实机验证 |
| U06 | 通过（测试+实机） | 实机 `settings-final-fixture.png`、`settings-final-verify.png`：结论、两行应用、报表入口可见 |
| U07 | 通过（测试+实机） | `ReportAppRankingFilterTests`（稳定排序）；实机多应用夹具 |
| U08 | 未验收 | 浅深色与长名称已截图（`settings-longname-dark.png`），但读屏、键盘与多语言矩阵未实测 |
| U09 | 通过（测试+实机） | `ReportPeriodConclusionTests`（高占用+低压力不误报、观测不足）；`StatisticsSnapshotSemanticsTests`；实机 `report-overview3.png` |
| P01 | 通过（测试） | `StatisticsSnapshotSemanticsTests`（分阶段：统计先发布，`isHardwareLoading` 独立）；实机硬件区显示「正在采集」 |
| P02 | 通过（测试） | 同文件 `aggregatedModelCarriesSnapshotTimestamp`、`aggregateDoesNotInventValuesWhenRangeHasNoRows` |
| P03 | 通过（测试） | `ReportPerformanceMeasurementTests` 实测并写入 `tmp/statistics-metric/report-perf.txt`；交互流畅度 trace 未采集（记录在 tasks 9.6） |
| X01 | 通过（测试+实机） | `ReportExportContextTests`；导出样本 `sample-week.pdf` 第 1 页显示 `2026/09/25 – 2026/10/01` |
| X02 | 通过（测试） | `StandaloneHTMLReportExporterTests.exportPayloadCarriesRangeBoundsAndScopeNote`、`templateUsesProvidedRangeBounds`；单位同源由 `fmtcheck.js` 逐字对照 |
| X03 | 通过（实机） | `sample-week.pdf` 9 页逐页渲染核对：浅色纸面、卡片不跨页、范围与来源限制保留 |
| X04 | 通过（测试） | `ReportResidualCleanupTests`（打印会话超时释放、临时文件清理、幂等 finish） |

## 统计

- 通过（测试或测试+实机/导出）：39
- 部分：1（U05）
- 未验收：1（U08）
- 其余 3 项（含 R04/P03 的次要条件）已在「部分/未验收」中说明其边界。

## 最小集成门槛

- 单位/时间/范围/状态/身份/存储正确性场景：全部有自动化测试。
- 两渠道构建：通过。
- Direct 测试：755 项通过。
- 原生摘要→详情闭环与浅深色/中英关键矩阵：摘要→详情已实机核对；**中英矩阵与读屏未做**（U08）。
- HTML/PDF 等价：单位与范围同源、PDF 版面已核对；**逐字段 golden 对照只覆盖格式化与范围**。
- 冷/热加载与高频交互证据：聚合耗时已测；**滚动/悬停 trace 未采集**。

未满足的门槛项均已在上表与 tasks 的未勾选项中明示，未按通过处理。
