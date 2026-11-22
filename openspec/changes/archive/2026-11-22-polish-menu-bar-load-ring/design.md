# Design: 菜单栏负载环精修与信息交互补齐

## Context

`MenuBarComputeRingIcon` 以 `21×21pt` `NSImage` 直接渲染并按 `(loadBucket, coreLevel, appearance, badge)` 缓存后赋给 `NSStatusItem.button.image`，动画由 `MenuBarLoadAnimator` 驱动。综合负载口径继续沿用 `ComputeLoadModel.combined`（CPU、GPU 与内存压力的 softmax 聚合）及三档固定核心色（`MenuBarCoreLevel` + 3 分回落迟滞）。动机与范围见 [proposal.md](proposal.md)，行为契约见 `specs/menu-bar/spec.md` 与 `specs/settings-window/spec.md`。

## Goals / Non-Goals

**Goals:**
- 消除半透明活跃弧与全圆底轨叠画引起的边缘发虚和中心发灰，校准圆帽端帽占比。
- 区分并支持压力告警与 Game HUD 两枚角标共存，满足无障碍高对比度与 VoiceOver 读取需求。
- 在不破坏菜单栏极简外观的前提下，通过惰性 Tooltip 与右键快捷菜单补齐归因与切换效率，并在设置页补齐图例自解释。

**Non-Goals:**
- 不改变 softmax 聚合公式、阈值边界或迟滞参数；不拆解外环与核心点的语义绑定；不开放 `ringSource` 或环+数字混合模式；不改动 `AppIcon.icon`。

## Decisions

### 1. 同心同半径与「剩余轨道」绘制

**选择**：将 `trackSize` 与 `ringSize` 统一为 `13.0pt`，先以 `.butt` 端帽顺时针绘制 `endAngle → -270°`（剩余未满段）的 `trackColor` 轨道，再以 `.round` 端帽顺时针绘制 `90° → endAngle` 的 `tint` 活跃弧（alpha `0.90 → 1.0`，高对比度下 `1.0`）。

**备选与取舍**：若保持全圆底轨并将活跃弧提高到 `1.0` alpha，在 `0.2pt` 直径差下外缘仍会出现细微灰边；仅画剩余轨道并用较粗（`2.0...2.25pt` > 轨道 `1.35pt`）的圆帽活跃弧自然盖住轨道平头断点，可彻底消除双层叠缝，同时让 21pt 原生矢量绘制保持单一路径锐度。

**端帽补偿与比例**：
- `progress = min(0.89, max(0.06, 0.06 + normalizedLoad * 0.83))`
  - 计入两边各半线宽约 `1.0...1.125pt`（在 `r = 6.5pt` 上合计约 `18°~20°`）后，`0%` 视觉占比约 `11%`（克制不显忙），`100%` 视觉占比约 `94.5%`（顶部 12 点前方仍留 `~2.2pt` 清晰缺口）。
- `lineWidth = 2.0 + normalizedLoad * 0.25`（稳住低载存在感，减少粗细剧烈跳变）。
- `coreSize = 3.4 + normalizedLoad * 0.9`，`coreBackplateSize = coreSize + 1.5`，核心点 alpha 固定 `1.0`（避免背板透色发灰）。
- 深浅外观下 `.idle / .working` 绿色向 `#3BEC64` 族微调：深色 `sRGB(0.26, 0.90, 0.56)`，浅色 `sRGB(0.04, 0.58, 0.34)`；`.busy` 与 `.stressed` 保持高辨识琥珀/珊瑚红。

### 2. 增强对比度与外观识别扩展

**选择**：在 `HagimiMonitorApp.swift` 的 `NSAppearance` 扩展补充四组高对比度变体匹配（`.accessibilityHighContrastAqua`、`.accessibilityHighContrastDarkAqua`、`.accessibilityHighContrastVibrantLight`、`.accessibilityHighContrastVibrantDark`），暴露 `isDark` 与 `isHighContrast`。`MenuBarComputeRingIcon.image` 新增 `increaseContrast: Bool = false` 参数并纳入缓存键：
- `appearanceSlot = (darkMode ? 1 : 0) + (increaseContrast ? 2 : 0)`（0...3）
- `badge = (showsAlert ? 1 : 0) | (showsHUDBadge ? 2 : 0)`（0...3）
- `cacheKey = ((loadBucket * 3 + coreLevel.rawValue) * 4 + appearanceSlot) * 4 + badge`（总量最大约 `101×3×4×4 = 4848`，维持 `cache.countLimit = 300` 按热点 LRU 复用）。

