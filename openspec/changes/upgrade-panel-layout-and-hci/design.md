# Design

## Context

当前面板架构与痛点背景见 [proposal.md](proposal.md)。代码核查确认以下关键技术约束：

1. **单宿主统一运动与几何快照**：面板展开/收起由 `NativePanelLayerView`、`PanelExpansionDriver` 与 `PanelGeometrySolver` 共同驱动，高度变更必须使用连续可中断弹簧/解析轨迹且不引入逐帧文本重测或布局抖动。`MetricDetailGrid` 使用非 Lazy 的 `PanelMetricColumns` / `PanelMetricColumnsLayout`（`SingleHostLayoutComponents.swift`），确保折叠状态下也能正确测出自然高度。
2. **配色与表面层的跨文件所有权**：
   - `MonitorPalette.swift` 持有模块与状态颜色（`balancedModuleTint`、`vibrantModuleTint`、`severityTint`、`displayTint`）、内衬（`trackFill` / `rowGrooveFill`）、文字层级（`primaryText` / `valueText` / `secondaryText` / `captionText`）及活力玻璃填充（`RowGlassFadeFill`）；
   - `NativePanelCardBackdropView`（`NativePanelCardBackdrop.swift`）和 `CompatibleGlassEffect` / `PanelMaterialButtonStyle`（`CompatibleGlassContainer.swift`）持有正式卡片和底部按钮材质；
   - `NativePanelLayerView.swift` 持有窗口底座罩（深色 `black @ 0.35`、浅色 `lightSurfaceVeilOpacity ?? 0.45`）及外框描边；
   - `PowerPanelLayoutTests.selectedPowerControlsMeetSmallTextContrastInBothThemes` 硬性断言 `MonitorPalette.selectedControlForeground`（`#171D2A`）在 `palette.moduleTint(for: .battery)` 上的对比度在明暗 × 两套主题全部组合下 `>= 4.5:1`。
3. **宿主宽度与静态预算的脱节**：`MonitorConstants` 定义了 `panelMinWidth = 300`、`panelIdealWidth = 340`、`panelMaxWidth = 460`，但目前宿主实际均固定使用 `panelIdealWidth = 340`。`StaticMetricSizing` 仍按未启用的 `300pt` 算出 `halfCellContentWidth = 120pt` 并叠加极端 `WorstValue`（如 `cpu.uptime` 为 `"888天88小时"`），迫使常规宽度的常见项占满整行。
4. **跨表面同源复用**：设置页实时预览 `ModuleRowPreview`（依赖 `MetricSampleCatalog` / `MetricPreviewTile`）以及供电分页 `PowerDetailPages` 共用 `MetricDetailGrid` 的排序、跨度、调色与视觉语言。
5. **长按拖拽与手势仲裁**：`PanelReorderItemModifier`（`PanelReorderInteraction.swift`）以 `.simultaneousGesture(LongPressGesture(minimumDuration: 0.4)...)` 挂载在模块行头与各指标格上，且模块展开手势仅挂载在行头。
6. **双渠道能力边界**：`HagimiMonitor`（App Store 沙盒）无法采集网络进程与磁盘他进程且禁止控制他进程生命周期；`HagimiMonitorDirect`（`DIRECT_DISTRIBUTION` + `DISPLAY_CONTROL`）放开磁盘/网络进程榜与显示器控制。

## Goals / Non-Goals

**Goals:**
- 按 **共用微交互基线 → 全象限配色定稿 → 展开网格 A/B（Worktree）对照 → 交互闭环升级** 的依赖顺序推进，保证最终在定稿配色下评测两套网格形态。
- 提供可同屏横向比较的 **浅色活力主题 3 套候选** 与 **平衡（浅/深）及活力（深）优化对照**，裁决后收敛为干净单一的正式调色实现。
- 在绝对不引入 1Hz 实时采样跳变（CLS）的前提下，解决展开指标网格“大段空灰条”和“落单半格右侧缺牙”问题。
- 让现有隐藏的交互（全格复制、CPU 核心环悬停、全展开、可展开提示、TOP 进程快捷操作）具备直觉可达性与原地反馈。

