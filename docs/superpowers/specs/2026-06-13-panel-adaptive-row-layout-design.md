# 展开面板自适应行布局

日期：2026-06-13
状态：待实现

## 背景与问题

`MonitorPanelView.swift` 的 `MetricDetailGrid`（约 309 行）目前用固定 2 列 `LazyVGrid` 渲染 CPU / GPU / Memory / Battery 模块展开后的指标格子，每个 cell 同时给 label 和 value 都加了 `lineLimit(1)` + `minimumScaleFactor(0.7)`。

后果：长内容（如 CPU 启动时间 uptime、长版本号）先被压成 70% 字号，仍塞不下时再被截成省略号。视觉上字号忽大忽小，且关键信息看不全。

## 目标

- 长内容自动独占整行，避免缩字和省略号。
- 短内容继续两两并排，不浪费空间。
- 不固定 cell 位置：保持原有顺序，但能塞进半行就塞，紧凑回填。
- 范围只覆盖出问题的 `MetricDetailGrid`，不影响其它模块。

## 非目标

- 不引入用户可调的布局开关。行为完全自动。
- 不改采样、设置、菜单栏图标、Network / Storage 行的现有结构。
- 不重排指标顺序。

## 方案

### 1. 新增 `MetricFlowLayout`

实现 SwiftUI `Layout` 协议（macOS 26+ 已可用），文件位置：`HagimiMonitor/Views/Panel/MetricFlowLayout.swift`。

行为：

1. 容器宽度由 `proposal.width` 给定。
2. 半行宽度 `halfWidth = (containerWidth - columnSpacing) / 2`，`columnSpacing = 8`。
3. 遍历每个子视图，调 `subview.sizeThatFits(.unspecified)` 拿自然宽度 `naturalWidth`：
   - 若 `naturalWidth > halfWidth` → 当前如果已经放了 1 个半行 cell，先收尾该行；本 cell 独占整行（宽度 = `containerWidth`）。
   - 若 `naturalWidth ≤ halfWidth` → 进入半行槽：
     - 如果当前行还有空槽（最多 2 个）→ 占下一个半行槽。
     - 没空槽 → 换新行，从左半槽开始。
4. 行高 = 该行内 cell 的最大自然高度。
5. 行间距 `rowSpacing = 6`，与现 `LazyVGrid(spacing: 6)` 一致。

要点：

- 不强行把"落单的半行 cell"拉成整行——它就只占半行（用户已确认）。
- 半行槽的 cell 渲染宽度统一给 `halfWidth`，整行 cell 渲染宽度给 `containerWidth`。这样 cell 内的 `Spacer(minLength: 4)` 自然把 label 和 value 推开。
- `placeSubviews` 用 `.proposal(.init(width: assignedWidth, height: nil))` 把分配宽度回喂给 cell，再调 `dimensions(in:)` 取实际高度。

### 2. 修改 `MetricDetailGrid`

`MonitorPanelView.swift:309-373`：

- `private let columns = ...` 删除。
- `content` 的非网络分支由 `LazyVGrid(columns: columns, ...)` 改为：
  ```swift
  MetricFlowLayout(columnSpacing: 8, rowSpacing: 6) {
      ForEach(metrics) { metric in
          metricCell(metric, theme: theme)
      }
  }
  ```
- 网络分支保持单列 `VStack`，不动。

### 3. 修改 `metricCell`

`MonitorPanelView.swift:349-372`：

- 删除 label 的 `minimumScaleFactor(0.7)`。
- 删除 value 的 `minimumScaleFactor(0.7)`。
- `lineLimit(1)` 保留：极端兜底——单个 cell 自然宽度 > 整行宽度时仍会用省略号 + `.help` tooltip。这种情况在新布局里很罕见（容器宽度由面板宽度决定，整行通常足够）。
- `layoutPriority`、`.contentShape`、点击复制、`.help`：保持不动。

测量上，`HStack` 自带的内禀尺寸就是 label + spacer 最小值（4pt）+ value 的总宽，能正确反映"实际需要多宽"。

### 4. 不变项

- `StorageVolumeDetailList`（storage 详情）不动。
- `NetworkGlassRow`（network 详情）保持现有单列 VStack。
- `MetricGlassRow` 外壳、动画、玻璃效果不动。
- `MonitorMetric` 数据结构、采样器、设置不动。

## 边界与异常

- **空 metrics 列表**：现状已被 `if isExpanded, !details.isEmpty` 守住（`MonitorPanelView.swift:241`），布局不会被空数据触发。
- **整行也塞不下的极端长 value**：保留 `lineLimit(1)` + `.help`，至少能 tooltip 看全。
- **窗口宽度变化**：自定义 Layout 是基于 `proposal.width` 实时计算的，面板宽度变了重排即可，不需要额外缓存。
- **macOS 版本**：项目已要求 macOS 26+，`Layout` 协议（macOS 13+）和 `GlassEffect`（26+）均可用。

## 测试

新增单元测试 `HagimiMonitorTests/MetricFlowLayoutTests.swift`，构造若干 mock cell 自然尺寸，验证：

1. 全短内容 → 两两并排，行数 = ⌈n/2⌉。
2. 单个长内容 → 该 cell 独占整行；它前后短 cell 紧凑回填。
3. 落单短 cell → 只占半行，不拉满。
4. 容器宽度变化 → 半行宽度跟着变。

UI 层目测验证：CPU 模块展开，含 uptime 的实际显示是独占整行、不再省略号。

## 影响面

- 受影响文件：
  - 新增 `HagimiMonitor/Views/Panel/MetricFlowLayout.swift`
  - 修改 `HagimiMonitor/MonitorPanelView.swift` 的 `MetricDetailGrid` 与 `metricCell`
  - 新增 `HagimiMonitorTests/MetricFlowLayoutTests.swift`
- 不影响：采样链路、设置、本地化（无新增可见字符串）、菜单栏图标、其它模块行。

## 本地化

本次改动无新增用户可见文本，无需更新 `Localizable.xcstrings`。
