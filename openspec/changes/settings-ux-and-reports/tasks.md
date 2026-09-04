## 1. 设置窗口尺寸与排版优化

- [x] 1.1 将 `SettingsWindowPresenter.swift` 中的窗口固定宽度 `fixedWidth` 由 600 改为 660pt，并通过构建验证设置窗口基础尺寸
- [x] 1.2 验证 `SettingsPage` 与 `StatisticsSettingsView` 在 660pt 宽度下的 3 列指标卡排版，确认各语言下文字与数值无挤压与溢出

## 2. 侧边栏重构与路由 Bug 修复

- [x] 2.1 重构 `SettingsSidebar.swift`，将 13 个条目划分为常规、监控模块、扩展功能、关于 4 个语义 `Section`，并验证侧栏视觉层级
- [x] 2.2 在 `SettingsSidebar` 中建立路由选择投影，并在 `.statistics` 添加点击手势，确保导航至 `.storage` 时保持「数据统计」高亮且点击可直接切回，彻底消除空白无选中态
- [x] 2.3 更新 `MonitorKind.storage` 的本地化标题为「磁盘」/「Disk」，避免与应用「存储管理」同名歧义，并更新对应 `Localizable.xcstrings`

## 3. 菜单栏指标单列表重组

- [x] 3.1 在 `GeneralSettingsView.swift` 中废弃独立的排序列表，将指标选择与顺序调整整合为单一内联列表
- [x] 3.2 实现已勾选指标的内联排序（支持上下调整或拖拽）并保持最多勾选 4 项约束，验证菜单栏展示顺序即时响应变更

## 4. 原生报表窗口与打印/导出能力

- [x] 4.1 在 `ReportTemplate.html` 中重构为「Cupertino Specimen」原厂硬件规格风格，并添加 `@media print` 专属打印样式与 `enterPrintMode()` / `exitPrintMode()` 浅色图表动态重绘
- [x] 4.2 实现 `ReportWindowPresenter` 原生 `WKWebView` 独立查看窗口与 Unified 原生工具栏，彻底解决 App Store 沙盒下外部浏览器无法读取容器文件（`NSURLErrorDomain: -3001`）问题
- [x] 4.3 实现 WebKit 消息通道 `hagimiPrint` 与原生 `webView.printOperation(with:)` 桥接，并在工具栏提供「另存为 HTML」保存面板与错误弹窗
- [x] 4.4 验证内置窗口打印/另存为 PDF、浏览器打印预览及 HTML 文件导出的完整性与版面稳定性

## 5. 综合构建与回归验证

- [x] 5.1 运行测试套件（Direct scheme test），确保 `MetricWidthAuditTests` 等现有测试全部通过
- [x] 5.2 分别构建 HagimiMonitor 与 HagimiMonitorDirect 并在暗黑/明亮双主题下检查设置页与报表交互正常
