## Context

HagimiMonitor 是一个 macOS 菜单栏系统监控应用，当前使用 macOS 26+ 特有的 SwiftUI API（`GlassEffectContainer`、`.glassEffect`、`.glassEffectID`、`.symbolEffect`、`.containerBackground`）构建面板 UI。这些 API 在 macOS 15 上不存在，导致应用无法在 macOS 15 上运行。需要引入兼容层，在 macOS 15 上使用替代方案实现相似的视觉效果。

## Goals / Non-Goals

**Goals:**
- 应用能在 macOS 15 上正常编译和运行
- macOS 26 上保留原有的 Glass 视觉效果
- macOS 15 上使用 `NSVisualEffectView` 实现近似的毛玻璃效果
- 最小化现有代码的改动，通过封装层隔离版本差异
- 符号动画和容器背景在 macOS 15 上有合理的降级方案

**Non-Goals:**
- 不在 macOS 15 上 100% 还原 macOS 26 的视觉效果（Glass 是 macOS 26 特有渲染管线，无法完全复刻）
- 不引入第三方依赖
- 不改变现有 macOS 26 上的任何行为

## Decisions

### 1. 使用运行时检查而非编译条件
**决策**：使用 `if #available(macOS 26, *)` 运行时检查，而非 `#if` 编译条件。
**理由**：
- 编译条件需要维护两套代码路径，容易遗漏
- 运行时检查允许用同一个 binary 在 macOS 15 和 26 上运行
- SwiftUI 的 `@ViewBuilder` 对 `if #available` 支持良好

### 2. 封装为 ViewModifier 和自定义 View，而非在每个调用点写 `if #available`
**决策**：创建 `CompatibleGlassContainer`、`CompatibleSymbolEffect`、`CompatibleContainerBackground` 等封装组件。
**理由**：
- 现有代码中 `GlassEffectContainer` 和 `.glassEffect` 出现 10+ 处，分散在各文件中
- 封装后只需修改 import 和调用名称，降低出错概率
- 便于后续统一调整 fallback 效果

### 3. macOS 15 的 Glass fallback 使用 `NSVisualEffectView` + `NSViewRepresentable`
**决策**：在 macOS 15 上使用 `NSVisualEffectView` 实现毛玻璃背景。
**理由**：
- `NSVisualEffectView` 从 macOS 10.10 就存在，兼容性最好
- 支持 `.sidebar`、`.contentBackground` 等 material 类型
- 可以通过 layer mask 实现圆角效果
- 替代方案（如自定义 `Canvas` 绘制）复杂度高且效果不如系统原生

### 4. 符号动画在 macOS 15 上降级为静态或简单 opacity 动画
**决策**：
- `.symbolEffect(.pulse)` → 使用 `withAnimation(.easeInOut)` 循环改变 `.opacity`
- `.symbolEffect(.variableColor.iterative)` → 移除动画，显示静态图标
**理由**：
- macOS 15 的 `SymbolVariants` 和 `symbolRenderingMode` 可用，但 `symbolEffect` 不可用
- 脉冲效果可以用 opacity 模拟，用户感知差异小
- variableColor 动画较复杂，降级为静态不影响功能

### 5. `.containerBackground` 在 macOS 15 上降级为透明窗口设置
**决策**：在 macOS 15 上，通过 `TransparentWindowBackground`（已有组件）确保窗口透明，不使用 `.containerBackground`。
**理由**：
- 已有 `TransparentWindowBackground` 组件负责窗口透明，`.containerBackground` 是锦上添花
- macOS 15 上移除 `.containerBackground` 不影响核心功能

## Risks / Trade-offs

- **视觉差异风险** → `NSVisualEffectView` 的效果与 `GlassEffectContainer` 有差异，macOS 15 上可能看起来不够 "glass"。缓解：选择最接近的 material 类型，并允许用户反馈后微调。
- **性能风险** → `NSVisualEffectView` 的实时模糊可能比 `GlassEffectContainer` 更耗性能。缓解：只在面板展开时渲染，且面板尺寸很小（~300px 宽）。
- **维护成本** → 两套渲染路径增加了测试负担。缓解：CI 中保持 macOS 26 构建，macOS 15 兼容性通过代码审查和手动测试验证。
- **API 碎片化** → 未来 macOS 27 可能有新的 Glass API，兼容层可能需要再次调整。缓解：封装层设计为可扩展，新增版本支持只需修改封装内部。

## Migration Plan

1. 创建兼容层视图组件（`CompatibleGlassContainer.swift`、`CompatibleSymbolEffect.swift`、`CompatibleContainerBackground.swift`）
2. 逐个替换现有文件中的 macOS 26+ API 调用
3. 修改 `project.pbxproj` 中的 `MACOSX_DEPLOYMENT_TARGET` 为 15.0
4. 在 macOS 26 开发机上验证视觉效果无变化
5. 在 macOS 15 测试机上验证应用可启动、面板正常显示
6. 合并到 dev 分支

## Open Questions

- `NSVisualEffectView` 的 material 类型选择（`.sidebar` vs `.contentBackground` vs `.windowBackground`）需要实际测试看哪个最接近 Glass 效果
- macOS 15 上 `.glassEffectID` 的 namespace 动画效果是否需要替代方案（可能不需要，因为 `NSVisualEffectView` 没有等价概念）
