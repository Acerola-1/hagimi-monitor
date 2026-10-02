# 统计存储 schema、迁移与回滚

本文记录进程统计库的结构、升级路径与回滚方式。实现以
`HagimiMonitor/Statistics/StatisticsProcessStore.swift` 为准。

## 库与实体

进程统计使用独立的 SwiftData 容器，位置在
`~/Library/Application Support/<bundle id>/…/AppStats.sqlite`（沙盒版在容器内），
与系统指标的 `statistics.sqlite3` 是两个库。

| 实体 | 作用 | 主键 |
|---|---|---|
| `StatsAppIdentity` | 应用身份与图标 | `appKey`（稳定身份键或旧显示名） |
| `StatsAppDaily` | 单应用单日聚合 | `day` + `appKey` |
| `StatsBatteryDaily` | 电池慢变量按日快照 | `day` |
| `StatsUsageMeta` | 使用打卡元信息 | 单例 |
| `StatsActiveDay` | 打卡活跃日 | `day` |
| `StatsAppEvent` | 确认的高占用事件 | `eventID` |

## 版本与迁移路线

当前 schema 版本为 **2**。版本 2 相对版本 1 的改动：

1. `StatsAppEvent` 为新增实体（加表）。
2. `StatsAppDaily.appKey` 的**取值语义**由显示名称改为带类别前缀的稳定身份键
   （`bundle:` / `systemExecutable:` / `unresolved:`）。

第 1 项由 SwiftData 的加表迁移承担：新建表、保留既有表，不需要重建容器，因此
旧库升级后历史日汇总与身份记录保持可读。

第 2 项**不是**结构变更，而是键空间变化。为不丢失历史，读取期做可证实归并：
`ReportDataAggregator.identityAliases` 把「显示名恰好等于某已知身份显示名」的旧键
映射到身份键；同名对应多个身份时放弃归并。这样改名场景能延续历史，同名不同应用
不会被误合。

## 回滚

- 新版本写入的 `StatsAppEvent` 与身份键行，旧版本不认识：旧版本打开同一库时会忽略
  新表，并把未知 `appKey` 当作普通名称行展示。**不会**发生静默丢弃。
- 因此回滚策略是「停用新写入后直接用旧二进制打开」，不需要降级脚本，也不需要删库。
- 若要完全回到旧形态，必须在回滚前保留一份升级前的库副本；本仓库不在用户真实库上
  做破坏性试验，演练使用独立临时目录的副本。

## 演练

`AppEventPersistenceTests` 覆盖：写入后读回、重复写入幂等、字段更新不产生重复行、
范围外事件不返回、跨边界事件返回、重启把进行中事件终结为中断（结束点取最后有效
时刻）、关闭并重新打开同一目录后历史仍可读。

`StatisticsTests` 中的既有存储用例继续覆盖日聚合、打卡与清理行为。

## 未完成

- 应用有效细桶（任意部分分钟的区间裁剪）与 60 个自然日保留维护尚未实施（tasks 5.3、5.5）。
- 范围删除尚未联动清理 `StatsAppEvent`（tasks 5.6）。
