## MODIFIED Requirements

### Requirement: 报表一键打印与导出 PDF 交互
HTML 网页报表与原生报表窗口 SHALL 提供直观的「打印 / 导出 PDF」能力，并支持在 App Store 沙盒环境与外部浏览器中正常运行。

#### Scenario: 内置报表窗口点击打印按钮
- **WHEN** 用户在原生报表窗口点击工具栏中的「打印」按钮
- **THEN** 应用按需生成带有浅色打印样式的 HTML，并临时调起用于打印的 WebKit 打印操作 `NSPrintOperation` 模态面板
- **AND** 打印完成、取消、导航/脚本失败、重复请求或父窗口关闭时都执行一次幂等 session cleanup
- **AND** cleanup 停止加载、断开 delegate、清除关联对象、释放 `WKWebView` 引用并删除本次唯一临时文件；系统 helper 退出时间不作为应用对象释放的唯一判断

#### Scenario: 外部浏览器中点击打印按钮
- **WHEN** 用户在外部浏览器中点击报表导航栏中的「打印 / 导出」按钮
- **THEN** 页面调用 `enterPrintMode()` 并调用 `window.print()` 唤起浏览器原生打印与 PDF 保存窗口
- **AND** 触发 `afterprint` 事件后调用 `exitPrintMode()` 还原图表色彩

### Requirement: 原生独立报表窗口与沙盒兼容导出
应用 SHALL 提供沙盒兼容的原生独立报表查看窗口（`ReportWindowPresenter`），避免日常查看依赖常驻 WebKit 进程，并保留独立的 HTML 文件导出能力。

#### Scenario: 打开详细报表
- **WHEN** 用户在数据统计设置中点击「查看详细报表」
- **THEN** 应用直接打开原生报表窗口呈现数据
- **AND** 窗口提供工具栏，包含刷新、打印、另存为 HTML 文件功能

#### Scenario: 另存为 HTML 文件
- **WHEN** 用户在原生报表窗口工具栏点击「另存为 HTML」
- **THEN** 独立 HTML 导出器按需生成独立单文件 HTML 报表，并弹出系统 `NSSavePanel` 供用户选择导出路径
- **AND** 导出器直接写入用户选择的目标 URL，不创建或复用 Application Support 中的固定报表缓存
- **AND** 若保存失败，以 Sheet 或模态框形式呈现原生 `NSAlert` 错误提示