**Non-Goals:**
- **不改写面板单宿主运动内核**（`NativePanelLayerMotion` / `PanelGeometrySolver` 保持既有弹簧连续性与隐藏期刷新门控）。
- **不把进程能耗数据源改造并入本次变更**（电源排行数据口径仍由暂停中的 `improve-app-energy-ranking` 独立管理，本变更仅增强展示行的通用交互）。

## Decisions

### 1. 第一阶段：共用排版减噪与微交互基线

#### 1.1 主行去冒号、对齐槽宽与行头胶囊平衡
- **做法**：
  - 去掉 `MetricGlassRow`、`NetworkGlassRow`、`BatteryGlassRow`、`BluetoothGlassRow`、`DisplaySection` 与设置预览 `ModuleRowPreview` 中模块名称后的 `":"`，直接修掉 `DisplaySection.controlsContent` 在 `showsDeviceReadings == true` 时的悬空 `"显示器:"`。
  - 左侧模块名引入按当前语言（`StaticMetricSizing.panelLanguage`）区分的最小对齐槽宽，使 9 行主数值在纵向上对齐成一条清晰扫描线；300pt 窄宽下若极端长词溢出，允许仅对超长标题退化回自然紧凑间距而不截断文字。
  - `BluetoothGlassRow` 的 `deviceIcons` 改为按设备图标数量紧凑自适应宽度（上限仍不超过双胶囊宽度），消除宽槽配单个小图标的失衡感；柔化 `PairedHeaderReadings` 对比。
  - 统一 `%` 符号渲染：在 `MetricDetailGrid` 的 `splitValueUnit` 中将 `"%"` 视为紧贴数字的符号（与数字同字号、同 `valueText` 色/字重且无额外 `spacing` 裂隙），`"°C"`、`"GB/s"`、`"mAh"` 等字母单位维持弱化后缀语义。
- **替代方案**：仅去掉 `DisplaySection` 冒号而不做左对齐槽宽。放弃原因：不同字数模块名仍导致主数值参差锯齿。

#### 1.2 全格复制热区、原地状态切换与手势共存
- **做法**：
  - 把 `MetricCopyFeedback` 从内层 `splitValue` 移至整张 `insetCell`（`thermalPressureCell` 保留温度与热压力档位各自独立热区）。
  - 悬停时整格轻微提亮并显示统一提示（整合解释文案、复制提示与长按拖拽提示，避免内外 `.help()` 相互覆盖）；点击后在格内**原地**将数值短暂切换为 `✓ 已复制`（约 1.0s 后恢复），移除 `.overlay(alignment: .topTrailing)` 浮层，保持零尺寸跳变。
  - 在 `PanelReorderItemModifier` 的上下文菜单中补充“复制数值”，并在触发复制前校验当前无在途拖拽会话（`panelReorder.session == nil`）。
- **替代方案**：保留局部小浮层只放大热区。放弃原因：24pt 高窄格上叠浮层会遮住自身或邻格文字。

#### 1.3 `CPUCoresDetail` 悬停原地反馈
- **做法**：保留 `CoreRingHoverRegion` 指针跟踪，去掉 `coreRing` 上的 `.overlay(alignment: .bottom)` 遮挡气泡；悬停命中核心时高亮目标 `CoreLoadRing`（如微放大或轨道提亮），同时下方 `P / E / S` 分组栏原地切换为居中显示 `P2 · 45%` / `E1 · 18%`（等高固定容器确保零高度跳变），移出后恢复分组均值。
- **替代方案**：气泡上移。放弃原因：顶部紧邻分隔线与行头，依然溢出边界。

#### 1.4 顶栏统计入口与全展开可发现性
- **做法**：将 `statsEntryButton` 的系统图标从 `chart.bar.doc.horizontal` 替换为更直观的 `chart.xyaxis.line`（或 `chart.bar.xaxis`）；为 `SYSTEM · LIVE` 标题区补齐“双击全部展开/收起”可发现提示，并评估在顶栏右侧操作簇新增极轻全展开/收起微按钮（在 `ViewThatFits` 中先于统计入口按优先级让位）。

---

### 2. 第二阶段：全象限配色与表面材质多版本对照与裁决

