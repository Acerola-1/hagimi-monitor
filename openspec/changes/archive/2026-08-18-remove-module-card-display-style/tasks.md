# Tasks: remove-module-card-display-style

## 1. 设置层

- [x] 1.1 `MonitorSettings` 移除 `cardStyleKinds`、`isCardStyle(_:)` / `setCardStyle(_:for:)`、UserDefaults 键 `settings.panel.cardStyleKinds` 的加载与持久化绑定
- [x] 1.2 `SettingsTests` 移除 `cardStyleKindsDefaultsToEmptyAndPersists` 用例

## 2. 面板视图

- [x] 2.1 删除 `MetricCardView`、`CardProcessList`、`CardProcessItem`、`CardProcessMetric` 及卡片私有辅助（bigValue / cardRate / hero / processSection 等）
- [x] 2.2 `row(for:)` 移除卡片分流，一律渲染紧凑行；删除 `card(for:)`
- [x] 2.3 `listKinds` 恢复为全部可见模块；`toggleAllExpansion` / `applyDefaultExpansion` 注释与逻辑恢复纯列表语义
- [x] 2.4 `reportActiveProcessKinds()` 恢复仅上报展开行；移除 `.onChange(of: cardStyleKinds)` 重报钩子

## 3. 设置 UI 与文案

- [x] 3.1 `ModuleSettingsView` 删除「显示方式」分段选择行与 `ModuleDisplayStyle` 枚举；「默认展开」行恢复恒显
- [x] 3.2 `Localizable.xcstrings` 删除 `settings.display-style` / `settings.display-style.list` / `settings.display-style.card` 三键（三语）

## 4. 验证与归档

- [x] 4.1 双 scheme（HagimiMonitor / HagimiMonitorDirect）Debug 构建通过
- [x] 4.2 Direct scheme 跑测试（`SettingsTests` 已知 5 个在途失败除外）
- [x] 4.3 手测：面板全列表行渲染、展开/收起与默认展开正常、设置页无「显示方式」行
- [x] 4.4 `openspec archive remove-module-card-display-style` 归档并同步删除 `module-display-style` spec