同时在 `FluidPanelController` 监听 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`，实时重刷状态项图像。

### 3. 告警红点与 Game HUD 徽章分离

**选择**：
- 压力告警保留右上角圆点（`MenuBarAlertBadge`，`radius = 1.8`，`inset = 2.4`）。
- `MenuBarHUDBadge` 移至**右下角**（`center = (rect.maxX - 2.7, rect.minY + 2.7)`），绘制 45° 旋转菱形（内半对角线 `1.9pt`，对比描边外半对角线 `2.55pt`），边界落在 `[0.15, 20.85]` 之内且与满载圆环保持约 `1.6pt` 间距。
- 更新 `MenuBarBadgePresentation`：`drawsAlert = showsAlert`、`drawsHUD = showsHUDBadge`、`needsOverlay = drawsAlert || drawsHUD`，在环形绘制路径与指标快照叠加路径均采用两个独立 `if` 判断绘制，使两者能够同时展示。

### 4. 惰性 Tooltip、VoiceOver、位置记忆与右键菜单

**选择**：
- **纯模型 `MenuBarStatusSummary`（`nonisolated Sendable`）**：负责将 `(combinedLoad, coreLevel, cpuUsage, gpuUsage, memoryPressure, showsAlert, showsHUDBadge)` 格式化为本地化 `tooltipText` 与 `accessibilityValue`，便于单元测试独立验证，不依赖 `NSStatusItem`。
- **惰性 Tooltip（`NSViewToolTipOwner`）**：不在秒级采样时写 `button.toolTip`（避免每次分配字符串并重置系统 tooltip 计时），而是由 `FluidPanelController` 实现 `NSViewToolTipOwner` 并对主按钮注册整块矩形 `statusToolTipTag`；当 `statusItem.length` 改变时重建 tag；悬停触发回调时直接读取 `store.combinedComputeLoad` 与各模块实时值拼出最新摘要。`FluidPanelController` 与 `NSViewToolTipOwner` 均运行在 `@MainActor`，需验证 Swift 6 严格并发签名（必要时用轻量隔离适配）。
- **VoiceOver `accessibilityValue`**：在 `refreshStatusItemImage` 内随负载桶或徽章变化同步更新 `button.setAccessibilityValue(_:)`，并与 `lastAccessibilityValue` 去重，避免无变化重复发辅助功能通知。
- **位置记忆**：主状态项设置 `statusItem.autosaveName = "SystemMonitor"`（与既有 `"DisplayControls"` 配对）。
- **右键菜单**：针对 `.systemMonitor` 增加显示模式切换项与（仅 `#if DIRECT_DISTRIBUTION`）`Game HUD` 勾选切换项；保持 `.displayControls` 入口右键菜单精简。

### 5. 设置页预览与三档图例

**选择**：
- `MenuBarLoadRingPreview` 新增 `var increaseContrast: Bool = false`（带默认值，兼容现有测试调用）。
- `MenuBarDisplaySettingsSection` 改用 `@Environment(\.colorScheme)` 与 `@Environment(\.colorSchemeContrast)` 驱动预览与图例，解决切换系统明暗或高对比度时静态 `NSApp.effectiveAppearance` 不自动重绘的问题。
- 在 `menuBarDisplayMode == .ring` 时显示说明文案（重新启用已有键 `menu-bar-display.ring-description`）、三档真实 `MenuBarComputeRingIcon` 样例卡与角标图例（HUD 图例仅 `#if DIRECT_DISTRIBUTION`）。

### 6. 三类菜单栏指标布局统一排版与符号去重

**选择**：
- `MenuBarMetricWidthEngine.splitValueUnit` 优先匹配多字符单位 `"Hz"` 再匹配单字符单位，并要求 `value.count > suffix.count` 以保留纯占位 `"--"`。
- 紧凑模式将测量与列宽计算全部收敛至 `MenuBarMetricWidthEngine`：上排标签采用 `7pt .medium`（视图 `0.64` 透明度），下排数字采用 `10pt .semibold` 搭配 `7.5pt .medium`（视图 `0.72` 透明度）弱化单位，列间距由 `2pt` 提升至 `7pt`，用单位缩窄省下的横宽换取多列满宽数值间的清晰断句。
- 横排模式将格内 `symbolSpacing` 设为 `2.5pt`，最小格间 `minInterPairGap` 设为图标模式 `7pt`、文字模式 `8pt`；文字模式前缀改用 `9.5pt .medium`（视图 `0.68` 透明度）并与主数字首基线对齐。
- 去重 `MenuBarMetricKind.symbol`（`.gpuPower` 改 `"bolt.square.fill"`、`.memoryBandwidth` 改 `"waveform"`、`.displayRefreshRate` 改 `"play.display"`），并将英文 `menu-bar-metric-prefix.display-refresh-rate` 补为 `"REF"`。

## Risks / Trade-offs

- **既有测试契约变更** → 原有 `MenuBarComputeRingIconCacheTests.alertDominatesHUDCacheState` 与 `SamplingGateStateTests.MenuBarBadgePresentationTests` 断言“告警覆盖 HUD”。本变更明确将需求修改为“右下角菱形共存”，需同步更新对应测试用例并新增像素边界与共存测试。
- **`NSViewToolTipOwner` 与 `button.toolTip` 混用冲突** → AppKit 规定设置 `button.toolTip` 会清除 `addToolTip` 区域，因此主状态项严格只使用 `addToolTip` 并随宽度重注册；显示器控制入口保留原 `button.toolTip`。
- **Swift 6 并发下 `NSViewToolTipOwner` 协议方法隔离** → 若 `@MainActor` 类直接实现 `nonisolated` Objective-C 协议方法产生编译告警，可用 `@preconcurrency` 或 `MainActor.assumeIsolated` 封装一层薄代理。
- **双渠道条件编译漏口** → 所有 Game HUD 菜单项、图例文案与测试断言须分别核对 `HagimiMonitor`（App Store）与 `HagimiMonitorDirect`（Direct）两个 scheme 的编译与运行效果。
