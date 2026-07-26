# Tasks: module-card-display-style

## 1. 设置层

- [x] 1.1 `MonitorSettings` 新增 `cardStyleKinds: Set<MonitorKind>`（默认空集）、`isCardStyle(_:)` / `setCardStyle(_:for:)`、UserDefaults 键 `settings.panel.cardStyleKinds` 的加载与持久化绑定（沿用 `defaultExpandedKinds` 同款模式）
- [x] 1.2 `SettingsTests` 新增显示方式默认值与持久化测试（默认空集 / 设置后重启恢复），沿用独立 suiteName 模式

## 2. 卡片视图恢复

- [x] 2.1 从 `git show 61febc61:HagimiMonitor/MonitorPanelView.swift` 摘取 `MetricCardView`、`CardProcessList` 及私有辅助（`bigValue` / `cardRate` / hero 分支等），粘回现行 `MonitorPanelView.swift`
- [x] 2.2 改造卡片：删除 `onRestore` 回调与右上角还原按钮；对照现行 theme/palette API 修正编译错误；确认电池 hero 单主值规则（有电池显示电量、无电池显示功耗，功耗恒显不重复）
- [x] 2.3 核对卡片布局硬约束：高度自适应（无 `minHeight` 强制方形）、无 GeometryReader 宽度→高度反馈环、Equatable 全字段比较

## 3. 面板接线

- [x] 3.1 `row(for:)` 顶层分流：`store.settings.cardStyleKinds.contains(kind)` 时渲染 `MetricCardView`（无 tap 手势），否则走现行紧凑行；`compatibleGlassEffectID` 沿用 `"metric-\(kind.id)"`
- [x] 3.2 新增 `listKinds`（可见 − 卡片），`allVisibleRowsExpanded` / `toggleAllExpansion` / `applyDefaultExpansion` 改基于 `listKinds`
- [x] 3.3 `reportActiveProcessKinds()` 上报 `expandedKinds ∪ (cardStyleKinds ∩ visibleKinds)`；新增 `.onChange(of: store.settings.cardStyleKinds)` 触发重报（不置位展开补间标记）

## 4. 设置 UI 与文案

- [x] 4.1 `ModuleSettingsView` 第一组新增「显示方式」分段选择行（列表行/大卡片，模块可见时才显示）；显示方式为卡片时隐藏「默认展开」行
- [x] 4.2 `Localizable.xcstrings` 新增 `settings.display-style`（显示方式）、`settings.display-style.list`（列表行）、`settings.display-style.card`（大卡片）及卡片内新增标签，补齐 zh-Hans / en / ja

## 5. 验证

- [x] 5.1 `HagimiMonitorDirect` scheme 构建通过；`SettingsTests` 串行全绿（`-parallel-testing-enabled NO`）
- [x] 5.2 `./launch.sh` 手测：默认全列表行为不变；CPU 设卡片后呼出即完整卡片；进程 5 行占位无高度跳变；双击标题区只影响列表行；钉住面板开着切显示方式底部按钮不被裁切；电池卡片无大面积空白（用户实机验证通过）
- [x] 5.3 三语环境抽查设置页与卡片文案（随 5.2 一并验证）
