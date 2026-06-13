# 展开面板自适应行布局 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `MetricDetailGrid` 改为内容驱动的紧凑流式布局：长内容独占整行（detail row 左对齐紧凑形态），短内容两两并排贴右，紧凑回填，不缩字号。

**Architecture:** 把"自然尺寸 → 帧位置"的算法抽成纯函数 `MetricFlowPlacer.place(...)`（独立可测）。`MetricFlowLayout: Layout` 把 `Subviews` 的自然尺寸喂给纯函数，再放置子视图。`MetricDetailGrid` 把原 `LazyVGrid` 替换成 `MetricFlowLayout`，并删掉 `minimumScaleFactor(0.7)`。`metricCell` 用 `ViewThatFits` 根据分配宽度自适应切换两种形态：半行→贴右，整行→detail row 左对齐紧凑。

**Tech Stack:** SwiftUI `Layout` 协议（macOS 13+）、Swift Testing（`@Test` / `#expect`）。

**File Structure:**

| 文件 | 作用 |
| --- | --- |
| `HagimiMonitor/Views/Panel/MetricFlowPlacer.swift`（新增） | 纯算法：输入 `[CGSize]` 自然尺寸 + 容器宽度 + 行/列间距，输出 `[CGRect]` 帧。零 SwiftUI 依赖，可被单元测试。 |
| `HagimiMonitor/Views/Panel/MetricFlowLayout.swift`（新增） | `Layout` 协议适配器：测量子视图自然尺寸，调用 `MetricFlowPlacer`，把结果回放到 `Subviews`。 |
| `HagimiMonitor/MonitorPanelView.swift`（修改） | `MetricDetailGrid.content`：用 `MetricFlowLayout` 替代 `LazyVGrid`；`metricCell`：删除 `minimumScaleFactor(0.7)`。 |
| `HagimiMonitorTests/MetricFlowPlacerTests.swift`（新增） | 覆盖布局算法的关键场景。 |

只新增/修改这 4 个文件，不动采样器、设置、Network/Storage 行、本地化。

---

### Task 1: 新增布局算法纯函数 `MetricFlowPlacer`

**Files:**
- Create: `HagimiMonitor/Views/Panel/MetricFlowPlacer.swift`
- Test: `HagimiMonitorTests/MetricFlowPlacerTests.swift`

- [ ] **Step 1: 写第一组失败测试 - 全短内容两两并排**

`HagimiMonitorTests/MetricFlowPlacerTests.swift`:

```swift
import Foundation
import Testing
@testable import HagimiMonitor

struct MetricFlowPlacerTests {
    private let containerWidth: CGFloat = 200
    private let columnSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 6
    // halfWidth = (200 - 8) / 2 = 96

    @Test func allShortItemsPairUpInTwoColumns() {
        let sizes = [
            CGSize(width: 60, height: 16),
            CGSize(width: 50, height: 16),
            CGSize(width: 70, height: 16),
            CGSize(width: 40, height: 16)
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.count == 4)
        #expect(result.frames[0].origin == CGPoint(x: 0, y: 0))
        #expect(result.frames[0].size.width == 96)
        #expect(result.frames[1].origin == CGPoint(x: 104, y: 0))
        #expect(result.frames[1].size.width == 96)
        #expect(result.frames[2].origin == CGPoint(x: 0, y: 22))
        #expect(result.frames[3].origin == CGPoint(x: 104, y: 22))
        #expect(result.totalSize == CGSize(width: 200, height: 38))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test -only-testing:HagimiMonitorTests/MetricFlowPlacerTests`
Expected: FAIL，提示 `MetricFlowPlacer` 未定义。

- [ ] **Step 3: 写最小实现让测试通过**

`HagimiMonitor/Views/Panel/MetricFlowPlacer.swift`:

