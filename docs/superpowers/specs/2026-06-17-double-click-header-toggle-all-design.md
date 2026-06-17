# 双击 Header 全展开/全收起 — 设计文档

- 日期: 2026-06-17
- 作者: mojl
- 状态: 待实现
- 影响文件: `HagimiMonitor/MonitorPanelView.swift`

## 背景

当前 `MonitorPanelView` 中,每个指标 row(CPU、GPU、内存、存储、网络、电池)
通过单击 row 自身切换展开状态,展开状态保存在 `expandedKinds: Set<MonitorKind>`。
用户想要快速一次性展开或收起所有 row,而不是逐个点击。

## 需求

| 项 | 决定 |
|---|---|
| 触发手势 | 双击面板 Header(`SYSTEM · LIVE  HH:mm` 那一行) |
| 触发区域 | 仅 Header,不包含 row、底部按钮、其他空白处 |
| 行为 | 切换式:当前可见 row 全部已展开 → 全收起;否则 → 全展开 |
| 作用范围 | 当前可见的所有 row(`store.modules`),不含 `DisplayControlsSection` |
| 单击 Header | 不响应 |
| row 行为 | 不变,单击仍 toggle 自身 |

## 不做(YAGNI)

- 不加右键菜单
- 不加视觉提示(hover、图标)
- 不支持 Force Touch / 触摸板重按
- 不加键盘快捷键
- 不持久化展开状态(面板关闭后保持现行的"默认全收起"行为)
- `DisplayControlsSection` 不参与全展开/全收起

## 实现

仅修改 `MonitorPanelView.swift`,新增 3 个私有成员 + 改动 `header(theme:)`,
不动 row 内部、不动 `MonitorStore`、不动 `MonitorSettings`,不新增文件、
不引入新依赖。

### 1. 新增计算属性与方法

```swift
/// 当前可见 row 的 kind 集合,顺序与渲染顺序一致。
/// `store.modules` 已由 settings 过滤过,所以只取它即可。
/// `DisplayControlsSection` 不是 module,天然不在内。
private var visibleKinds: [MonitorKind] {
    store.modules.map(\.kind)
}

/// 当前是否所有可见 row 都处于展开状态。
/// 空 modules 时为 false——没有 row 可展开,双击不应被视为"已全开"。
private var allVisibleRowsExpanded: Bool {
    !visibleKinds.isEmpty
    && visibleKinds.allSatisfy { expandedKinds.contains($0) }
}

/// 切换"全展开 / 全收起"。
/// 已全展开 → 清空 expandedKinds(全收起);否则 → 写满 visibleKinds(全展开)。
/// 残留在 expandedKinds 里、当前不可见的 kind 不影响判定;全展开分支会用
/// 可见集合覆盖,残留也会被一同清掉。
private func toggleAllExpansion() {
    withAnimation(.smooth(duration: 0.18)) {
        if allVisibleRowsExpanded {
            expandedKinds.removeAll()
        } else {
            expandedKinds = Set(visibleKinds)
        }
    }
}
```

动画时长 `0.18s smooth` 沿用 `toggleExpansion(for:)` 已有节奏,保持视觉一致。

### 2. 改动 `header(theme:)`

在原 `header` 的最外层 `HStack` 之后追加两行修饰符:

```swift
.contentShape(Rectangle())   // 让 Spacer 区域也可点击
.onTapGesture(count: 2) {
    toggleAllExpansion()
}
```

`contentShape(Rectangle())` 让整条 header(含中间空白 Spacer)成为可点击区。
`onTapGesture(count: 2)` 仅响应双击,单击不触发,与现有 row 单击 toggle
不冲突。

### 3. 边界情况

| 场景 | 行为 |
|---|---|
| `store.modules` 为空(理论极端态) | 双击无效,无副作用 |
| 仅部分 row 展开 | 双击 → 全展开 |
| 用户在设置中切换模块可见性 | `expandedKinds` 中残留的不可见 kind 不影响判定;下次"全展开"会被覆盖清掉 |
| 双击落在底部按钮上 | 按钮自带事件吞噬,不会冒泡到 header,自然无副作用 |

## 测试策略

SwiftUI 视图层手势难做单元测试,且本改动逻辑极简(纯 Set 运算)。
**采用手动 QA**,不为单测改架构。

QA 清单:

1. 默认全收起 → 双击 Header → 所有 row 全展开,带动画
2. 全展开后 → 双击 Header → 全收起,带动画
3. 手动单击展开 CPU 一个 row → 双击 Header → 全展开(包括其它 row)
4. 全展开后,在设置里隐藏"电池" → `expandedKinds` 残留的电池 kind 不影响
   下一次双击仍正确切换
5. 单击 Header(单次)→ 不应有任何反应
6. 单击 row 仍能正常 toggle 自身

## 影响范围

- 改动文件: `HagimiMonitor/MonitorPanelView.swift`
- 行数: 约 +20 行
- 新依赖: 无
- 新文件: 无
- 破坏性: 无

## 风险

无明显风险。`onTapGesture(count: 2)` 是 SwiftUI 标准 API,
`contentShape` 已在项目其它地方使用过(例如 row 内部命中区域)。
