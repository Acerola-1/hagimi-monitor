# 技术设计：模块大卡片显示方式

## Context

- 面板视图 `MonitorPanelView` 常驻 NSPanel（菜单栏面板 / 钉住面板各一份实例），显隐为窗口级 order；行渲染入口 `row(for:)` 按 kind 分流到各 GlassRow
- 旧大卡片实现完整存于 git 历史 `61febc61`：`MetricCardView`（hero + `MetricDetailGrid(isCompact: false)` + `CardProcessList`）、`CardProcessList`（固定 5 行横杠占位）；其依赖的 `MetricDetailGrid`（含 `isCompact` 参数）、`SparklineChart`、`ProgressMeter` 在当前代码中全部健在，恢复面仅限卡片本体与接线
- 既有按需采样记账：视图经 `reportActiveProcessKinds()` → `store.updateExpandedKinds(_:for:)` 按来源上报需进程采样的 kind 集合；该机制当年即按「展开 ∪ 放大」设计
- 刚合入（未发版）的「默认展开」：`defaultExpandedKinds: Set<MonitorKind>`，面板隐藏时经 `applyDefaultExpansion()` 重置展开状态
- 窗口动画分工（硬约束）：内容瞬时上报尺寸，用户 toggle 的展开走 `panelExpansionDuration` 补间（`beginExpansionAnimation` 一次性标记），数据驱动的尺寸变化走 0 时长动画组瞬时贴合并抢占在途补间

## Goals / Non-Goals

**Goals:**

- 用户可按模块把面板呈现从「列表行」切换为「大卡片」，设置持久化
- 卡片内容常显（hero + 指标网格 + TOP 进程），零新增交互层，面板交互维持「点击展开」单层
- 与「默认展开」「双击全展开」无冲突：卡片模块退出这两个机制的作用域
- 卡片模块参与按需进程采样（面板可见期间视同展开）

**Non-Goals:**

- 不复活拖拽撕离 / 独立窗口（DetachedPanelController 全家）
- 不复活悬停放大浮标与 `enlargedKinds` 运行时交互态
- 显示器模块（DirectOnly `DisplayControlsSection`）不参与
- 不做卡片内布局的重新设计（沿用 61febc61 已调优的 hero 版式与「高度自适应、禁止强制方形」结论）

## Decisions

### D1 存储模型：`cardStyleKinds: Set<MonitorKind>`，不引入枚举字典

仅两种显示方式，沿用 `visibleKinds` / `defaultExpandedKinds` 的既有模式（`@Published private(set) Set` + rawValue 数组持久化，键 `settings.panel.cardStyleKinds`），提供 `isCardStyle(_:)` / `setCardStyle(_:for:)`。
备选 `[MonitorKind: DisplayStyle]` 字典被否：三态需求出现前是过度设计；设置页的分段选择器在 UI 层用局部枚举 `list/card` 映射集合成员即可。

### D2 设置 UI：分段选择器置于「在面板中显示」组内，卡片档隐藏「默认展开」行

`ModuleSettingsView` 第一组内追加「显示方式」`SettingsRow`（Picker.segmented：列表行/大卡片），模块隐藏时随组内其他行一起隐藏。选卡片时**隐藏**「默认展开」行（不清除 `defaultExpandedKinds` 持久值，切回列表行即恢复生效）——用户已确认采用「两个独立设置 + 条件显隐」而非三态合并。

### D3 面板渲染：`row(for:)` 顶层按 `cardStyleKinds` 分流，卡片无手势

命中卡片的 kind 渲染改造版 `MetricCardView`（剥离 `onRestore` 按钮、悬停浮标、拖拽 modifier），不挂 `onTapGesture`，不参与 `CollapsibleDetail`。`compatibleGlassEffectID` 沿用 `"metric-\(kind.id)"`，行↔卡切换时玻璃容器可做形变过渡。
卡片 TOP 进程显隐仍尊重各模块的 `showXXXProcesses` 设置（与旧实现一致）。

### D4 展开机制作用域收窄到列表行

- `listKinds = visibleKinds − cardStyleKinds`（渲染序）
- `allVisibleRowsExpanded` / `toggleAllExpansion` / `applyDefaultExpansion` 的目标集合全部改基于 `listKinds`；卡片 kind 若残留在 `expandedKinds` 中无渲染影响，且会在下一次 `applyDefaultExpansion` 重置时被清掉
- `reportActiveProcessKinds()` 上报 `expandedKinds ∪ (cardStyleKinds ∩ visibleKinds)`，并新增 `.onChange(of: store.settings.cardStyleKinds)` 触发重报——切到卡片立即开始进程采样、切回且未展开则停

### D5 显示方式切换的窗口尺寸：数据驱动路径，瞬时贴合

设置页切换显示方式属配置驱动（非面板内用户 toggle），不置位 `beginExpansionAnimation`，走既有 0 时长动画组瞬时贴合路径。菜单栏面板通常此刻隐藏（打开设置会关面板），后台贴合无感；钉住面板可见时接受一次瞬时高度变化，避免与「窗口补间仅服务用户 toggle」的既有分工冲突。

### D6 恢复方式：从 `git show 61febc61` 摘取而非 revert

`b48424d0` 是整删提交，直接 revert 会连撕离/浮标一起带回。从历史版本文件中仅摘 `MetricCardView`、`CardProcessList` 及其私有辅助（`bigValue` / `cardRate` 等），按现行代码调整（如 `localizedNetworkInterface` 等辅助函数的现状核对）。电池卡片遵守单主值规则：有电池显示电量百分比，无电池显示实时功耗，功耗恒显且不与百分比重复。

## Risks / Trade-offs

- [卡片引入后面板高度显著增加，多模块设卡片时可能超出屏幕可视高度] → 面板本就支持内容自适应+屏幕边缘回收；不做数量限制，交由用户自行取舍（与「模块全部展开」同性质）
- [恢复的旧代码与现行 palette/theme API 有细节漂移] → 编译期即暴露；逐一对照现行 GlassRow 的用法修正，不引入新 API
- [GeometryReader 反馈环旧病复发导致底部按钮被裁] → 硬约束写入 spec：卡片布局仅允许静态尺寸约束（`.frame(maxWidth: .infinity)` 等），禁止自测宽度回写高度
- [卡片模块常驻进程采样增加空转开销] → 仅面板可见时上报（既有 `isPanelVisible` guard 已挡住隐藏期采样），与展开行为同一预算
- [每秒采样刷新导致卡片整卡重绘] → 沿用旧实现的 Equatable 全字段比较跳帧，theme 用 ThemeCache 稳定实例

## Migration Plan

无数据迁移：新键默认空集，全部模块维持列表行，行为与现版完全一致。回滚 = 移除新键读写与卡片分流（`defaultExpandedKinds` 不受影响）。

## Open Questions

（无——卡片交互形态、设置形态均已与用户确认：内容常显不可收起；两个独立设置 + 条件显隐）
