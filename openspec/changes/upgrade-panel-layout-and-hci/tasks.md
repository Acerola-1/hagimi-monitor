# Tasks

> **当前状态**：主面板排版、全象限配色、方案 B 展开网格及验收后 4 项交互精修已全部定稿落地并完成双渠道目测与测试验证；待正式提交后按需执行 `openspec archive`。

## 1. 第一阶段：排版减噪与微交互修复（共用基线）

- [x] 1.1 去除主面板行头（`MetricGlassRow`、`NetworkGlassRow`、`BatteryGlassRow`、`BluetoothGlassRow`、`DisplaySection`）与设置预览 `ModuleRowPreview` 中模块名后的冗余冒号（修复直连态 `显示器:` 悬空冒号），按当前语言对齐左侧模块名槽宽；已完成 `HagimiMonitor` / `HagimiMonitorDirect` 构建与行高布局测试。
- [x] 1.2 优化 `BluetoothGlassRow` 右侧设备图标槽宽度自适应及 `PairedHeaderReadings` 视觉对比，并修改 `MetricDetailGrid` 的 `splitValueUnit` 使 `%` 紧贴数字且保持同权重，在 `MetricSampleCatalog` / `MetricPreviewTile` 同步口径；已同步完成并构建通过。
- [x] 1.3 将 `MetricCopyFeedback` 点击与悬停热区扩展至整个指标格（热压力合并格统一整格复制，避免局部反馈文案溢出），按 `属性: 数值` 格式写入剪贴板并在格内原地切换短暂 `✓ 已复制` 状态（配备贴合 `7pt` 连续圆角的 `0.75pt` 细描边，禁用系统直角焦框），整合 tooltip 与右键复制菜单并防护长按拖拽误触发。
- [x] 1.4 调整 `CPUCoresDetail` 悬停交互，改为目标圆环轻量高亮 + 底部 `P/E/S` 汇总栏采用 `180ms` 退出防抖与原地 `0.16s` 交叉淡入展示当前核标识与占用率（如 `P2 · 45%`），核间滑过不回闪汇总栏，移出后恢复分组均值。
- [x] 1.5 将顶栏统计入口图标更换为直观图表图标（`chart.xyaxis.line`），并为 `SYSTEM · LIVE` 标题区保留简洁稳定的「双击展开或收起 / Double-click to expand or collapse」提示（不增设顶栏展开按钮）；已补齐 `Localizable.xcstrings` 中英译文。

## 2. 第二阶段：全象限配色与表面层多版本对照与裁决

- [x] 2.1 在 `MonitorPalette`、`NativePanelCardBackdrop`、`CompatibleGlassContainer` 与 `NativePanelLayerView` 中通过 `#if DEBUG` 临时启动参数 `-HagimiPaletteVariant` 实现**浅色活力主题 3 套完整候选**（`v1` 清透亮白磨砂 + 浅色专调高纯度前景、`v2` 前景/底色解耦淡彩玻璃 + 按色相控浓度归零、`v3` 纯白磨砂 + 22×22 图标柔光底托 + warning/critical 微弱光晕）；`PowerPanelLayoutTests` 与双渠道构建已通过。
- [x] 2.2 在同一 `#if DEBUG` 对照框架下实现**平衡（浅/深）与活力（深）的优化候选（`refined` vs 原版 `baseline`）**：拆开平衡主题 `memory` / `network` 及 `gpu` / `bluetooth` / `display` 撞车色相、建立明暗分治模块色与 `severityTint`、去掉浅色 `#3C485A` 冷蓝偏色、补齐浅/深色卡片 `0.5pt` 细描边、提亮深色 `trackFill`/`rowGrooveFill` 与拉开主次层级，同时保留活力深色暗底发光基调；`PowerPanelLayoutTests` 与 `UXAcceptanceRenderingTests` 已通过。
- [x] 2.3 使用 `TemporaryInstanceOverrides`（`-HagimiInstanceLabel` + `-HagimiPaletteVariant`）并排拉起三联与双联对照实例，已完成用户逐象限目测裁决。
- [x] 2.4 按用户裁决结果固化最终四象限配方至 `MonitorPalette`、`NativePanelCardBackdrop`、`CompatibleGlassContainer` 与 `NativePanelLayerView`，并已彻底删除 `#if DEBUG` `-HagimiPaletteVariant`、`openPinned`、`pinnedSlot` 临时参数与淘汰分支。

