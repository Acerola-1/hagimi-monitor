# 主面板布局、交互与全象限视觉升级（含配色多方案与网格 A/B 对照）

## Why

1. **展开指标网格与静态宽度策略的结构矛盾**：`MetricDetailGrid` 目前采用「标签左 · 数值右」单行左右对顶布局，并由 `StaticMetricSizing` 按未启用的 `panelMinWidth`（`300pt`）推导 `halfCellContentWidth = 120pt`（当前宿主实际固定为 `panelIdealWidth = 340pt`，实际半格内容宽约 `134pt`），叠加按极端极值声明的 `WorstValue`（如 `cpu.uptime` 的 `"888天88小时"`），导致 `热压力`、`启动时间` 等常见指标被迫独占整行并留下大段空白灰条；同时 `MetricGridPacking` / `PanelMetricColumnsLayout` 在用户隐藏指标或拖拽排序后遇到落单半格会留下右侧空白缺口。另一方面，随 1Hz 实时采样值动态重排会引发严重布局抖动（CLS），必须保留跨采样帧稳定不横跳的刚性前提。
2. **主面板视觉噪点与微排版不一致**：全屏多层圆角底色嵌套过密；9 个模块行头存在冗余冒号及左侧扫描基线不齐（直连渠道 `DisplaySection` 在显示设备读数时甚至出现悬空 `显示器:`）；`BluetoothGlassRow` 右侧宽槽内仅浮着单个小图标；`splitValue` 拆分导致同一张卡片内 `%` 呈现多种间距与字重；`CPUCoresDetail` 悬停气泡（`.offset(y: ...)`）直接遮挡下方 `P / E` 分组汇总栏。
3. **可发现性与操作闭环不足**：折叠行与不可展开行（如单风扇）缺少状态提示；顶栏双击 `SYSTEM · LIVE` 全部展开/收起隐蔽且右上角统计入口图标（`chart.bar.doc.horizontal`）辨识度偏弱；`MetricCopyFeedback` 点击热区仅限于右侧数值文本且 `.overlay(alignment: .topTrailing)` 成功浮层会遮盖自身；五类资源及电源 TOP 5 进程榜为只读静态列表，缺少切回前台/定位/退出的快捷闭环。
4. **全象限配色与表面材质系统性失衡**：
   - **活力 · 浅色**：`vibrantModuleTint` 未做明暗分治，暖色（CPU `#F97316`、磁盘 `#B28600`）在白色毛玻璃底座上冲白发粉发脏；全色相共用 `vibrantGlassOpacity = 0.08` 且展开区 `rowTintFaintOpacity = 0.02` 残留色雾；`trackFill` / `rowGrooveFill` 采用偏冷蓝的 `#3C485A` 叠加在暖色卡片上触发冷暖互脏；浅色卡片缺少物理细描边，被迫靠整卡泼色撑轮廓。
   - **平衡 · 浅/深**：`balancedModuleTint` 同样未分明暗，9 个模块中有 6 个挤在蓝青系且 `memory`（`#42A39A`）与 `network`（`#43A6A0`）几乎同色撞车，`gpu` / `bluetooth` / `display` 三蓝接近；浅色下多枚图标/图表对比度偏淡（约 `2.0–2.9:1`），`severityTint` 绿/黄文字在浅色玻璃上低于 `3:1`。
   - **深色共通（平衡 · 深 & 活力 · 深）**：`trackFill` / `rowGrooveFill` 仅 `white @ 0.03` 在暗底上近乎隐形；模块卡片缺少与底部按钮 `materialButtonStroke` 呼应的 `0.5pt` 细描边；`captionText`（`white @ 0.78`）与 `valueText`（`white @ 0.90`）主次层级跨度偏窄；`storage`（平衡 `#9A865E`、活力 `#B28600`）及 `severityTint` 在暗底上偏沉。

## What Changes

- **第一阶段：排版减噪与微交互修复（共用基线）**：
  - 主行去除模块名后冗余冒号（包含修复直连渠道 `显示器:` 悬空冒号），按当前语言对齐左侧模块名槽宽，使主数值纵向对齐；柔化行头右侧 `PairedHeaderReadings` 并优化 `BluetoothGlassRow` 图标槽比例。
  - 统一 `%` 等紧贴符号间距与字重，扩展 `MetricCopyFeedback` 点击热区至整格并改为格内原地 `✓ 已复制` 状态切换；`CPUCoresDetail` 悬停改用圆环高亮 + 底部 `P/E/S` 栏原地临时展示核编号与占用率；优化顶栏统计图标辨识度与全展开可发现入口。
