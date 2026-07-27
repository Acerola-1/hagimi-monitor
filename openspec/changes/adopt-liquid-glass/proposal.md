# 提案：全面采用液态玻璃（Liquid Glass）

## Why

项目在 v0.9.0 前曾将行级液态玻璃整体降级为毛玻璃，当时归因于"液态玻璃导致面板展开闪烁"。2026-07 重新评估后确认**当年降级的两个前提已失效**：

1. **闪烁的直接技术原因已查明**：旧实现 `CompatibleGlassContainer(spacing: 8)` 的合并距离**大于**面板行间距（`VStack(spacing: 6)`），导致所有行永远处于"可融合"状态，展开动画逐帧触发液态融合边界重算。解法是把容器 spacing 降到行距以下（如 2），当年未发现此参数语义。
2. **宿主架构已整体更换**：闪烁发生在 `MenuBarExtra(.window)` 时代（整窗重绘）；现宿主为自建 `NSPanel`（`FluidPanelController`），`setFrame(display:animate:)` 驱动高度动画，resize 不 rebuild SwiftUI 视图树。窗口底现用 `.popover + .behindWindow` 无闪烁即为活证据。
3. **`.glass` 按钮深色偏亮问题有解**：当年用的是裸 `.glass`；行级液态玻璃带上现有 `theme.rowGlassTint` 着色体系即可压住亮度。

2026-07-26 已完成一版完整实现并实测：**构建通过、运行正常、视觉效果可接受**（用户评价"实现效果还可以"）。因暂无时间微调，代码已复原，本变更留档待日后评估实施。

## What Changes

- **兼容层扩展**：`CompatibleGlassEffect` 新增 `style` 参数（`.frosted` / `.liquid` / `.liquidInteractive`），默认 `.frosted` 保证既有调用点零改动；macOS 15 回退层一字不动
- **面板行级液态玻璃**：6 个 metric 行 + Direct 版显示器控制行切 `.liquidInteractive`（tint 压亮度 + 指针交互反馈）
- **容器合并距离修复**：面板 `CompatibleGlassContainer` spacing 8 → 2（关键修复，杜绝行间融合重算）
- **按钮升级**：`compatibleButtonStyle()` 在 26+ 切原生 `.buttonStyle(.glass)`
- **设置页真液态玻璃**：`SettingsGroup` / `SettingsIconHeader` 卡片切 `.liquid`
- **零散点位**：小猫致谢卡片、菜单栏预览胶囊在 26+ 换 `.glassEffect`

## Capabilities

### New Capabilities
- `liquid-glass-adoption`: 按场景分级的液态玻璃采用策略（可交互表面 / 静态表面 / 毛玻璃回退）

### Modified Capabilities
- `macos15-glass-compatibility`: 现行 spec 仍写 `.sidebar + .behindWindow`，与代码实际的 `.menu + .withinWindow` 失同步，实施本变更时一并修正

## Impact

- **受影响文件**（6 个，完整 diff 见 design.md）：
  `CompatibleGlassContainer.swift`、`MonitorPanelView.swift`、`SettingsLayout.swift`、`GeneralSettingsView.swift`、`HeaderCatCameo.swift`、`DisplayControlsSection.swift`
- **明确排除**（勿实施）：菜单栏位图组件（无视图层级）、面板 header（15 逐帧脉冲动画）、行内 Pill/徽章（玻璃套玻璃反模式）、SparklineChart/ProgressMeter（数据图形）
- **验收门槛**：面板展开 CPU < 10%；展开/收起与窗口补间同步无闪烁；深浅双模式视觉协调
- **待微调项**：见 design.md「遗留微调项」
