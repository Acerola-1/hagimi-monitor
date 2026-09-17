# 原生报表交互约定

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Select/Listbox | ReportNavigationPicker | SwiftUI Picker selection | macOS 27 tabs; macOS 15–26 segmented | 实机点击与拖动时间和硬件分类 |
| Date | ReportCustomRangePicker | 起止端点草稿、Calendar 自然日边界和 applyCustomRange | macOS 27 tabs；macOS 15–26 segmented；一个 graphical DatePicker | 打开同步当前范围、端点联动、结束日期不晚于今天、取消与应用 |
| Overview score | ReportOverviewView | ReportActiveRangeModel.coverageRatio + StatisticsHealthScore.Result | 紧凑横向评分摘要带 | 评分 nil 原因、数据完整度边界、当前/历史评分口径 |
| Scrollbar | SwiftUI ScrollView / Table | macOS 用户滚动条设置 | 表格独立滚动，硬件分类横滚 | 最小宽度与长内容 |

本工具是 SwiftUI + AppKit，不使用网页 DOM、CSS、ARIA 或路由 URL。可访问性由原生控件语义与标签承担。报告卡片进入详情，刷新保留既有范围；日期浮窗取消不提交。后台聚合期间标题显示已提交数据日期，更新指示清晰可见。打印和导出保留系统对话框及错误提示。其他历史报表缺陷按原审计文档另行追踪，此次 UI 检查不追认先前全部验收勾选。
