## 1. 统一过渡动画定义

- [x] 1.1 在 `MonitorPanelView.swift` 中定义共享的 `detailDisclosure` 过渡常量（按 OS 版本分叉:macOS 26+ 用 asymmetric,macOS 15 用 `.identity`）
- [x] 1.2 修改 `MetricGlassRow`、`NetworkGlassRow`、`BatteryGlassRow` 使用共享过渡
- [x] 1.3 修改 `DisplayControlsSection` 使用相同的共享过渡,并移除重复的 `.animation(value:)` 二重驱动

## 2. 添加进度条过渡动画

- [x] 2.1 在 `ProgressMeter` 中添加 `.animation(.easeInOut(duration: 0.3), value: value)` 修饰符

## 3. 折线图过渡动画（已推翻）

- [x] 3.1 ~~在 `SparklineChart` 中添加 `.animation(value: samples)`~~ — Canvas 绘制结果无法被 SwiftUI 补间,该修饰符无效,已移除。design.md 决策 4 同此结论冲突,以本结果为准。

## 4. 优化 macOS 15 兼容层

- [x] 4.1 修改 `CompatibleGlassEffect` 移除外层 `clipShape`
- [x] 4.2 保留 `.sidebar` 材质 + `.behindWindow` 混合（诊断中验证 `.withinWindow` 不影响闪烁,故维持原材质）

## 5. 按版本隔离展开动画（macOS 15 抖动根因）

- [x] 5.1 `MonitorPanelView` 抽取 `setExpansion` 辅助:macOS 26+ 用 `withAnimation`,macOS 15 直接改状态
- [x] 5.2 `DisplayControlsSection` 抽取 `toggleExpansion` 同样按版本分叉(chevron 旋转保留)

## 6. 验证与测试

- [x] 6.1 在 macOS 15 上验证展开方向:无抖动、无闪烁 ✅
- [ ] 6.2 收起方向仍有整面板闪烁一次 ❌ — 见下方遗留问题
- [x] 6.3 构建成功,macOS 26+ Liquid Glass 未受影响

## 遗留问题:macOS 15 收起闪烁

展开方向已完全修复。收起时整个面板仍会闪烁一次,观感不佳。

**已排除**(均经真机验证无效):
- SwiftUI 动画层:`withAnimation` / `.transition`(改 `.identity` 仍闪)
- `VisualEffectView` 的 `canDrawSubviewsIntoLayer` / `layerContentsRedrawPolicy`
- glass `blendingMode`(`.behindWindow` → `.withinWindow` 仍闪)

**待完成的决定性诊断**:将窗口临时设为 `isOpaque = true` + 纯色背景。
- 不闪 → 根因是透明窗口(`isOpaque=false`/`clear`)收缩时整窗重绘闪过透明底,在保住圆角+毛玻璃前提下解决
- 仍闪 → 指向 `MenuBarExtra(.window)` 在 macOS 15 收缩时的系统级重绘,改窗口属性无解,需考虑自管 NSPanel 托管或接受限制

(上一轮不透明诊断用户反馈"没效果",但当时同时改了多处样式干扰观测,需用干净的单一变量重做该实验确认。)