#### 2.1 四象限诊断基线与优化配方
1. **活力 · 浅色（实现 3 套完整候选供选择）**：
   - **方向 1（清透亮白磨砂 + 浅色专调高纯度前景）**：卡片本体改为微透亮白磨砂底 + `0.5pt` 细腻浅色描边建立物理层级；行头仅留 `1.5%–3%` 极轻模块微晕，展开区 `rowTintFaintOpacity` 降至 **`0%`** 归纯中性；内部 `trackFill` 去除 `#3C485A` 冷蓝偏色，改用纯中性（`white @ 55%` 微浮片 + 细描边，或无色偏 `black @ 3.5%`）；前景色表针对浅色单独压深提纯，确保图标与图表保持鲜明活力与足够非文本对比度。
   - **方向 2（前景/底色解耦淡彩玻璃 + 按色相控浓度 + 展开归零）**：保留浅色淡彩玻璃思路，但拆出浅色专用的 `vibrantLightSurfaceTint`：CPU/磁盘等暖色表面压低染色浓度（`3.5%–4.5%`）并向清透蜜柑/琥珀微调色相以避开肉粉与泥黄，冷色保持 `5.5%–6%`，同时展开超过 `110pt` 后底色完全衰减至 `0%`；`trackFill` 使用纯净半透明白片（带极细边框）隔绝冷暖冲突。
   - **方向 3（纯白磨砂 + 图标柔光底托 + 高负载局部着底）**：常态下所有卡片本体保持洁白中性磨砂 + `0.5pt` 细描边，活力由行头图标的柔光圆角底托（tinted badge）与右侧高饱和图表承载；仅当某模块超过 `warningThreshold` / `criticalThreshold` 时，行头才轻柔浮现告警色微晕。
2. **平衡 · 浅色 & 平衡 · 深色（`refined` vs 原版 `baseline`）**：
   - **重分撞车色相**：现状 `balancedModuleTint` 中 6 个模块挤在蓝青区，且 `memory`（`#42A39A`）与 `network`（`#43A6A0`）几乎同色。优化方案将内存（保持清润青绿）、网络（转清澈水蓝/天青）、GPU（回归低饱和蓝紫/靛紫以承接活力紫的家族记忆）、蓝牙（稳重钴蓝）与显示器（中性钢蓝）明确拉开色相间隔，保留温和克制的低饱和基调。
   - **明暗分治与对比度加固**：浅色下适当压深偏淡的 `fan`（`#5BB0C2`）、`battery`（`#55BC6F`）、`memory`、`cpu` 及 `severityTint`（现行浅色玻璃下图标/图形多落在 `2.0–2.9:1`），去除 `#3C485A` 冷蓝偏色统一中性灰，并为卡片补充 `0.5pt` 浅色细描边；深色下适度提亮偏沉的 `storage`（`#9A865E`）及 `severityTint`。
3. **活力 · 深色（保留暗底发光基调，`refined` vs 原版 `baseline`）**：
   - **保留核心氛围**：维持深黑窗口底座（`black @ 0.35`）与 `16% → 2%` 玻璃渐变作为基线。
   - **四项克制精修**：
     1. 将深色 `trackFill` 从 `white @ 0.03` 适度提至 `0.06`（`rowGrooveFill` 同步提至 `0.07–0.08`），让深色下指标格与行头成对读数槽重新具备清晰边界；
     2. 在 `NativePanelCardBackdropView` 为卡片补上与底部 `PanelMaterialButtonStyle`（`materialButtonStroke` = `white @ 0.10`）呼应的 `0.5pt` 极细高光描边（约 `white @ 0.08`），统一卡片与底部按钮轮廓语言；
     3. 将深色 `captionText` 从 `white @ 0.78` 适当拉开到约 `0.64`，与 `valueText`（`white @ 0.90`）形成清晰“值主标签次”扫读跨度（并验证在复杂高饱和浅色背景透出下仍可读）；
     4. 轻微提亮深色下偏暗的 `storage`（`#B28600`）与 `severityTint`（`.calm` / `.warning` / `.critical`）。
