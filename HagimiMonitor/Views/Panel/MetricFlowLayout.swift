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
