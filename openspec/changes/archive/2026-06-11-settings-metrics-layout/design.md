## Context

当前 `ModuleSettingsView` 使用 `ForEach` 垂直排列 `MetricSelectionRow`，每个指标一行。`MetricSelectionRow` 使用 `HStack` 包含 checkmark + title，最小高度 44px，水平内边距 14px，垂直内边距 10px。

## Goals / Non-Goals

**Goals:**
- 文案「检测项目」→「监测项目」
- 双列网格布局，每行两个指标选项
- 保持现有交互（勾选、4项限制、禁用态）

**Non-Goals:**
- 不修改 `MonitorSettings` 的数据模型
- 不修改最多4项的限制逻辑
- 不改 `MetricSelectionRow` 的组件本身（只改容器布局）

## Decisions

**Decision: 使用 SwiftUI `LazyVGrid` + `GridItem`**
- 两列等宽：`GridItem(.flexible())` × 2
- 行间距保持 0（或很小），因为每个 cell 自带内边距
- 列间距保持与现有水平 padding 一致

**Decision: 保持 `MetricSelectionRow` 不变**
- 只改外层容器从 `ForEach(VStack)` 到 `LazyVGrid`
- `MetricSelectionRow` 的样式、交互、尺寸不变
- 这样改动最小，风险最低

**Decision: 处理奇数项时的最后一行**
- `LazyVGrid` 会自动处理，第二列留空
- 不需要特殊处理

## Risks / Trade-offs

- **[Risk]** 双列布局下文字可能截断
  → **Mitigation**: `MetricSelectionRow` 已有 `.minimumScaleFactor(0.82)`，且指标名称通常较短（2-4字）

- **[Risk]** 点击区域变小
  → **Mitigation**: 每个 cell 仍保持 `minHeight: 44`，`contentShape(Rectangle())` 确保整个区域可点击
