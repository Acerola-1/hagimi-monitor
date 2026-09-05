## Why

当前 HagimiMonitor 的设置窗口与报表体系在 UI/UX 与工程上存在若干核心体验缺陷与排版瓶颈：
1. **窗口死锁 600pt 导致卡片内容区极度拥挤**：扣除 165pt 侧栏与 72pt 水平边距后，右侧卡片内净宽仅 363pt，3 列指标卡单格文字净宽只有 81pt，强制全部降级为垂直堆叠并触发 0.75 缩放，中英文下排版逼仄。
2. **侧边栏导航选中态丢失 Bug 与概念冲突**：点击数据统计底部的“存储管理”跳转至 `.storage` 时，侧栏缺少对应 tag 导致高亮彻底消失；且监控项中的 SSD「存储」与应用数据库「存储管理」同名撞车。
3. **菜单栏指标设置双列表冗余**：勾选项与排序项分裂为两个垂直列表，选满 4 项时堆叠达 12 行，占用空间过大且操作脱节。
4. **HTML 报表打印与导出能力缺失**：报表缺乏 `@media print` 打印样式与快捷导出/打印交互，暗黑毛玻璃背景在打印为 PDF 时造成严重排版紊乱。

本次改动旨在理顺设置窗口尺寸与导航心智，消除高危交互 Bug，并赋予 HTML 报表完整的离线打印与导出能力。

## What Changes

- **设置窗口尺寸与布局调整**：
  - 将固定窗口宽度从 `600pt` 增至 `660pt`，卡片可用宽度增加 60pt，彻底解除 3 列网格排版压迫。
- **侧边栏结构重构与路由修复**：
  - 修复 `.storage` 路由下侧边栏高亮丢失问题，在侧栏中使「数据统计」保持激活态，或将存储管理收纳进统计同级分段控制。
  - 侧栏 13 项增加语义化分组（通用设置、监控模块、扩展功能、关于等），避免扁平列表认知过载。
  - 将硬件 SSD 监控项标题命名为「磁盘」/「Disk」，消除与应用「存储管理」同名概念冲突。
- **菜单栏指标配置体验整合**：
  - 将「勾选展示」与「显示顺序」两个独立列表合并为单一内联列表，勾选项支持直接拖拽排序或内联调整，大幅缩减页面纵向冗余卡片。
- **HTML 报表打印与导出支持及原生独立预览窗口**：
  - 针对 App Store 沙盒环境下外部浏览器无法直接读取容器内 `Application Support` 报表文件（`NSURLErrorDomain: -3001`）的核心阻断，实现内置原生 `ReportWindowPresenter`（基于 `WKWebView`），提供沉浸式独立报表预览、原生工具栏（刷新、打印/导出 PDF、另存为 HTML）。
  - 在 `ReportTemplate.html` 中引入专用 `@media print` 样式：强制白色/浅色打印底色、隐藏极光阴影、粘性导航条与无用交互组件。
  - 在报表顶栏增加「打印 / 另存为 PDF」按钮，通过 WebKit 消息桥接（`hagimiPrint`）唤起原生 `NSPrintOperation`，在外部浏览器打开时降级为 `window.print()`。

## Capabilities

### New Capabilities
- `html-report-export`: HTML 网页报表的打印排版样式（`@media print`）、WebKit 原生报表窗口（`ReportWindowPresenter`）、另存为 HTML 文件导出，以及一键打印/导出 PDF 交互能力。

### Modified Capabilities
- `settings-window`: 设置窗口宽度放宽至 660pt、侧栏分组及 `.storage` 选中态维持、SSD 模块重命名为磁盘、以及菜单栏指标配置单列表重排。

## Impact

- **Affected Files**:
  - `HagimiMonitor/SettingsWindowPresenter.swift`: 窗口宽度约束 `fixedWidth: 660`。
  - `HagimiMonitor/ReportWindowPresenter.swift`: 原生 WKWebView 报表查看窗口、系统工具栏与打印/导出链路。
  - `HagimiMonitor/Statistics/StatisticsReportBuilder.swift`: 报表数据生成与调起原生查看器。
  - `HagimiMonitor/Views/Settings/SettingsSidebar.swift`: 分组结构、路由 tag 保持、磁盘命名文案。
  - `HagimiMonitor/Views/Settings/SettingsRootView.swift`: 路由映射与高亮维持。
  - `HagimiMonitor/Views/Settings/GeneralSettingsView.swift`: 菜单栏指标单列表重构。
  - `HagimiMonitor/Resources/ReportTemplate.html`: `@media print` 样式、Cupertino 规格风格与打印脚本桥接。
  - `HagimiMonitor/Localizable.xcstrings`: 涉及的侧栏分组标题、磁盘文案与报表窗口/打印本地化。
- **Dependencies & Compatibility**: 无新增第三方依赖，保持完全沙盒合规与 Direct 兼容。