```swift
import CoreGraphics

/// 展开面板指标格子的紧凑流式布局算法。
/// 规则：
/// - 半行宽度 = (容器宽 - 列间距) / 2。
/// - 自然宽度 ≤ 半行：进入半行槽，最多两个并排。
/// - 自然宽度 > 半行：独占整行；当前若已放半行槽则先收尾再换行。
/// - 落单的半行 cell 不强制铺满，仍只占半行。
enum MetricFlowPlacer {
    struct Result: Equatable {
        var frames: [CGRect]
        var totalSize: CGSize
    }

    static func place(
        sizes: [CGSize],
        containerWidth: CGFloat,
        columnSpacing: CGFloat,
        rowSpacing: CGFloat
    ) -> Result {
        guard !sizes.isEmpty, containerWidth > 0 else {
            return Result(frames: [], totalSize: .zero)
        }

        let halfWidth = max(0, (containerWidth - columnSpacing) / 2)

        var frames: [CGRect] = Array(repeating: .zero, count: sizes.count)
        var cursorY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        // 当前行待放的半行槽 cell 索引（0 或 1 个）
        var pendingHalfIndex: Int? = nil

        func flushRow() {
            if pendingHalfIndex != nil {
                cursorY += rowMaxHeight + rowSpacing
            }
            pendingHalfIndex = nil
            rowMaxHeight = 0
        }

        for index in sizes.indices {
            let natural = sizes[index]
            let needsFullRow = natural.width > halfWidth

            if needsFullRow {
                if let half = pendingHalfIndex {
                    // 当前行已经放了一个半行 cell：收尾，再换行放整行
                    cursorY += rowMaxHeight + rowSpacing
                    pendingHalfIndex = nil
                    _ = half
                    rowMaxHeight = 0
                }
                frames[index] = CGRect(
                    x: 0,
                    y: cursorY,
                    width: containerWidth,
                    height: natural.height
                )
                cursorY += natural.height + rowSpacing
                rowMaxHeight = 0
                pendingHalfIndex = nil
            } else {
                if pendingHalfIndex == nil {
                    // 左半槽
                    frames[index] = CGRect(
                        x: 0,
                        y: cursorY,
                        width: halfWidth,
                        height: natural.height
                    )
                    rowMaxHeight = max(rowMaxHeight, natural.height)
                    pendingHalfIndex = index
                } else {
                    // 右半槽
                    frames[index] = CGRect(
                        x: halfWidth + columnSpacing,
                        y: cursorY,
                        width: halfWidth,
                        height: natural.height
                    )
                    rowMaxHeight = max(rowMaxHeight, natural.height)
                    // 行满，收尾
                    cursorY += rowMaxHeight + rowSpacing
                    rowMaxHeight = 0
                    pendingHalfIndex = nil
                }
            }
        }

        // 最后一行如果还挂着半行槽，把它的高度算进 totalHeight
        var totalHeight = cursorY
        if pendingHalfIndex != nil {
            totalHeight += rowMaxHeight
        } else if cursorY > 0 {
            // 上一次 flush 多加了一段 rowSpacing，扣掉
            totalHeight -= rowSpacing
        }

        return Result(
            frames: frames,
            totalSize: CGSize(width: containerWidth, height: max(0, totalHeight))
        )
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test -only-testing:HagimiMonitorTests/MetricFlowPlacerTests`
Expected: PASS。

- [ ] **Step 5: 补长内容独占整行的测试**

在 `MetricFlowPlacerTests.swift` 末尾追加：