4. **硬对比度约束**：任何象限调整 `.battery` 模块色时，均需保证 `MonitorPalette.selectedControlForeground`（`#171D2A`）与其对比度继续 `>= 4.5:1`（`PowerPanelLayoutTests`）；浅色电池若需同时满足浅底图形可读（`>= 3.0:1`）与深色前景文本达标（`>= 4.5:1`），其相对亮度须精确落在 `[0.23, 0.30]` 甜区，或将卡片前景色与实色控件填充色按语义分槽。

#### 2.2 多版本同屏对照机制（`#if DEBUG` 启动参数）
- **决策**：配色对照采用 `#if DEBUG` 临时启动参数 `-HagimiPaletteVariant`（接入 `TemporaryInstanceOverrides`，取值如 `v1` / `v2` / `v3` / `baseline` / `refined`），配合 `-HagimiInstanceLabel` 在单份 Debug 构建下同时拉起多个钉住面板实例并排对比；正式 Release 构建通过 `#if DEBUG` 编译隔离。
- **替代方案**：为 3 套浅色活力 + 平衡/深色对比分别开 3~4 个 Git Worktree。放弃原因：配色改动集中于 `MonitorPalette.swift`、`NativePanelCardBackdrop.swift`、`NativePanelLayerView.swift` 等少数文件，若拆成 4 个 worktree，既无法复用单次构建同时摆 3 个窗口比色，还会给第一阶段基线维护和后续网格工作流带来无谓的合并冲突；待用户裁决各象限胜出方案后，立即删去全部临时参数与淘汰分支代码。

---

### 3. 第三阶段：展开指标网格 A/B 双方案并行设计与 Worktree 对照

#### 3.1 共同约束
- 两种方案均保持**零 1Hz 实时布局重排**，保持 `PanelMetricColumnsLayout`（非 Lazy）同步自然尺寸测算与 `ModuleRowPreview`（设置页预览卡）同源复用，并在已完成第一、二阶段的**最终定稿配色**上对比。

#### 3.2 方案 A（主工作区分支 `exp/panel-grid-a`）：KPI 堆叠微瓦片 + 规格行分离 + 语义组合条
- 将 `MetricDetailGrid` 分为三类静态形态：
  1. **紧凑 KPI 瓦片（标签在上、加粗数值在下）**：覆盖短数值与状态指标，支持 **2 列或 3 列**均衡布局，尾行落单可等分撑满，彻底消除右侧空白。
  2. **语义组合条**：CPU `闲置 / 系统 / 用户` 合并为三段构成比例条 + 紧凑图例，省去孤立半格。
  3. **规格 / 诊断整行（保持标签左 · 数值右）**：仅用于无界文本与长技术参数串（SSID、IP、PD 档位、Display 档案）。
- 适配 `PanelReorderController` 多列命中逻辑与 `MetricWidthAuditTests`（按堆叠瓦片内标签行/数值行单行预算审计）。

#### 3.3 方案 B（独立 Git Worktree `exp/panel-grid-b`）：容器断点响应式 + 孤立半格自动补满
- 保留左右键值对形态，升级两项核心机制：
  1. **宽度档位静态纯函数**：`StaticMetricSizing.isFullRow(kind:name:language:availableWidth:)` 按实际宿主宽度减去留白后的列宽判定断点，不再锁死未启用的 `300pt`（`120pt` 预算）。
  2. **合理 99% 分位最坏值契约 + 孤项撑满**：将极端离群值（如 `"888天88小时"`）收回到常规上界（超出极值走紧凑单位或 `minimumScaleFactor` 兜底）；修改 `MetricGridPacking.rows(for:)`，行内仅余 1 个 `span == 1` 元素时自动按整行宽度铺满（保留原逻辑 `span = 1` 以支持拖拽后重新配对）。
- 适配 `MetricWidthAuditTests` 遍历 `["zh-Hans", "en"] × [300, 340, 460]` 全档位矩阵断言。

