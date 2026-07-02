## Context

HagimiMonitor 是一个 macOS 菜单栏系统监控应用，支持 macOS 15 和 macOS 26+。项目使用兼容层（`Compatible*` 系列视图修饰符）在两个版本间提供一致的毛玻璃效果体验。

当前问题：
- `MonitorPanelView` 和 `DisplayControlsSection` 各自定义了 `detailDisclosure` 过渡，定义不一致
- macOS 15 的 `CompatibleGlassEffect` 对背景和内容都应用了 `clipShape`，造成冗余
- `ProgressMeter` 和 `SparklineChart` 缺少数值变化时的过渡动画
- macOS 15 的 `CompatibleGlassContainer` 只是一个普通 `VStack`，无视觉效果

## Goals / Non-Goals

**Goals:**
- 统一面板内所有区域的展开/折叠动画行为
- 为进度条和折线图添加平滑过渡
- 优化 macOS 15 兼容层实现
- 保持 macOS 26+ 的原生 Liquid Glass 体验不受影响

**Non-Goals:**
- 重新设计面板整体布局
- 添加新的系统监控指标
- 修改面板尺寸约束逻辑
- 更改 macOS 26+ 的 GlassEffectContainer 行为

## Decisions

### 1. 过渡动画统一方案

**决策：** 提取 `detailDisclosure` 过渡为共享常量，所有区域使用相同定义

**理由：**
- 当前 `MonitorPanelView:1435-1441` 使用 `.opacity.combined(with: .scale(0.98))`
- `DisplayControlsSection:138-145` 只使用 `.opacity`
- 统一使用插入时 `.scale(0.98)` + `.opacity`，移除时仅 `.opacity`

**替代方案：** 修改为简单的 `.opacity` — 但会丢失插入时的微妙缩放效果

### 2. 进度条动画方案

**决策：** 使用 SwiftUI 的隐式动画，在 `ProgressMeter` 中添加 `.animation(.easeInOut(duration: 0.3), value: value)`

**理由：**
- `ProgressMeter` 当前直接使用 `value` 计算宽度，无过渡
- 添加隐式动画使数值变化平滑
- 不影响性能，因为是简单的宽度动画

### 3. macOS 15 兼容层优化

**决策：** 移除 `CompatibleGlassEffect` 中的双重 `clipShape`

**理由：**
- 当前实现先裁剪 `VisualEffectView`，再裁剪整个内容
- `VisualEffectView` 已经被裁剪，外层裁剪冗余
- 移除外层裁剪可简化视图层级

### 4. SparklineChart 动画方案

**决策：** 使用 `withAnimation` 包裹 Canvas 重绘

**理由：**
- Canvas 本身不支持隐式动画
- 通过在父视图层面添加动画过渡，让 Canvas 平滑重绘
- 使用 `.animation(.easeInOut(duration: 0.25), value: samples)` 触发重绘

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| 动画增加 GPU 开销 | 保持动画时长 ≤0.3s，使用简单缓动曲线 |
| macOS 26+ 行为变化 | 所有修改通过兼容层隔离，不影响原生实现 |
| 过渡动画与 GlassEffect 冲突 | 测试确保 macOS 26+ 的 Liquid Glass 动画正常 |
| 进度条动画在高频更新时卡顿 | 使用 `value` 作为动画触发器，避免每帧都触发 |