```swift
    @Test func longItemTakesFullRowAndCompactsAfter() {
        // 索引 1 是长内容（150 > halfWidth 96）
        let sizes = [
            CGSize(width: 60, height: 16),   // 短，进左半槽
            CGSize(width: 150, height: 18),  // 长，独占整行（先收尾上一行）
            CGSize(width: 70, height: 16),   // 短，进新行左半槽
            CGSize(width: 40, height: 16)    // 短，进同一行右半槽
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        // 第 0 行：索引 0 在左半槽
        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 96, height: 16))
        // 第 1 行：索引 1 独占整行，y = 16 + 6 = 22
        #expect(result.frames[1] == CGRect(x: 0, y: 22, width: 200, height: 18))
        // 第 2 行：索引 2 进左半槽，y = 22 + 18 + 6 = 46
        #expect(result.frames[2] == CGRect(x: 0, y: 46, width: 96, height: 16))
        // 第 2 行：索引 3 进右半槽
        #expect(result.frames[3] == CGRect(x: 104, y: 46, width: 96, height: 16))
        // 总高 = 46 + 16 = 62
        #expect(result.totalSize == CGSize(width: 200, height: 62))
    }

    @Test func trailingOddItemKeepsHalfRow() {
        let sizes = [
            CGSize(width: 60, height: 16),
            CGSize(width: 50, height: 16),
            CGSize(width: 70, height: 18) // 落单
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames[2] == CGRect(x: 0, y: 22, width: 96, height: 18))
        // 落单 cell 仍只占半行
        #expect(result.frames[2].size.width == 96)
        #expect(result.totalSize == CGSize(width: 200, height: 40))
    }

    @Test func emptyInputReturnsZero() {
        let result = MetricFlowPlacer.place(
            sizes: [],
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.isEmpty)
        #expect(result.totalSize == .zero)
    }

    @Test func longItemAtStartTakesFullRow() {
        let sizes = [
            CGSize(width: 180, height: 18),
            CGSize(width: 50, height: 16)
        ]

        let result = MetricFlowPlacer.place(
            sizes: sizes,
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 200, height: 18))
        #expect(result.frames[1] == CGRect(x: 0, y: 24, width: 96, height: 16))
        #expect(result.totalSize == CGSize(width: 200, height: 40))
    }

    @Test func zeroContainerWidthReturnsEmpty() {
        let result = MetricFlowPlacer.place(
            sizes: [CGSize(width: 60, height: 16)],
            containerWidth: 0,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        #expect(result.frames.first?.size == .zero)
        #expect(result.totalSize == .zero)
    }
```

- [ ] **Step 6: 跑全部 placer 测试**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test -only-testing:HagimiMonitorTests/MetricFlowPlacerTests`
Expected: 6 个测试全部 PASS。如果失败，先调 `MetricFlowPlacer` 的算法再继续，不要绕过。

- [ ] **Step 7: 提交**

```bash
git add HagimiMonitor/Views/Panel/MetricFlowPlacer.swift HagimiMonitorTests/MetricFlowPlacerTests.swift
git commit -m "$(cat <<'EOF'
[新增] 展开面板指标紧凑流式布局算法 MetricFlowPlacer

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 新增 SwiftUI `Layout` 适配器 `MetricFlowLayout`

**Files:**
- Create: `HagimiMonitor/Views/Panel/MetricFlowLayout.swift`

> 说明：`Layout` 协议本身不便于直接单测（依赖 `Subviews` 的实现），但所有计算都已落在 `MetricFlowPlacer` 里被覆盖。本任务只验证编译通过；功能验证放在 Task 4 的真机/模拟运行。

- [ ] **Step 1: 写适配器实现**

`HagimiMonitor/Views/Panel/MetricFlowLayout.swift`:

```swift
import SwiftUI

/// 把 `MetricFlowPlacer` 的纯算法接到 SwiftUI 的 `Layout` 协议。
/// 半行槽放短 cell，长 cell 独占整行，紧凑回填。
struct MetricFlowLayout: Layout {
    var columnSpacing: CGFloat = 8
    var rowSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let containerWidth = proposal.width ?? 0
        guard containerWidth > 0 else { return .zero }

        let result = MetricFlowPlacer.place(
            sizes: naturalSizes(of: subviews),
            containerWidth: containerWidth,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
        return result.totalSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard bounds.width > 0 else { return }

        let result = MetricFlowPlacer.place(
            sizes: naturalSizes(of: subviews),
            containerWidth: bounds.width,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )

        for index in subviews.indices {
            let frame = result.frames[index]
            let placement = CGPoint(
                x: bounds.minX + frame.origin.x,
                y: bounds.minY + frame.origin.y
            )
            subviews[index].place(
                at: placement,
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: frame.size.width,
                    height: frame.size.height
                )
            )
        }
    }

    private func naturalSizes(of subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }
}
```

- [ ] **Step 2: 编译，确认无错误**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build`
Expected: BUILD SUCCEEDED。如果出现 `Layout` 协议、`Subviews` 相关错误，确认 `import SwiftUI` 已写。

- [ ] **Step 3: 提交**

```bash
git add HagimiMonitor/Views/Panel/MetricFlowLayout.swift
git commit -m "$(cat <<'EOF'
[新增] MetricFlowLayout：基于 MetricFlowPlacer 的 SwiftUI Layout 适配器

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 接入 `MetricDetailGrid` 并去掉缩字号

**Files:**
- Modify: `HagimiMonitor/MonitorPanelView.swift:309-373`