#### 3.4 Worktree 并行对照与收敛流程
1. 第一、二阶段合入主工作分支后，主工作区建分支 `exp/panel-grid-a` 实施 **方案 A**；
2. `git worktree add ../hagimi-monitor-grid-b -b exp/panel-grid-b` 在独立 worktree 实施 **方案 B**；
3. 使用独立 DerivedData（`tmp/dd-grid-a` 与 `tmp/dd-grid-b`）分别编译 `HagimiMonitorDirect`，带 `-HagimiInstanceLabel "方案A"` / `"方案B"` 同屏启动对比；
4. 按用户裁决合并胜出方案，删除废弃 worktree/分支，并同步收敛主 spec、`ModuleRowPreview` 与测试。

---

### 4. 第四阶段：人机交互闭环升级

#### 4.1 行头可展开提示
- 仅在 `detailAvailable` / `hasExpandableContent` / `canExpand` 为 true 时，折叠态行头悬停呈现极轻 chevron 提示；单风扇等不可展开行不显示箭头且维持既有 `34pt` 行高与右缘对齐。

#### 4.2 TOP 进程行悬停/右键快捷操作与 PID 复用防护
- **数据源与透传**：六类 TOP 模型均已携带 `pid: pid_t`，需透传给 `TopProcessRowData`。
- **交互与渠道边界**：悬停渐显轻量快捷动作 + 整行 `.contextMenu`（前置激活、复制名称/PID、访达显示）；仅 `#if DIRECT_DISTRIBUTION` 提供带二次确认的温和退出（行内微确认条优先，避免菜单栏临时面板弹出系统弹窗失焦关闭）。
- **安全校验**：校验 `pid > 0`、非自身（`pid != ProcessInfo.processInfo.processIdentifier`）、非关键系统进程，并在执行前通过 `NSRunningApplication(processIdentifier: pid)` 核对应用存活与名称/路径匹配，防止 1Hz 采样间隙 PID 复用误伤。

#### 4.3 面板宽度调节评估
- 若在第三阶段后需要开放 `300~460pt` 面板宽度调节，则在设置页「常规 → 外观」增加宽度档位（或钉住面板边缘拖拽），并传入 `NativePanelLayerView`、`FluidPanelController`、`PinnedPanelController` 与 `StaticMetricSizing`。

## Risks / Trade-offs

- **全象限同时调优可能让“平衡”和“活力”境界模糊** → 平衡主题专注柔和低饱和且重在拉平内部撞车色相；活力主题专注高纯度前景/图表对比，即使选浅色方向 1/3 仍能一眼与平衡拉开区分。
- **修改 `.battery` 调色易触发 `PowerPanelLayoutTests` 对比度断言失败** → 浅色/深色电池色严格控制在相对亮度满足 `#171D2A` 对比度 `>= 4.5:1` 区间内，必要时将“图标/图表前景色”与“选中实色填充背景”拆槽。
- **深色 `captionText` 降亮后在极复杂桌面壁纸透过 `.popover` 玻璃时可能对比下滑** → 仅适度调整幅度（`~0.64` 档），并在真实浅色/深色/高对比复杂壁纸下联合检验。
- **A/B 并行或三联配色对照清理不彻底导致测试/Release 残留分支逻辑** → 配色临时开关严格包裹 `#if DEBUG` 且第 2.4 步强制清理回收；网格 Worktree 在第 3.4 步强制销毁并验证 `git worktree list`。
- **与 `panel-long-press-reordering` 的落单半格留空条款存在差异** → 在 `proposal.md` 与 `specs/monitor-panel/spec.md` 显式标注，胜出方案定型后统一同步主规范。

## Migration Plan

1. **第一阶段落地**：完成共用排版减噪与微交互修复，回归双渠道编译与既有测试。
2. **第二阶段配色对照与裁决**：基于第一阶段基线通过 `#if DEBUG` `-HagimiPaletteVariant` 交付浅色活力 3 套候选与平衡/深色优化对照，同屏目测后按用户决定固化唯一正式配色，清理临时变体参数。
3. **第三阶段网格 A/B（Worktree）对照与裁决**：在定稿配色上分别于主工作区分支与独立 Git Worktree 实现方案 A 与方案 B，同屏目测后合并胜出方案并销毁淘汰分支/worktree。
4. **第四、五阶段**：完成行头可展开提示、TOP 进程交互闭环（及按需面板宽度调节），执行双渠道构建、全量 `xcodebuild test`、真实多背景目测验收与 `DESIGN.md` 同步。
