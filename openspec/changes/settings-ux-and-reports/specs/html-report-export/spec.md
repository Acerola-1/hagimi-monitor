## Purpose

Defines the print stylesheet optimizations and user export actions for the standalone hardware HTML report, ensuring clean PDF and physical print outputs.

## ADDED Requirements

### Requirement: 网页报表打印样式优化
HTML 网页报表（`ReportTemplate.html`）SHALL 包含专用的 `@media print` 样式定义，确保在浏览器触发打印或导出为 PDF 时，输出具有高可读性且节省耗材的浅色排版。

#### Scenario: 浏览器打印预览排版
- **WHEN** 用户在浏览器中调起打印预览（Cmd + P）或执行导出 PDF
- **THEN** 页面背景自动切换为纯白/浅色底色
- **AND** 极光光晕背景（`.aurora-glow`）与动态投影被隐藏
- **AND** 顶部粘性导航条（`.sec-nav`）、时间范围选择器与返回顶部按钮被隐藏
- **AND** 文本与图表网格以适合纸张/PDF 的高对比度深色渲染
- **AND** 关键图表与指标卡具有页面分页保护（`break-inside: avoid`），防止被截断在两页之间

### Requirement: 报表一键打印与导出 PDF 交互
HTML 网页报表与内置报表窗口 SHALL 提供快捷直观的「打印 / 导出 PDF」能力，并支持在 App Store 沙盒环境与外部浏览器中正常运行。

#### Scenario: 内置报表窗口点击打印按钮
- **WHEN** 用户在内置报表窗口点击顶部导航栏中的「打印 / 导出」按钮或工具栏打印图标
- **THEN** 网页调用 `enterPrintMode()` 预热切换图表为浅色高对比模式
- **AND** 通过 `window.webkit.messageHandlers.hagimiPrint` 向宿主发送消息，宿主唤起原生 `NSPrintOperation` 模态打印面板
- **AND** 打印完成后调用 `exitPrintMode()` 还原图表色彩

#### Scenario: 外部浏览器中点击打印按钮
- **WHEN** 用户在外部浏览器中点击报表导航栏中的「打印 / 导出」按钮
- **THEN** 页面调用 `enterPrintMode()` 并调用 `window.print()` 唤起浏览器原生打印与 PDF 保存窗口
- **AND** 触发 `afterprint` 事件后调用 `exitPrintMode()` 还原图表色彩

### Requirement: 原生独立报表窗口与沙盒兼容导出
应用 SHALL 提供沙盒兼容的独立报表查看窗口（`ReportWindowPresenter`），避免 App Store 沙盒下外部浏览器无权访问容器内部文件的阻断问题。

#### Scenario: 打开详细报表
- **WHEN** 用户在数据统计设置中点击「查看详细报表」
- **THEN** 应用生成当前时段统计 HTML 并通过内置 `WKWebView` 窗口打开
- **AND** 窗口提供 Unified 工具栏，包含刷新、打印、另存为 HTML 文件功能

#### Scenario: 另存为 HTML 文件
- **WHEN** 用户在报表窗口工具栏点击「另存为 HTML」
- **THEN** 弹出系统 `NSSavePanel` 供用户选择导出路径
- **AND** 若保存失败，以 Sheet 或模态框形式呈现原生 `NSAlert` 错误提示