- [ ] **Step 1: 替换 `MetricDetailGrid` 的非网络分支**

把 `MonitorPanelView.swift` 里 `MetricDetailGrid` 当前的实现整体替换为：

```swift
private struct MetricDetailGrid: View {
    let metrics: [MonitorMetric]
    let kind: MonitorKind
    let theme: MonitorPanelTheme

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.rowSeparator(for: kind))
                .frame(height: 1)
                .padding(.leading, 28)

            content
                .padding(.leading, 28)
        }
    }

    @ViewBuilder
    private var content: some View {
        // 网络模块：长字符串（IP）改用单列 VStack，让内容主动声明宽度推动面板撑宽。
        if kind == .network {
            VStack(spacing: 6) {
                ForEach(metrics) { metric in
                    metricCell(metric, theme: theme)
                }
            }
        } else {
            MetricFlowLayout(columnSpacing: 8, rowSpacing: 6) {
                ForEach(metrics) { metric in
                    metricCell(metric, theme: theme)
                }
            }
        }
    }

    private func metricCell(_ metric: MonitorMetric, theme: MonitorPanelTheme) -> some View {
        HStack(spacing: 6) {
            Text(localizedMetricName(kind: kind, id: metric.name))
                .monitorPanelCaptionFont(.footnote)
                .foregroundStyle(theme.captionText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Text(localizedMetricValue(kind: kind, metric: metric))
                .monitorPanelMonoFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .layoutPriority(2)
                .help(localizedMetricValue(kind: kind, metric: metric))
                .contentShape(Rectangle())
                .onTapGesture {
                    copyToPasteboard(metric.value)
                }
        }
    }
}
```

关键差异（对比当前版本）：
- 删除 `private let columns = [...]` 整段。
- 非网络分支由 `LazyVGrid(columns: columns, alignment: .leading, spacing: 6) { ... }` 改为 `MetricFlowLayout(columnSpacing: 8, rowSpacing: 6) { ... }`。
- `metricCell` 中 label 与 value 的 `.minimumScaleFactor(0.7)` 全部删掉；其余保留。

- [ ] **Step 2: 编译**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 跑全部已有单测，确保没有回归**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug test`
Expected: 所有测试 PASS（包含 Task 1 新增的 6 个）。

- [ ] **Step 4: 提交**

```bash
git add HagimiMonitor/MonitorPanelView.swift
git commit -m "$(cat <<'EOF'
[优化] 展开面板指标改用 MetricFlowLayout，长内容独占整行不再缩字号

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `metricCell` 双形态 — 短半行贴右 / 长 detail row 左对齐紧凑

**背景修订（2026-06-13）：**
Task 1-3 已上线后人工验证发现：长 cell 独占整行时仍沿用 `HStack { label, Spacer, value }` 形态，会在中间留出大段空白；同行/相邻行的 value 锚点又在 halfWidth、fullWidth 之间跳变，节奏不齐。

修订思路（已写入 spec § 方案 § 3）：**双 cell 语法**——
- 半行 cell（短指标）保持 `label + Spacer + value 贴右`，与现状一致。
- 整行 cell（长指标）改为 `HStack(spacing: 6) { label, value, Spacer(minLength: 0) }`，label 紧贴 value 左对齐，右侧空白。
- **不强求**长 detail row 与上下行的 value 锚点对齐——通过形态差异（左对齐紧凑 vs 贴右）让用户视觉识别它是"详情行"，而非"被拉宽的格子"。

判定方式：cell 自己读取 SwiftUI 分配的宽度，与 cell 自身自然宽度比较。若分配宽度远大于自然宽度（差距 ≥ 24pt），即说明它被分到了整行，切换 detail row 形态；否则按半行形态渲染。这种"cell 内部自适应"实现与 `MetricFlowLayout` 完全解耦，不需要给 Layout 协议加额外环境值。

**Files:**
- Modify: `HagimiMonitor/MonitorPanelView.swift`，`MetricDetailGrid.metricCell`（约第 344-365 行）

- [ ] **Step 1: 改 `metricCell` 为根据分配宽度切换形态**

把 `MetricDetailGrid` 中的 `metricCell(_:theme:)` 整体替换为：

