# Proposal: 精修菜单栏负载环的视觉、无障碍与信息表达

## Why

当前菜单栏负载环（`MenuBarComputeRingIcon`）在整体视觉语言与底层平滑缓存机制上已达到较高水准，但在小尺寸 Retina 像素锐度、状态徽章区分度、系统辅助功能适配以及“一眼看到状态后如何快速归因与操作”等方面仍有提升空间。与此同时，用户明确保留「softmax 单标量综合负载 + 三档固定核心色」的产品语义，需要一份针对性的精修方案，在不改变核心语义的前提下将其打磨至苹果原生菜单栏工具的精致度，并交付可运行的双渠道版本用于直观对照对齐。

## What Changes

- **光学几何与色彩精修**：
  - 将底轨（track）与活跃负载弧统一为同心同半径，并改为仅绘制**未覆盖部分的剩余轨道**，彻底消除半透明活跃弧叠加全圆底轨产生的中轴叠缝。
  - 针对 `.round` 圆头端帽的半宽延伸重新校准 `progress` 映射，消除 `0%` 空闲偏长与 `95%+` 提前封口失向的问题，使 `100%` 满载仍保留清晰可见的顶部微缺口。
  - 收窄线宽与中心点尺寸的浮动幅度并提高活跃弧墨色不透明度，使低负载态也能与系统原生状态栏图标保持均衡的视觉分量；中心核心点实色化并微调深浅外观下的绿点色值，提升与品牌资产的家族一致性。
  - 适配 macOS「增强对比度」（`NSAppearance` 高对比度变体与 `accessibilityDisplayShouldIncreaseContrast`），并纳入图像缓存键。
- **告警红点与 Game HUD 徽章的位置与形态区分（支持共存）**：
  - 压力告警保留右上角红色圆点；Game HUD 状态改为**右下角紫色菱形**（45° 旋转方块带反差描边），解除两者同位同形、告警覆盖 HUD 且仅靠颜色区分的限制。
  - App Store 渠道保持不绘制 Game HUD 徽章。
- **主状态项交互、无障碍与信息补齐**：
  - 主系统监控状态项设置 `statusItem.autosaveName = "SystemMonitor"` 以稳定记忆菜单栏拖拽排位。
  - 通过 `NSViewToolTipOwner` 实现**惰性悬停 Tooltip**（零常驻采样/绘制开销），按需展示综合负载百分比与档位、CPU / GPU / 内存压力明细，以及未读告警或 Game HUD 运行提示。
  - 为主状态项按钮同步并去重更新 `accessibilityValue`，使 VoiceOver 能读出实时综合负载与分项归因。
  - 右键上下文菜单新增「切换为菜单栏指标 / 切换为负载环」快捷切换项；Direct 渠道额外提供「游戏 HUD」勾选快捷开关。
- **设置页说明与三档图例**：
  - 在「通用 → 菜单栏」选为负载环模式时，展示综合负载说明文案、由真实 `MenuBarComputeRingIcon` 渲染的三档状态图例（正常 / 繁忙 / 高压）及角标说明（App Store 版仅显示未读压力事件红点说明，Direct 版补充游戏 HUD 显示中紫菱说明）。
  - 修复设置页预览仅读取 `NSApp.effectiveAppearance` 不响应环境变化的问题，同步接入 SwiftUI `colorScheme` 与 `colorSchemeContrast`。
- **菜单栏三类指标布局（图标 / 文字 / 紧凑）统一排版与符号去重**：
  - 统一 `MenuBarMetricWidthEngine` 与 `MenuBarMetricLabel` 的三模式测量与渲染：支持多字符单位 `Hz` 拆分弱化；紧凑模式上排标签降为 `7pt .medium`（`0.64` 透明度）、下排主数字改 `10pt .semibold` 并搭配 `7.5pt .medium`（`0.72` 透明度）弱化单位，列间距提至 `7pt` 以消除多满宽指标粘连；横排文字模式前缀缩为 `9.5pt .medium`（`0.68` 透明度）并基线对齐，横排格内间距提至 `2.5pt`、最小格间间距提至 `7pt`（图标）与 `8pt`（文字）。
  - 去重 16 项菜单栏指标 SF Symbol（`.gpuPower` 改 `"bolt.square.fill"`、`.memoryBandwidth` 改 `"waveform"`、`.displayRefreshRate` 改 `"play.display"`），并补齐 `menu-bar-metric-prefix.display-refresh-rate` 英文前缀 `"REF"`。

### Non-Goals

- 保持现有 softmax 单标量综合负载聚合（`ComputeLoadModel.combined`）与三档固定核心色 + 3 分回落迟滞（`MenuBarCoreLevel`）不变。
- 不做“外环算力 / 中心点健康度”双通道语义解耦。
- 不重新开放 `ringSource` 监测源选择器，不做“环 + 数字”混合模式。
- 不添加常驻呼吸/旋转动画，不修改 `AppIcon.icon` 或静态品牌图标资产。
- 不执行 git 提交。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `menu-bar`: 新增负载环光学绘制与高对比度适配要求、状态项悬停摘要 / 无障碍值 / 位置记忆 / 快捷右键菜单要求，并修改告警与 Game HUD 徽章的位置、形态及共存行为。
- `settings-window`: 新增通用设置页在负载环模式下展示说明文案、三档真实渲染图例、角标图例以及响应系统色彩/对比度变化的预览要求。

## Impact

- `HagimiMonitor/HagimiMonitorApp.swift`: 扩展 `NSAppearance` 的 `isDark` 与 `isHighContrast` 判定。
- `HagimiMonitor/MenuBarComputeRingIcon.swift`: 调整几何参数、剩余轨道绘制、实色核心、高对比度配色与缓存键结构，独立绘制两枚角标。
- `HagimiMonitor/MenuBarHUDBadge.swift`: 改为右下角紫色菱形绘制，更新 `MenuBarBadgePresentation` 允许告警与 HUD 并存。
- `HagimiMonitor/MenuBarStatusSummary.swift`（新增）: 封装本地化悬停 Tooltip 与 VoiceOver `accessibilityValue` 文案模型。
- `HagimiMonitor/MonitorModels.swift`: 暴露只读 `computeLoadBreakdown` 供 Tooltip 与无障碍文案获取实时分项数据（`combinedComputeLoad` 同步复用）。
- `HagimiMonitor/Views/Panel/FluidPanelController.swift`: 接入 `autosaveName`、`NSViewToolTipOwner`、增强对比度监听、`accessibilityValue` 去重同步、指标模式双徽章叠加以及右键快捷菜单项。
- `HagimiMonitor/MenuBarDisplayModels.swift` & `HagimiMonitor/MenuBarMetricWidthEngine.swift`: 去重指标 SF Symbol，统一横排与紧凑模式的字号层次、多字符单位 `Hz` 拆分、列宽测量及最小格间距。
- `HagimiMonitor/MenuBarStatusLabel.swift` & `HagimiMonitor/Views/Settings/GeneralSettingsView.swift`: 升级三类指标视图层次与间距，传递对比度状态并补充负载环说明与三档/徽章图例。
- `HagimiMonitor/Localizable.xcstrings`: 激活既有描述键、修复英文刷新率前缀并补齐中英双语文案。
- `HagimiMonitorTests/`: 更新徽章/缓存测试，新增 `MenuBarStatusSummaryTests`、`MenuBarMetricLayoutTests` 与几何/高对比度/共存像素测试。