## 3. 第三阶段：展开指标网格 A/B 双方案并行实现与 Worktree 对照

- [x] 3.1 在主工作区（未提交实验改动的现状）实现方案 A：将 `MetricDetailGrid` 与 `ModuleRowPreview` 拆分为「上下堆叠 KPI 微卡片（2/3 列自适应无空洞）+ CPU `闲置/系统/用户` 微型占比条 + 规格/诊断整行」，更新 `MetricCellSizing`、`SingleHostLayoutComponents`、`MetricSampleCatalog`、`MetricWidthAuditTests` 与 `SingleHostLayoutTests` 并验证相关测试通过。
- [x] 3.2 通过 detached worktree `tmp/worktree-grid-b` 实现方案 B：升级 `StaticMetricSizing` 为「面板宽度档位（300/340/460pt）× 语言 × 99% 分位合理最坏值」纯函数（保留极值缩放兜底），修改 `PanelMetricColumnsLayout` 使落单半格自动撑满所在行并同步 `MonitorPanelView` / `ModuleRowPreview` / `MetricWidthAuditTests` / `SingleHostLayoutTests`，在独立 `tmp/dd-grid-b` 下完成验证。
- [x] 3.3 在中英文双语下并排运行 `方案A` 与 `方案B` 常驻对照窗，用户已完成对比并选定 **方案 B**。
- [x] 3.4 已将 **方案 B** 收拢至主工作区（并保留热压力格右键复制），移除 `tmp/worktree-grid-b` 与 `tmp/dd-grid-b`，收敛 `MetricWidthAuditTests` 与 `SingleHostLayoutTests` 为单一正式方案 B。

## 4. 第四阶段：人机交互闭环升级（基于胜出基线）

- [x] 4.1 为可展开与不可展开模块行头增加克制的悬停可展开 chevron 提示（不可展开模块行显示静态禁止/无明细提示且不显示 chevron，保持 `panelRowHeaderHeight = 34` 与右缘槽位稳定）。
- [x] 4.2 透传 `pid` 至 `TopProcessRowData` 并在五类资源与电源 TOP 5 进程行接入悬停/原生 `NSMenu` 右键快捷操作（交互、右键菜单展开与退出确认期间按 `pid` 冻结列表排序并按值快照目标信息，防止 1Hz 刷新导致目标漂移）：双渠道支持前置激活 GUI 应用、复制名称/PID 与访达显示；仅 `DIRECT_DISTRIBUTION` 支持带二次确认的温和退出（校验 PID 存活与身份防复用，排除系统关键进程与本应用）；`TopProcessRowTests` 相关安全校验与排序冻结用例已通过。
- [ ] 4.3 评估开放 `300~460pt` 面板宽度调节入口并接入 `FluidPanelController` / `PinnedPanelController` / `NativePanelLayerView` 与静态断点布局；若后续接入，补齐设置项持久化与不同宽度档位下的 `PanelGeometryTests` 验收。

## 5. 第五阶段：双渠道整体验收与文档同步

- [x] 5.1 已在最终收拢代码上完成 `HagimiMonitor`（App Store）与 `HagimiMonitorDirect`（Direct）双渠道编译与 `HagimiMonitorDirect` 测试验证。
- [x] 5.2 已完成 `HagimiMonitor` 与 `HagimiMonitorDirect` 双渠道实机启动与目测复核（涵盖全象限配色、方案 B 展开网格、进程冻结与右键快照、整格复制圆角反馈、CPU 核心防抖淡入）。
- [x] 5.3 已同步更新 `DESIGN.md`（并清理 `PinnedPanelController` 冷启动点击响应修复），并通过 `openspec validate upgrade-panel-layout-and-hci --strict` 校验。

## Workflow follow-up

- 全部实施与目测验收完成后，由用户确认再执行 `openspec archive upgrade-panel-layout-and-hci` 并同步收敛主 `openspec/specs/`（含与 `panel-long-press-reordering` 差异条款的统一）。
