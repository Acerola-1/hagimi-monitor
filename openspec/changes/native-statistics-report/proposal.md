## Why

当前 HagimiMonitor 报表窗口已经采用 `NSWindow` + `NSHostingView<NativeReportView>` 承载原生数据模型。ECharts、Flatpickr 与硬件脚本只在用户主动导出或打印时进入独立 HTML 生成路径；日常查看不创建常驻 WebKit。

本次改造将日常报表查看全面迁移为 macOS 原生窗口（AppKit 窗口生命周期 + SwiftUI 界面 + Swift Charts / 原生绘制），直接消费强类型 Swift 数据模型，使用原生 SF Symbols 与应用图标，并在关窗后及时释放报表专用的重型图表与数据资源；同时保留独立 HTML 导出及按需打印能力。

## What Changes

- **原生报表窗口**：日常查看报表改用 AppKit `NSWindow` + `NSHostingView`（SwiftUI）构建，不再静态创建或常驻 `WKWebView`。
- **强类型数据管线**：定义并消费原生 Swift 统计快照模型（`StatisticsReportModel` 及分模块结构），消除 `[[Any]]`、JSON 字符串以及仅供网页展示的 PNG→Base64 转码链路。
- **完整统计与图表迁移**：使用 Swift Charts 与原生组件实现所有已有模块与图表（系统健康分、概览趋势、热力图、CPU 趋势与 P/E 核/分布、GPU 趋势与分布/显存、内存构成与压力、网络吞吐与每日用量、磁盘吞吐与每日用量、功耗、电池与健康度历史、热压力与风扇、应用排行与高负载告警、事件流、数据明细表、洞察建议、本机硬件清单与右栏规格），并保持现有统计聚合语义。
- **实时读数轻量更新**：右栏实时状态由 `MonitorStore` 驱动局部更新，不触发整个历史报表重算。
- **生命周期与资源释放**：关闭报表窗口时销毁窗口、取消定时器与订阅、清空报表专用数据快照与图表状态，杜绝内存持续泄露与残留。
- **导出与按需打印**：保留独立单文件 HTML 导出能力（由 `StandaloneHTMLReportExporter` 按需直接写入目标 URL）；打印功能在用户明确触发时生成唯一临时文件并由 `TransientReportPrintSession` 调起 WebKit 打印操作，所有出口通过幂等清理释放引用并删除临时文件，不常驻 WebKit。

## Capabilities

### New Capabilities
- `native-statistics-report`: 原生 macOS 统计报表窗口、模块化交互导航、时间范围过滤、Swift Charts 图表渲染、应用排行与硬件规格展示及关窗资源释放。

### Modified Capabilities
- `html-report-export`: 将日常查看报表的展示机制从常驻 WKWebView 切换为原生窗口；HTML 生成收敛为仅在用户导出或打印时按需触发。

## Impact

- `HagimiMonitor/ReportWindowPresenter.swift`：重构为管理原生报表窗口的生命周期，负责原生窗口展示、状态重置、按需导出与临时打印。
- `HagimiMonitor/Statistics/StandaloneHTMLReportExporter.swift`：承担独立 HTML 模板组装与写入；原生窗口直接消费强类型报表模型。
- `HagimiMonitor/Views/Report/`：新增原生报表 SwiftUI 视图体系（侧栏/分段导航、时间范围选择器、各监控模块、图表组件、硬件右栏、本机硬件查看器等）。
- `HagimiMonitor/AppDelegate.swift`、`StatisticsSettingsView.swift`：报表唤起入口与锚点跳转机制无缝对接原生窗口。
- 内存与资源占用：打开报表不再拉起常驻 WebKit 进程，关闭后释放报表所有重型数据与视图层缓存。
