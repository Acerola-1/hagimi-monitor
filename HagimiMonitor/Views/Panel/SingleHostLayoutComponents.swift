import SwiftUI

// MARK: - Layout Value Keys

struct SectionIDLayoutKey: LayoutValueKey {
    static let defaultValue: String = ""
}

extension View {
    func sectionLayoutID(_ id: String) -> some View {
        layoutValue(key: SectionIDLayoutKey.self, value: id)
    }
}

// MARK: - AccordionLayout

/// 主体手风琴布局：读取 PanelFrame 中计算好的绝对卡片矩形并直接放置，
/// 根尺寸等于 bodyDocumentHeight，不向上级反馈变化的自然尺寸。
struct AccordionLayout: Layout {
    // 外壳按顶部几何定位，内容基线不参与外层对齐。
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    let cardFrames: [String: CGRect]
    let documentHeight: CGFloat
    let cardWidth: CGFloat
    var naturalHeights: [String: CGFloat] = [:]
    var group = PanelChildGroup(ids: [], leading: 0)

    struct Cache {
        var initialFrames: [String: CGRect] = [:]
        var key = ""
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func prepareInitialFrames(subviews: Subviews, cache: inout Cache) {
        let ids = subviews.map { $0[SectionIDLayoutKey.self] }
        guard ids.contains(where: { cardFrames[$0] == nil }) else { return }
        let key = "\(ids)|\(cardWidth)|\(group)"
        guard cache.key != key else { return }
        cache.key = key
        cache.initialFrames.removeAll()
        var y = group.top
        let width = max(0, cardWidth - group.leading - group.trailing)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            cache.initialFrames[subview[SectionIDLayoutKey.self]] = CGRect(x: group.leading, y: y, width: width, height: size.height)
            y += size.height + group.spacing
        }
    }

    var fittedSize: CGSize {
        CGSize(width: cardWidth, height: documentHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        prepareInitialFrames(subviews: subviews, cache: &cache)
        return cardFrames.isEmpty
            ? CGSize(width: cardWidth, height: (cache.initialFrames.values.map(\.maxY).max() ?? 0) + group.bottom)
            : fittedSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        prepareInitialFrames(subviews: subviews, cache: &cache)
        for subview in subviews {
            let id = subview[SectionIDLayoutKey.self]
            if let frame = cardFrames[id] ?? cache.initialFrames[id] {
                subview.place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: frame.width, height: naturalHeights[id] ?? frame.height)
                )
            }
        }
    }
}

// MARK: - PanelChromeLayout

/// 面板骨架布局：固定顶部 Header，并将主体 ScrollView 约束在视口高度内。
struct PanelChromeLayout: Layout {
    // 外壳按顶部几何定位，内容基线不参与外层对齐。
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    let headerHeight: CGFloat
    let viewportHeight: CGFloat
    let panelWidth: CGFloat
    static let headerToBodySpacing: CGFloat = 4

    var fittedSize: CGSize {
        let totalH = headerHeight + Self.headerToBodySpacing + viewportHeight
        return CGSize(width: panelWidth, height: totalH)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        fittedSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        // subview[0]: Header
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: panelWidth, height: headerHeight)
        )
        // subview[1]: ScrollView
        let bodyOrigin = CGPoint(x: bounds.minX, y: bounds.minY + headerHeight + Self.headerToBodySpacing)
        subviews[1].place(
            at: bodyOrigin,
            proposal: ProposedViewSize(width: panelWidth, height: viewportHeight)
        )
    }
}

struct PanelRevealHeightKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// 行外壳返回可见高度，行头收到完整固定提议，明细视口独立决定自己的揭示高度。
struct PanelCardLayout: Layout {
    // 外壳按顶部几何定位，内容基线不参与外层对齐。
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    let measurementKey: String
    struct Cache {
        var width: CGFloat?
        var key: String?
        var headerHeight: CGFloat = 0
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? cache.width ?? 0
        if cache.width != width || cache.key != measurementKey {
            cache.headerHeight = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
            cache.width = width
            cache.key = measurementKey
        }
        let reveal = subviews.count > 1 ? subviews[1][PanelRevealHeightKey.self] : 0
        return CGSize(width: width, height: cache.headerHeight + reveal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        _ = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: cache.headerHeight))
        if subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + cache.headerHeight), anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: 0))
        }
    }
}

struct PanelCardStack<Content: View>: View {
    let measurementKey: String
    let content: Content
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale
    init(measurementKey: String = "", @ViewBuilder content: () -> Content) {
        self.measurementKey = measurementKey
        self.content = content()
    }
    var body: some View {
        let content = self.content
        let layout = PanelMotionExperiment.enabled
            ? AnyLayout(PanelCardLayout(measurementKey: "\(measurementKey)|\(locale.identifier)|\(typeSize)|\(scale)"))
            : AnyLayout(VStackLayout(spacing: 0))
        layout { content }
    }
}

/// 指标数量有限且按登记表固定分列，完整尺寸与滚动视口无关。
struct PanelMetricColumns<Content: View>: View {
    let measurementKey: String
    @ViewBuilder let content: () -> Content
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale

    var body: some View {
        if PanelMotionExperiment.enabled {
            PanelMetricColumnsLayout(measurementKey: "\(measurementKey)|\(locale.identifier)|\(typeSize)|\(scale)") {
                content()
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: MetricGridMetrics.columnSpacing),
                                GridItem(.flexible())], spacing: MetricGridMetrics.gridRowGap) {
                content()
            }
        }
    }
}

struct PanelMetricColumnsLayout: Layout {
    let measurementKey: String
    struct Cache {
        var width: CGFloat?
        var key: String?
        var sizes: [CGSize] = []
        var rowHeights: [CGFloat] = []
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    private func measure(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width || cache.key != measurementKey || cache.sizes.count != subviews.count else { return }
        let cellWidth = max(0, (width - MetricGridMetrics.columnSpacing) / 2)
        cache.sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)) }
        cache.rowHeights = stride(from: 0, to: cache.sizes.count, by: 2).map { index in
            max(cache.sizes[index].height, index + 1 < cache.sizes.count ? cache.sizes[index + 1].height : 0)
        }
        cache.width = width
        cache.key = measurementKey
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? cache.width ?? 0
        measure(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.rowHeights.reduce(0, +)
            + CGFloat(max(0, cache.rowHeights.count - 1)) * MetricGridMetrics.gridRowGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        measure(width: bounds.width, subviews: subviews, cache: &cache)
        let cellWidth = max(0, (bounds.width - MetricGridMetrics.columnSpacing) / 2)
        var y = bounds.minY
        for index in subviews.indices {
            let rowHeight = cache.rowHeights[index / 2]
            let x = bounds.minX + CGFloat(index % 2) * (cellWidth + MetricGridMetrics.columnSpacing)
            subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - cache.sizes[index].height) / 2),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: cellWidth, height: cache.sizes[index].height))
            if index % 2 == 1 { y += rowHeight + MetricGridMetrics.gridRowGap }
        }
    }

    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
}
