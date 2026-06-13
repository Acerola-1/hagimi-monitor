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
        guard !sizes.isEmpty else {
            return Result(frames: [], totalSize: .zero)
        }

        guard containerWidth > 0 else {
            return Result(
                frames: Array(repeating: .zero, count: sizes.count),
                totalSize: .zero
            )
        }

        let halfWidth = max(0, (containerWidth - columnSpacing) / 2)

        var frames: [CGRect] = Array(repeating: .zero, count: sizes.count)
        var cursorY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var pendingHalfIndex: Int? = nil

        for index in sizes.indices {
            let natural = sizes[index]
            let needsFullRow = natural.width > halfWidth

            if needsFullRow {
                if pendingHalfIndex != nil {
                    cursorY += rowMaxHeight + rowSpacing
                    pendingHalfIndex = nil
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
                    frames[index] = CGRect(
                        x: 0,
                        y: cursorY,
                        width: halfWidth,
                        height: natural.height
                    )
                    rowMaxHeight = max(rowMaxHeight, natural.height)
                    pendingHalfIndex = index
                } else {
                    frames[index] = CGRect(
                        x: halfWidth + columnSpacing,
                        y: cursorY,
                        width: halfWidth,
                        height: natural.height
                    )
                    rowMaxHeight = max(rowMaxHeight, natural.height)
                    cursorY += rowMaxHeight + rowSpacing
                    rowMaxHeight = 0
                    pendingHalfIndex = nil
                }
            }
        }

        var totalHeight = cursorY
        if pendingHalfIndex != nil {
            totalHeight += rowMaxHeight
        } else if cursorY > 0 {
            totalHeight -= rowSpacing
        }

        return Result(
            frames: frames,
            totalSize: CGSize(width: containerWidth, height: max(0, totalHeight))
        )
    }
}