```swift
    private func metricCell(_ metric: MonitorMetric, theme: MonitorPanelTheme) -> some View {
        let labelText = localizedMetricName(kind: kind, id: metric.name)
        let valueText = localizedMetricValue(kind: kind, metric: metric)

        let label = Text(labelText)
            .monitorPanelCaptionFont(.footnote)
            .foregroundStyle(theme.captionText)
            .lineLimit(1)
            .layoutPriority(1)

        let value = Text(valueText)
            .monitorPanelMonoFont(.footnote, weight: .semibold)
            .foregroundStyle(theme.secondaryText)
            .lineLimit(1)
            .layoutPriority(2)
            .help(valueText)
            .contentShape(Rectangle())
            .onTapGesture {
                copyToPasteboard(metric.value)
            }

        return ViewThatFits(in: .horizontal) {
            // detail row 形态：要求 label/value 之外右侧再留 ≥24pt 空白；
            // 半行槽（~120pt）通常容不下，会回退到下面的贴右形态。整行（~240pt）一般容得下。
            HStack(spacing: 6) {
                label
                value
                Spacer(minLength: 24)
            }
            // 半行贴右形态：label 左 + Spacer 撑开 + value 右
            HStack(spacing: 6) {
                label
                Spacer(minLength: 4)
                value
            }
        }
    }
```

要点：
- `ViewThatFits(in: .horizontal)` 按顺序尝试候选；第一个能放下就用第一个，否则尝试下一个。
- 第一个候选（detail row）右侧 `Spacer(minLength: 24)` 等于 "label + 6 + value + 24 ≤ 分配宽度" 才视为放得下。
- 半行槽宽度 ≈ 120pt，对短 label/value 一般容不下这 24pt 余量 → 回退到第二个候选（贴右形态）。
- 整行宽度 ≈ 240pt，对长内容（uptime 这种）通常仍有 ≥24pt 余量 → 用 detail row 左对齐紧凑形态。
- 如果实测发现短指标也意外切到了 detail row（或反之），调整阈值即可，先试 24，不行再尝试 32 / 48。


- [ ] **Step 2: 编译验证**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitorDirect -configuration Debug build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 跑测试确认无回归**

Run: `xcodebuild -project hagimi-monitor.xcodeproj -scheme HagimiMonitor -configuration Debug test`
Expected: 全部测试 PASS（含 `MetricFlowPlacerTests` 6/6）。

- [ ] **Step 4: 启动 dev 版手工核验**

Run: `./launch.sh`，等应用就绪。

操作：
1. 展开 CPU 模块（启用了 uptime）。

Expected:
- uptime 这一行独占整行，**label 紧挨 value 左对齐**，右侧留空白；中间不再出现大段空洞。
- 同模块内的短指标（如 `temperature`、`processes`）仍两两并排、value 贴右。
- 落单短 cell 只占半行、value 贴 halfWidth 列。
- 长 detail row 的 value 与上下行的 value 列**不对齐**——这是设计预期，通过形态差异区分两种行型。
- 视觉读起来比修订前整齐：每行只有"两个贴右短 cell"或"一个左对齐 detail row"两种状态，节奏稳定。

如果 uptime 仍然显示成"label 左 / value 右"贴边模式（中间空洞），说明 `ViewThatFits` 没按预期切到 detail row：
- 把 detail row 候选里的 `Spacer(minLength: 24)` 阈值适当提高（比如 32 或 48），让它在半行槽里更容易被否决。
- 用 Xcode View Debugger 看一下 cell 实际拿到的分配宽度。

- [ ] **Step 5: 提交**

