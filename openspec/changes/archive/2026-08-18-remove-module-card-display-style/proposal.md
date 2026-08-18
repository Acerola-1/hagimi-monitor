# 移除模块大卡片显示方式

## Why

2026-07-26 引入的「大卡片」显示方式（存档：`openspec/changes/archive/2026-07-26-module-card-display-style/`）本意是以静态配置复活当年被弃用的悬停放大卡片，提供 hero 大数字 + TOP 进程的仪表盘式呈现。实际使用后评估其价值不足以抵消持续的维护成本，决定整体移除：

- **与既有能力重叠**：大卡片本质是「常显的展开态」（hero 主值 + 指标网格 + TOP 进程）。列表行的「默认展开」设置已覆盖「呼出即摊开」的核心诉求，卡片仅多一层大字号视觉包装，边际价值低。
- **持续双份维护成本**：它为每个模块维持了第二条渲染路径——专属 `MetricCardView`（约 240 行）与 `CardProcessList`（约 90 行）。此后每新增一个特性都要双路径适配（风扇卡片分支、网络门控双路径、进程采样集合要 ∪ 卡片、展开机制要排除卡片、设置页要门控「默认展开」），耦合面随功能演进而扩大。
- **形态始终未收敛**：该形态是二次复活（悬停放大 → 静态配置），一直未沉淀出稳定、不可替代的价值点。

综上，删除大卡片以收敛渲染路径、降低后续维护负担；「希望某模块默认摊开」的诉求由既有「默认展开」能力承接。

## What Changes

- 各模块设置页移除「显示方式」分段选择（列表行 / 大卡片）
- 面板中移除大卡片渲染路径：`MetricCardView` / `CardProcessList` 及其私有辅助全部删除；`row(for:)` 不再分流，一律渲染紧凑列表行
- 移除卡片相关的展开互斥与采样记账特例：`listKinds` 恢复为全部可见模块；`reportActiveProcessKinds()` 恢复为仅上报展开的行；移除 `onChange(of: cardStyleKinds)` 重报钩子
- 「默认展开」开关恢复对所有可见模块恒显（不再因卡片档隐藏）
- 移除 `cardStyleKinds` 持久化（UserDefaults 键 `settings.panel.cardStyleKinds`）与 `isCardStyle` / `setCardStyle`；存量键不再读取，历史值自然失效
- 移除相关文案 `settings.display-style` / `.list` / `.card`（zh-Hans / en / ja）
- 移除 `SettingsTests` 中显示方式默认值与持久化测试
- 显示器模块（DirectOnly）与本功能无关，维持现状

## Capabilities

### Removed Capabilities

- `module-display-style`: 按模块的面板显示方式设置（列表行/大卡片）整体移除。其承载的「希望模块默认摊开」诉求由 `monitor-panel` / 设置侧既有「默认展开」能力承接，无需求级能力缺口。

## Impact

- `HagimiMonitor/MonitorSettings.swift`：移除 `cardStyleKinds` 及其加载/持久化绑定、`isCardStyle(_:)` / `setCardStyle(_:for:)`、`Keys.cardStyleKinds`
- `HagimiMonitor/MonitorPanelView.swift`：删除 `MetricCardView` / `CardProcessList` / `CardProcessItem` / `CardProcessMetric` 与卡片私有辅助；`row(for:)` / `listKinds` / `reportActiveProcessKinds` / `toggleAllExpansion` / `applyDefaultExpansion` 恢复纯列表行语义；移除 `onChange(of: cardStyleKinds)`
- `HagimiMonitor/Views/Settings/ModuleSettingsView.swift`：删除「显示方式」分段选择行与 `ModuleDisplayStyle` 枚举；「默认展开」行恢复恒显
- `HagimiMonitor/Localizable.xcstrings`：删除 `settings.display-style` 三键
- `HagimiMonitorTests/SettingsTests.swift`：删除显示方式默认值与持久化测试
