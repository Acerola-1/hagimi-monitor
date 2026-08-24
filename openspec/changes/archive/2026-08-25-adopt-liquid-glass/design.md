# 设计：液态玻璃采用方案

## Context

完整实现已于 2026-07-26 验证通过（构建成功、运行正常、效果可接受），随后按用户要求复原，
留档待日后微调后正式实施。**本目录下 `implementation.patch` 是当时验证过的完整 diff**。

## 一键恢复

```bash
git apply openspec/changes/adopt-liquid-glass/implementation.patch
./launch.sh   # 构建 + 杀旧实例 + 启动
```

若主干代码已演进导致 patch 冲突，按下方「核心决策」手工重做，工作量约半小时。

## 核心决策

### 1. 闪烁根因与修复（最关键的一条）

`GlassEffectContainer(spacing:)` 的 spacing 是**液态融合触发距离**：两个玻璃元素间距小于
spacing 即进入融合计算。旧实现 spacing=8 > 面板行距 6，所有行永远可融合，展开动画逐帧
重算融合边界 → 闪烁。修复：**面板容器 spacing 降为 2**（必须小于行距 6）。

### 2. 兼容层 API 形态

`CompatibleGlassEffect` 加 `style: CompatibleGlassStyle = .frosted` 参数：

- `.frosted`：现状毛玻璃（`NSVisualEffectView(.menu, .withinWindow)`），默认值，既有调用点零改动
- `.liquid`：26+ 原生 `.glassEffect(.regular[.tint])`，静态表面用（设置卡片）
- `.liquidInteractive`：追加 `.interactive()`，可点击表面用（面板行）

**macOS 15 回退层一律走 `.frosted` 实现，一字不改**——`.withinWindow` 约束依然成立
（15 上面板逐帧 resize 时 `.behindWindow` 会触发桌面重采样闪烁）。

tint 处理：`tint == .clear` 时不调 `.tint()`（`.tint(.clear)` 视觉异常）；面板行传
`theme.rowGlassTint(for: kind)` 压住裸 `.regular` 深色模式偏亮的问题。

### 3. 各调用点风格分配

| 调用点 | style |
|---|---|
| 面板 6 个 metric 行（MonitorPanelView 三个 Row 组件） | `.liquidInteractive` + rowGlassTint |
| DisplayControlsSection（Direct 版） | `.liquidInteractive` + displayGlassTint |
| SettingsGroup（radius 13）/ SettingsIconHeader（radius 12） | `.liquid`，无 tint |
| `compatibleButtonStyle()` | 26+ `.buttonStyle(.glass)`，15 回退 `PanelMaterialButtonStyle` |
| CatThanksCard（HeaderCatCameo） | 26+ `.glassEffect(.regular, in: .rect(cornerRadius: 12))`，15 回退 `.regularMaterial`（独立 `CatThanksCardBackground` modifier） |
| 菜单栏预览胶囊（GeneralSettingsView） | 26+ `.glassEffect(.regular, in: .capsule)`，15 回退 `.quaternary`（独立 `MenuBarPreviewChipBackground` modifier） |

### 4. 保持不动的决策

- `CompatibleGlassEffectID` 维持空操作：行不参与 morphing（展开是高度生长非视图插拔），
  恢复真 `glassEffectID` 会重新引入容器几何重算
- 面板窗口底维持 `NSVisualEffectView(.popover, .behindWindow)`：窗口级单层无闪烁问题
- 明确排除区：菜单栏位图、header（15 逐帧脉冲）、行内 Pill/徽章（玻璃套玻璃）、数据图形

## 遗留微调项（日后评估时逐项过）

1. **行 tint 浓度**：`rowGlassTint` 原是为毛玻璃底调的，在液态玻璃上浓淡可能需重调
   （入口：`MonitorPalette.rowGlassTint(for:)`）
2. **底部按钮 `.glass` 深色模式观感**：当年被否决过，若仍偏亮可试 `.tint()` 或回退 `.frosted`
3. **`.interactive()` 是否保留**：悬停反馈与行的 hover 高亮可能视觉打架
4. **进阶项（未实施）**：面板窗口底换 macOS 26 AppKit `NSGlassEffectView`
   （Fluid/PinnedPanelController 两处），需单独验证 resize 动画表现
5. **spec 同步**：修正 `openspec/specs/macos15-glass-compatibility/spec.md`
   （`.sidebar + .behindWindow` → 实际的 `.menu + .withinWindow`），补充场景边界

## 验收标准

- 面板展开时 CPU < 10%（`top -pid $(pgrep HagimiMonitor)`）
- 展开/收起动画与窗口补间同步、无闪烁（重点连续快速点击多行）
- 深色/浅色模式下行、按钮、设置卡片基调协调
- macOS 15 回归：视觉与行为与现状完全一致（回退层未动，理论零风险，仍需实测确认）
