# 原生报表交互约定

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Select/Listbox | ReportNavigationPicker | SwiftUI Picker selection | macOS 27 tabs; macOS 15–26 segmented | 实机点击与拖动时间和硬件分类 |
| Date | ReportCustomRangePicker | 起止端点草稿、Calendar 自然日边界和 applyCustomRange | macOS 27 tabs；macOS 15–26 segmented；一个 graphical DatePicker | 打开同步当前范围、端点联动、结束日期不晚于今天、取消与应用 |
| Overview score | ReportOverviewView | ReportActiveRangeModel.coverageRatio + StatisticsHealthScore.Result | 紧凑横向评分摘要带 | 评分 nil 原因、数据完整度边界、当前/历史评分口径 |
| Scrollbar | SwiftUI ScrollView / Table | macOS 用户滚动条设置 | 表格独立滚动，硬件分类横滚 | 最小宽度与长内容 |

本工具是 SwiftUI + AppKit，不使用网页 DOM、CSS、ARIA 或路由 URL。可访问性由原生控件语义与标签承担。报告卡片进入详情，刷新保留既有范围；日期浮窗取消不提交。后台聚合期间标题显示已提交数据日期，更新指示清晰可见。打印和导出保留系统对话框及错误提示。其他历史报表缺陷按原审计文档另行追踪，此次 UI 检查不追认先前全部验收勾选。

## 2026-10-01 补充约定

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| 打开上下文 | `StatisticsReportContext` + `StatisticsReportFlow` | range / anchor / appKey / metric / eventID | 首次开窗与复用窗口都提交新上下文 | 提交后标题与数据对应新范围；深链落到对应排行分类 |
| 时段结论 | `ReportPeriodConclusion` | 事件列表 + 覆盖秒数 + 质量标记 | 无观测 / 不足 / 平稳 / 出现压力 | 高占用+低压力不误报；结论明示只描述系统压力 |
| 质量说明 | `ReportActiveRangeModel.qualityNotice` | `StatisticsDataQuality` | 部分覆盖 / 旧日汇总 / 前列样本估算 / 不支持 | 估算值不以精确值外观出现；页面不得隐去限制 |
| 趋势视图 | `ReportOverviewView.TrendMode` | 用户切换 | 负载（CPU/GPU）与内存（压力/占比） | 默认只有两条负载曲线；每条曲线单位清晰 |
| 应用排行 | `ReportAppRankingFilter` + 视图模型状态 | 完整记录集合 | 按占用 / 峰值 / 名称排序，支持搜索、系统过滤与展开全部 | 超过 8 项可展开到完整列表；搜索无结果有明确状态；清除即恢复 |
| 事件证据行 | `ReportAppsView.episodeRow` | `ProcessAlertEpisode` | 进行中 / 已恢复（有效低值）/ 中断（原因） | 有效高占用时长与观测次数分开；中断不被写成恢复；注明时间重叠不代表因果 |
| 快照时刻 | `ReportActiveRangeModel.updatedAt` | 快照 capturedAt | 标题区显示 | 报表是历史快照，不宣称每秒实时更新 |
| 硬件加载 | `NativeReportViewModel.isHardwareLoading` | 第二阶段任务 | 统计先发布，硬件独立补充 | 统计可读时硬件区显示「正在采集」而不是「读不到」 |

历史事件来自落库的确认事件，与内存告警按事件 ID 去重合并；重启后仍可查询，进行中事件
在重启时终结为中断。范围内的均值/峰值目前取自整段事件，按区间裁剪仍待实施。
