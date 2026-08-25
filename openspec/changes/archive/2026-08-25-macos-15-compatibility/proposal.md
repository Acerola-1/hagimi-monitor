## Why

当前 HagimiMonitor 仅支持 macOS 26+，因为核心 UI 大量使用了 macOS 26 引入的 `GlassEffectContainer`、`.glassEffect`、`.glassEffectID`、`.symbolEffect` 和 `.containerBackground` 等 SwiftUI API。用户反馈需要在 macOS 15 测试机上运行，但直接降低 `MACOSX_DEPLOYMENT_TARGET` 后，应用因运行时找不到这些 API 而无法启动。需要一套兼容方案，让应用在 macOS 15 上也能正常工作，同时保留 macOS 26 上的 Glass 视觉效果。

## What Changes

- **兼容层视图组件**：创建 `CompatibleGlassContainer` 等封装视图，在 macOS 26+ 使用原生 `GlassEffectContainer`，在 macOS 15 使用 `NSVisualEffectView` 实现类似毛玻璃效果
- **条件编译/运行时检查**：对所有 macOS 26+ API 调用添加 `@available` 或 `if #available` 保护
- **符号动画降级**：`.symbolEffect` 在 macOS 15 上移除或使用替代动画（如 `.opacity` 闪烁）
- **容器背景降级**：`.containerBackground` 在 macOS 15 上移除或使用透明背景替代
- **项目配置调整**：`MACOSX_DEPLOYMENT_TARGET` 降至 15.0，但保留 macOS 26 SDK 编译

## Capabilities

### New Capabilities
- `compatible-glass-effect`: 跨版本兼容的毛玻璃容器组件，支持 macOS 15 fallback
- `symbol-effect-fallback`: 符号动画的降级方案，macOS 15 使用替代动画
- `container-background-fallback`: 容器背景的降级方案

### Modified Capabilities
- （无现有 spec 需要修改，这是新增兼容层）

## Impact

- **受影响文件**：`MonitorPanelView.swift`、`SettingsLayout.swift`、`StatisticsView.swift`、`EventTimelineView.swift`、`DisplayControlsSection.swift`、`BatteryGlassRow`（`MonitorPanelView.swift` 内）
- **编译条件**：需要 `#available(macOS 26, *)` 运行时检查
- **UI 差异**：macOS 15 上的视觉效果会略有不同（`NSVisualEffectView` 效果 vs 原生 Glass），但功能完整
- **测试**：需要在 macOS 15 和 macOS 26 两个环境分别验证