```bash
git add HagimiMonitor/MonitorPanelView.swift
git commit -m "$(cat <<'EOF'
[优化] 长指标 cell 改为左对齐紧凑 detail row 形态

短指标保持 label 左 + value 右贴边；超过半行的 metric 切换为
label 紧挨 value 左对齐、右侧留白的 detail row，避免整行 cell
中间出现大段空白。

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 真机/本地运行手工验证

**Files:** 无修改，仅运行验证。

- [ ] **Step 1: 启动开发版**

Run: `./launch.sh`
Expected: 菜单栏出现 HagimiMonitor 图标，点击展开面板。

- [ ] **Step 2: 验证 CPU 模块 uptime（detail row 形态）**

操作：
1. 在面板里点击 CPU 行展开。
2. 在设置里启用 `uptime`（如未启用），重新观察。

Expected:
- `uptime` 独占整行，且为 **左对齐紧凑形态**：label 紧贴 value，右侧留空。
- 文本不再被压成 70% 字号，也不再以省略号结尾。
- 与上下行短 cell 的 value **不强求列对齐**，但因为形态差异（贴右 vs 左对齐紧凑），整体读起来仍然整齐。

- [ ] **Step 3: 验证短指标仍两两并排贴右**

操作：在 GPU 或 Memory 模块展开短指标（如 `usage`、`free`、`total`、`used`）。

Expected:
- 短指标继续两两并排，value 贴右。
- 落单的短指标只占半行，value 贴 halfWidth 列。
- 行高、间距与改动前差异最小。

- [ ] **Step 4: 验证 Network / Storage 未受影响**

操作：分别展开 Network 和 Storage 模块。

Expected:
- Network 详情仍是单列竖排，value 贴右，未变。
- Storage 详情仍是 `StorageVolumeDetailList` 卷信息样式，未变。

- [ ] **Step 5: 重新打开面板**

操作：关闭并重新展开面板，多次切换不同模块。

Expected:
- 重排后短/长内容仍按规则分布。
- 不出现错位、重叠、长 cell 中间空洞的问题。

- [ ] **Step 6: 如以上任一项失败**

不要"调样式糊弄"。回到 Task 4，把 `ViewThatFits` 阈值或形态结构调对再重测。

- [ ] **Step 7: 全部通过后在 PR 描述写验证记录**

例：`已手工验证：CPU uptime 独占整行 detail row 左对齐无空洞；短指标两两并排贴右；Network/Storage 未变。`

无需额外提交。

---

## Self-Review

**1. Spec coverage**

| Spec 要求 | 对应任务 |
| --- | --- |
| 新增 `MetricFlowLayout`（自定义 Layout） | Task 2（算法在 Task 1） |
| 半行宽度 = `(containerWidth - columnSpacing) / 2`，间距 8 / 6 | Task 1 Step 3 实现，Task 1 Step 1/5 测试 |
| 长内容独占整行；当前行已有半行槽则先收尾 | Task 1 Step 5 `longItemTakesFullRowAndCompactsAfter` |
| 短内容紧凑回填、不固定位置 | Task 1 Step 5 同上测试覆盖 |
| 落单半行 cell 不拉满 | Task 1 Step 5 `trailingOddItemKeepsHalfRow` |
| 修改 `MetricDetailGrid`：删除 `columns`，非网络分支用新布局 | Task 3 Step 1 |
| 修改 `metricCell`：删除 `.minimumScaleFactor(0.7)` | Task 3 Step 1 |
| `lineLimit(1)` + `.help` + 复制保留 | Task 3 Step 1（在重写后的 cell 中保留） |
| Network 单列保持不变 | Task 3 Step 1（`if kind == .network` 分支未改） |
| Storage `StorageVolumeDetailList` 不动 | 全程未触碰 |
| 不新增本地化字符串 | 计划中无新增可见文本 |
| 不引入用户开关 | 计划中无 settings 改动 |
| 单元测试覆盖：全短、长内容独占、落单半行、容器宽度变化 | Task 1 Step 1 / 5（含 `zeroContainerWidthReturnsEmpty`、`longItemAtStartTakesFullRow` 覆盖宽度边界） |
| UI 目测验证 CPU uptime 不再省略号 | Task 4 Step 2 |

无遗漏。

**2. Placeholder scan**

无 "TBD"、"TODO"、"以后补"、"类似 Task N" 等空话。每一步都给出了具体代码 / 命令 / 期望结果。

**3. Type consistency**

- `MetricFlowPlacer.place(sizes:containerWidth:columnSpacing:rowSpacing:)` 在 Task 1 定义，在 Task 2 `MetricFlowLayout` 中以同名参数调用。
- `MetricFlowPlacer.Result { frames, totalSize }` 在 Task 1 定义，在 Task 2 使用 `result.totalSize` / `result.frames[index]`，字段名一致。
- `MetricFlowLayout(columnSpacing: 8, rowSpacing: 6)` 的两个参数名与 Task 2 结构体定义一致；Task 3 调用方使用相同参数名。

一致性 OK。
