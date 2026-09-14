## Context

当前报表窗口采用 `NSWindow` + `NSHostingView<NativeReportView>` 承载。日常查看不创建 WebKit；独立 HTML 只在用户主动导出或打印时按需生成。

参见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 将日常报表查看全面迁移为 macOS 原生窗口（AppKit 窗口生命周期 + SwiftUI 视图 + Swift Charts / 原生组件）。
- 消除常驻 `WKWebView`，日常打开不再启动 WebKit 辅助进程，关闭窗口后彻底释放报表持有的重型数据模型与图表资源。
- 采用类型明确的 Swift 数据模型（`ReportSnapshot` / `ReportRangeData` / `StatisticsRow` 等），复用现有 `StatisticsHealthScore`、`StatisticsOverviewModel` 与聚合口径，保证数据语义一致。
- 完整保留现有功能：时间范围选择、各指标历史趋势与分布、P/E 核、显存、网络/磁盘吞吐与每日柱状图、电池健康历史、应用排行与高负载告警、事件流、明细表、洞察建议、各硬件模块侧栏与当前模块实时状态、本机全景规格。
- 保留独立 HTML 导出能力；按需打印临时调起 WebKit 操作并在完成后销毁。
- 支持深浅外观跟随、中英双语、经典毛玻璃质感。

**Non-Goals:**
- 不改变数据库表结构与底层采样存储格式。
- 不引入第三方图表库，常规图表采用 Swift Charts，热力图等特异结构使用 SwiftUI Canvas / 原生网格。
- 不逐像素复刻网页动画，采用符合 macOS 规范的原生交互与布局。

## Decisions

### 1. 窗口与生命周期管理
- **决策**：由 `ReportWindowPresenter` 统一管理原生 `NSWindow`。当用户关闭窗口时，`NSWindowDelegate.windowWillClose` 触发清理流程：取消实时刷新定时器、取消后台聚合任务、解绑主题订阅、清空数据与视图模型引用，并将窗口实例置空以彻底释放。
- **备选方案**：保留静态单例窗口与常驻视图。劣势：即使停止定时器，视图树和图表缓存依然常驻内存，无法达成关窗释放目标。

### 2. 数据流与职责边界
- **决策**：
  1. **后台拉取与快照**：打开窗口时在 `Task.detached(priority: .userInitiated)` 中拉取 `snapshot`、`processStore` 数据与 `HardwareInventory`，生成不可变的 `ReportSnapshot`。
  2. **范围与指标聚合**：范围切换（今日/近7天/近30天/近1年/自定义）在后台进行行过滤与聚合，产出强类型的 `ReportActiveRangeModel`，主线程仅绑定渲染结果。
  3. **实时状态局部更新**：右栏实时状态由 `ReportLiveHardwareSource` 每秒读取当前硬件模块的 `ReportLiveReadings`，只发布变化后的字典，不触发历史报表重新聚合。窗口不可见、完全遮挡、最小化、应用隐藏或当前模块没有实时栏时不运行 timer；恢复可见或切换模块后立即取一帧。
- **备选方案**：实时刷新连带重新查询数据库。劣势：严重浪费 CPU 并引发图表无意义重绘。

### 3. 图表与视觉呈现方案
- **决策**：
  - 趋势线、堆叠面积、峰值虚线、柱状图采用 **Swift Charts**（`LineMark`, `AreaMark`, `BarMark`, `RuleMark`），结合 `chartXSelection` 或手势实现精确的坐标轴与悬停读数。
  - 负载分布（极轻/轻度/中度/繁重/极限）采用分段横条/环形指示器。
  - 7×24 小时活动热力图采用 SwiftUI 网格组件，绘制星期×小时单元格。
  - 配色全面复用 `MonitorPalette` 和系统语义色，支持明暗模式自适应。
- **备选方案**：继续在原生窗口内嵌小尺寸 WebKit 或纯 CoreGraphics。劣势：增加复杂度与内存开销，违背原生化初衷。

### 4. 图标与资源处理
- **决策**：
  - SF Symbols 直接通过原生 `Image(systemName:)` 渲染，继承面板与菜单栏的统一映射。
  - 原生窗口中的模块、系统进程和应用图标使用 SF Symbols / 原生图标语义；窗口关闭时释放报表作用域缓存。
  - 独立 HTML 导出器继续内嵌必要的 SF Symbols 位图、应用图标和进程图标，以保持单文件离线可读；这些资源不进入日常窗口路径。

### 5. 导出与打印机制
- **决策**：
  - **导出**：保留独立单文件 HTML 导出器 `StandaloneHTMLReportExporter`，仅在用户点击「另存为 HTML」时按需生成并直接写入 `NSSavePanel` 选中的目标 URL，不创建 Application Support 报表缓存。
  - **打印**：当用户点击「打印」时，为本次请求生成唯一临时 HTML 并由 `TransientReportPrintSession` 挂载瞬时 `WKWebView` 调起 `NSPrintOperation`。成功、取消、导航/脚本失败、重复请求和父窗口关闭都汇入幂等 `finish()`，停止加载、断开 delegate、清关联对象、释放引用并删除临时文件。系统 WebKit helper 的退出时间不作为对象释放的同步生命周期信号；原生分页打印尚未替换该路径。

## Risks / Trade-offs

- [大量历史数据在 Swift Charts 中的绘制性能] → 根据范围跨度自动降采样（今日分钟/近月小时/近日），限制单图表数据点在合理区间（例如 100~500 点），确保滚动流畅与手势灵敏。
- [多列布局在较小屏幕上的空间占用] → 延续主列 + 硬件右栏的双列设计，支持左右比例自适应及垂直滚动。
- [关闭窗口后的异步竞态] → 所有后台任务检查 Task 状态或 weak 引用，防止关窗后任务完成重新触发主线程持有或更新。

## 2026-09-14 用户追加的 UI 决策

报表导航改用 macOS 27 的 TabsPickerStyle，使用已安装 Xcode 27 beta 编译，以运行时 availability 保留 macOS 15/26 的 segmented 回退。该决定替代阶段 D.5 基于旧 SDK 的临时方案；不修改菜单栏面板的材质。概览以指标与历史趋势为视觉主体，压力评分收敛为辅助区域，保留评分维度和缺失原因。详见根目录 DESIGN.md 及 docs/development/native-report-ui-contract.md。

## 2026-09-14 原生报表摘要与日期范围补充

- 概览评分收敛为 `ReportCardView` 表面上的紧凑横向摘要，覆盖率由 `ReportDataAggregator.coverageRatio` 从有效采样秒数计算并直接进入 `ReportActiveRangeModel`；没有有效范围或样本时保持 nil。
- 当前秒数评分只显示内存压力 60% 与热压力 40% 的实际维度和公式。旧历史行出现 CPU/GPU 维度时标明“历史评分口径”，并展示实际维度，避免套用新公式。
- `ReportCustomRangePicker` 打开时从当前范围同步草稿，使用一个原生 graphical 日历和起止端点切换；取消不提交，应用按自然日 `[start, nextDay(end))` 提交，结束日期限制为今天。
