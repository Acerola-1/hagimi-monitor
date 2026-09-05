## Context

参考 `proposal.md`。当前设置窗口宽度锁死为 600pt，导致右侧主卡片可用净宽仅 363pt，在 3 列指标格下文字净宽仅 81pt，强制引发文字重叠与缩放。同时，进入存储管理页面时由于侧栏未匹配 tag 产生空白选中 Bug；菜单栏指标设置上下双列表冗余堆叠达 12 行；HTML 报表缺乏打印适配与快捷导出手段。

## Goals / Non-Goals

**Goals:**
- 将设置窗口固定宽度提升至 660pt，彻底解除卡片与指标格的排版压迫。
- 侧栏按 HIG 标准划分为清晰的 4 个语义分组（通用、监控、扩展、关于），消除 13 项长列表认知疲劳。
- 保持子页面 `.storage` 导航期间侧栏对「数据统计」的高亮激活，点击侧栏「数据统计」可直接返回，修复空白选中 Bug。
- 将 SSD 模块名称统一为「磁盘」/「Disk」，消除与应用「存储管理」同名歧义。
- 将菜单栏指标的“勾选”与“排序”合并为单一内联列表。
- 实现独立原生报表查看窗口（`ReportWindowPresenter`），彻底解决 App Store 沙盒下外部浏览器无法读取容器内报表（`NSURLErrorDomain: -3001`）的阻断缺陷。
- 为 HTML 网页报表落地「Cupertino Specimen · 苹果原厂硬件规格档」视觉风格，提供 `@media print` 浅色无光晕打印排版、原生 `NSPrintOperation` 打印/导出 PDF 桥接，以及另存为独立 HTML 文件能力。

**Non-Goals:**
- 不更改底层时序数据库结构与采样算法。
- 不引入额外第三方库。

## Decisions

### 1. 窗口宽度增至 660pt
- **决策**：在 `SettingsWindowPresenter.swift` 中将 `fixedWidth` 常量从 600 改为 660pt。
- **依据**：侧栏占 164pt，分割线 1pt，水平外边距 72pt（36pt * 2），内容卡片可用宽度由 363pt 跃升至 423pt。3 列卡片单格净宽提升至 101pt 以上，彻底解决文字碰撞与被迫堆叠缩放。
- **备选方案**：压缩 `SettingsPage` 的横向 padding（如从 36 减到 16）。但侧边距过小会破坏 macOS Liquid Glass 的留白与呼吸感，扩大窗口宽度是更原生的做法。

### 2. 侧栏路由高亮保持与语义分组
- **决策**：
  1. `SettingsSidebar` 的 `List` 分为 4 个 `Section`：常规（`general`）、监控（各 `module` 及 `displayModule`）、扩展（`quickTools`、`statistics`）、关于（`about`）。
  2. 侧栏导航绑定使用衍生投影（Proxy Selection）：当全局路由处于 `.storage` 时，侧栏的高亮项保持投影到 `.statistics`；在 `.statistics` 条目上附加点击手势，确保用户在存储子页直接点击侧栏「数据统计」能顺利切回。
  3. 将 `MonitorKind.storage` 的本地化标题从「存储」更改为「磁盘」，英文由 "Storage" 更改为 "Disk"。
- **依据**：符合 macOS 标准主从视图惯例，彻底修复进入二级管理页时侧栏选区消失的不稳定感，同时理清硬件与应用数据的概念分界。

### 3. 菜单栏指标单列表重组
- **决策**：废弃 `GeneralSettingsView` 中的 `MenuBarMetricOrderRow` 独立展示块。采用单列表：已勾选项目靠前并展示排序手柄/上下微调，未勾选项目在后展示禁用态或置灰，单列表内完成勾选上限（4项）及排序。
- **依据**：消除上下双列表的认知鸿沟与多达 12 行的滚动浪费。

### 4. HTML 报表「Cupertino Specimen」规格排版与 `@media print` 适配
- **决策**：
  1. 采用 Apple 原厂 Hardware Diagnostic Dossier 设计语言（Cupertino Specimen）：工业级规格信息密度、等宽参数矩阵、微弧高对比数据卡片与精致 SVG 语义角标。
  2. 在 `ReportTemplate.html` 的 `<style>` 中追加 `@media print`：
     - 背景强制纯白（`background: #ffffff !important;`），文字设为 `#1d1d1f`。
     - 隐藏极光环境光晕（`.aurora-glow`）、粘性导航条（`.sec-nav`）、时间范围选择器与返回顶部按钮。
     - 卡片增加 `break-inside: avoid;`，边框转为浅灰实线（`1px solid #e5e5e7`），移除暗黑模式发光阴影。
  3. 页面内置 `enterPrintMode()` / `exitPrintMode()`：在打印前将所有图表 Canvas 背景动态重绘为浅色底，打印完成后无缝还原。

### 5. 原生报表窗口（ReportWindowPresenter）与 WebKit 桥接
- **决策**：
  1. 新增 `ReportWindowPresenter`：使用 `NSWindow` + `WKWebView` 呈现报表，窗口支持标准 macOS 缩放与记忆尺寸，标题栏集成 Unified 原生工具栏（包含刷新、打印、另存为 HTML 文件）。
  2. **沙盒兼容依据**：App Store 版本开启了 App Sandbox，导出的 HTML 位于 `~/Library/Containers/.../Application Support` 下。外部进程（Safari/Chrome）因沙盒安全隔离无法直接读取（报错 `NSURLErrorDomain: -3001`）。内置 `WKWebView` 能安全读取容器内沙盒数据，完全消除沙盒阻断。
  3. **打印链路实现**：macOS 上的 `WKUIDelegate` 并无打印回调，且内嵌 `WKWebView` 的 `window.print()` 为空操作。因此通过 `WKScriptMessageHandler`（`hagimiPrint`）桥接网页中的 `#nav-print` 按钮，调用宿主原生 `webView.printOperation(with: printInfo).runModal(for: window, ...)`，调出系统打印面板并支持「另存为 PDF」；在外部浏览器打开时降级回退至 `window.print()`。
  4. **导出文件**：通过原生 `NSSavePanel` 将报表另存为任意用户目录下的独立 HTML 文件，并附带完整的错误提示弹窗（`NSAlert`）。

## Risks / Trade-offs

- **[Risk]** 660pt 宽度在极小屏幕（如 MacBook 12 寸或外接竖屏）上是否超宽？
  - **Mitigation**：macOS 最小支持分辨率宽度通常在 1280pt 以上，660pt 占用空间极小，在所有受支持的 Mac 设备上均可轻松容纳。
- **[Risk]** 侧栏 `Section` 在自绘模糊材质下的层级背景穿透问题。
  - **Mitigation**：使用标准 SwiftUI `Section` 配合系统侧栏默认样式，保持背景透明度与统一的材质模糊。