- **第二阶段：全象限配色与表面层多版本对照与裁决**：
  - 实现 **浅色活力主题 3 套候选**（方向 1：清透亮白磨砂 + 浅色专调高纯度前景；方向 2：前景/底色解耦淡彩玻璃 + 按色相控浓度 + 展开归零；方向 3：纯白磨砂 + 图标柔光底托 + 高负载着底）。
  - 实现 **平衡（浅/深）与活力（深）的原版 vs 优化对照**：拆分明暗分治色表、拆开平衡主题撞车色相、去浅色冷蓝偏色、补齐明暗 `0.5pt` 细描边、将深色 `trackFill`/`rowGrooveFill` 提至清晰档并拉开 `captionText` 与 `valueText` 层级、适度提亮深色 `storage` 与 `severityTint`（同时保护活力深色既有暗底发光氛围）。
  - 利用 `#if DEBUG` 临时启动参数 `-HagimiPaletteVariant` 配合 `-HagimiInstanceLabel` 同屏并排展示供用户逐象限裁决，裁决后清理全部临时变体并收敛唯一正式实现。
- **第三阶段：展开指标网格 A/B 双方案并行对照（借助 Git Worktree）**：
  - 基于已完成第一、二阶段的定稿配色基线开展网格对照，确保两套网格都在最终满意的色彩下对比。共同铁律：绝不随 1Hz 实时采样值重排，保持单宿主自然高度测算、拖拽重排与 `ModuleRowPreview` 同源预览。
  - **方案 A（主工作区分支）**：拆分「紧凑上下堆叠 KPI 瓦片（支持 2/3 列）」与「无界长文本/诊断整行」，并将 CPU `闲置 / 系统 / 用户` 组合成语义构成条。
  - **方案 B（独立 Git Worktree）**：保留单行左右键值对，将静态跨度升级为「面板宽度档位 × 语言 × 合理 99% 分位最坏值」的容器断点纯函数，并使落单半格自动撑满所在行以消除缺牙空洞。
  - 双版本用独立 DerivedData 构建并同屏对比，待用户裁决后保留胜出方案、清理另一分支/worktree 并同步收敛主规范。
- **第四阶段：人机交互闭环升级（基于胜出基线）**：
  - 为可展开与不可展开模块行头增加克制的状态/悬停提示；为五类资源及电源 TOP 5 进程行增加悬停/右键快捷操作（双渠道前置激活/复制 PID/访达显示；仅 `DIRECT_DISTRIBUTION` 带二次确认与 PID 身份防复用校验的温和退出）；按需评估开放 `300~460pt` 面板宽度调节入口联动容器断点。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `monitor-panel`: 主行标题对齐与去冒号、状态与全部展开可发现性、指标格全格复制与原地反馈、CPU 逐核悬停原地反馈、TOP 进程行交互与渠道边界、展开网格布局契约调整及 A/B 对照验收关卡。
- `metric-width-audit`: 最坏值契约区分常规合理上界与极值兜底、静态判定从 300pt 锁死升级为适配选定网格形态（方案 A 堆叠分层预算 / 方案 B 容器宽度档位断点）的构建期审计。
- `color-scheme-settings`: 明暗分治的模块与状态调色、平衡主题跨模块色相区分、浅/深色表面层级与内衬辨识，以及全象限多版本对照裁决关卡。

## Impact

- **源码范围**：`HagimiMonitor/MonitorPanelView.swift`、`HagimiMonitor/MonitorPalette.swift`、`HagimiMonitor/Constants.swift`、`HagimiMonitor/Views/Panel/NativePanelCardBackdrop.swift`、`HagimiMonitor/Views/Panel/NativePanelLayerView.swift`、`HagimiMonitor/Views/CompatibleGlassContainer.swift`、`HagimiMonitor/Views/Panel/MetricCellSizing.swift`、`HagimiMonitor/Views/Panel/SingleHostLayoutComponents.swift`、`HagimiMonitor/Views/Panel/DisplaySection.swift`、`HagimiMonitor/Views/Panel/RowHeaderPills.swift`、`HagimiMonitor/Views/Panel/PanelReorderInteraction.swift`、`HagimiMonitor/Views/Settings/ModuleRowPreview.swift`、`HagimiMonitor/Views/Settings/MetricSampleCatalog.swift`、`HagimiMonitor/Localizable.xcstrings`；进程模型 `HagimiMonitor/TopCPUProcess.swift`、`TopGPUProcess.swift`、`TopMemoryProcess.swift`、`TopDiskProcess.swift`、`TopNetworkProcess.swift`、`ProcessEnergyShare.swift`。
- **测试范围**：`PowerPanelLayoutTests`、`MetricWidthAuditTests`、`PanelGeometryTests`、`PanelOrderingTests`、`UXAcceptanceRenderingTests`、`AccessoryGridLayoutTests`、`TopProcessRowTests`。
- **已有规范/在途变更冲突声明**：
  - 本提案将修改 `openspec/specs/monitor-panel/spec.md` 中“锁死 300pt 最窄半格判定”和“奇数半格末尾留空”的既有约束；
  - 本提案亦与在途变更 [panel-long-press-reordering/specs/monitor-panel/spec.md](../panel-long-press-reordering/specs/monitor-panel/spec.md) 中“前一半行指标之后留出空半格 / 不因面板宽度改变归属”条款存在策略差异，需在 A/B 对照裁决后统一同步并收敛主 spec。
