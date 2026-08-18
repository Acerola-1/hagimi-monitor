# module-display-style Spec Delta

## REMOVED Requirements

### Requirement: 按模块设置面板显示方式
**Reason**: 大卡片形态价值评估不足，与「默认展开」能力重叠，整体移除该 capability。
**Migration**: 希望模块呼出即摊开的用户改用「默认展开」开关；存量 `settings.panel.cardStyleKinds` 值不再读取，自然失效。

### Requirement: 大卡片内容常显且无展开交互
**Reason**: `MetricCardView` 渲染路径随 capability 一并删除。
**Migration**: 所有模块恢复紧凑列表行，点击展开查看明细。

### Requirement: 与「默认展开」及双击全展开互斥
**Reason**: 卡片不再存在，互斥规则失去对象。
**Migration**: 「默认展开」开关对所有可见模块恒显；双击全展开作用于全部可见模块。

### Requirement: 卡片模块参与按需进程采样
**Reason**: 进程采样集合恢复为仅「展开的列表行」。
**Migration**: 无——展开模块的按需采样语义与引入卡片前一致。

### Requirement: 卡片布局遵守窗口高度上报硬约束
**Reason**: 卡片视图删除，相关布局约束随实现一并消失。
**Migration**: 无。

### Requirement: 卡片文案三语完备
**Reason**: `settings.display-style` 三键文案随功能删除。
**Migration**: 无。
