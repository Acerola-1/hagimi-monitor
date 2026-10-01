import AppKit
import SwiftUI
import os

private struct PanelMotionAdapterKey: EnvironmentKey {
    static let defaultValue = PanelMotionAdapterReference()
}

private struct PanelMotionAdapterReference {
    weak var value: (any PanelWindowSubmissionAdapter)?
}

extension EnvironmentValues {
    var panelMotionAdapter: (any PanelWindowSubmissionAdapter)? {
        get { self[PanelMotionAdapterKey.self].value }
        set { self[PanelMotionAdapterKey.self] = PanelMotionAdapterReference(value: newValue) }
    }
}

struct PanelNaturalMeasurements: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct PanelChildGroups: PreferenceKey {
    static let defaultValue: [String: PanelChildGroup] = [:]
    static func reduce(value: inout [String: PanelChildGroup], nextValue: () -> [String: PanelChildGroup]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    @ViewBuilder
    func panelMeasure(_ id: String) -> some View {

        background(
            GeometryReader { geometry in
                Color.clear.preference(key: PanelNaturalMeasurements.self, value: [id: geometry.size])
            })

    }
}

/// 显式诊断只累计自有自然测量；正式运行不进入锁或输出计数日志。
/// 内部通过 NSLock 保护 counts 字典，多线程并发采集安全。
nonisolated final class PanelLayoutCounters: @unchecked Sendable {
    static let shared = PanelLayoutCounters()
    private let enabled = ProcessInfo.processInfo.environment["HAGIMI_PANEL_BENCH"] != nil
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func measure(_ id: String) {
        guard enabled else { return }
        lock.lock()
        counts[id, default: 0] += 1
        lock.unlock()
    }

    func checkpoint() {
        guard enabled else { return }
        lock.lock()
        let result = counts
        counts.removeAll()
        lock.unlock()
        NSLog("[panel-measure] %@", result.keys.sorted().map { "\($0):\(result[$0]!)" }.joined(separator: ","))
    }
}

/// 内容更新或实际宽度改变时测量理想高度，揭示帧仅复用固定的内容提议。
struct PanelNaturalContentLayout: Layout {
    // 外壳按顶部几何定位，内容基线不参与外层对齐。
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) -> CGFloat? { nil }
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) -> CGFloat? { nil }

    var label: String = "content"
    var measurementKey: String = ""
    private static var measureLog: OSLog { OSLog(subsystem: "HagimiMonitor.Panel", category: "Geometry") }
    struct Cache {
        var width: CGFloat?
        var key: String?
        var size: CGSize = .zero
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.key = nil
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? cache.width ?? 328
        if cache.width != width || cache.key != measurementKey {
            PanelLayoutCounters.shared.measure(label)
            os_signpost(.begin, log: Self.measureLog, name: "NaturalMeasure", "%{public}s", label)
            defer { os_signpost(.end, log: Self.measureLog, name: "NaturalMeasure") }
            cache.size = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
            cache.width = width
            cache.key = measurementKey
        }
        return CGSize(width: width, height: cache.size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let size = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

/// 自然高度的失效键由内容结构和排版环境组成，普通读数更新保持同一测量版本。
struct PanelNaturalContent<Content: View>: View {
    let label: String
    var measurementKey: String = ""
    let content: Content
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var scale

    var body: some View {
        let content = self.content
        PanelNaturalContentLayout(
            label: label,
            measurementKey: "\(measurementKey)|\(locale.identifier)|\(dynamicTypeSize)|\(scale)"
        ) { content }
    }
}

struct SingleHostDetail<Content: View>: View {
    let id: String
    let isExpanded: Bool
    let available: Bool
    let content: Content
    var measurementKey: String = ""

    var body: some View {

        PanelNaturalContent(label: id, measurementKey: measurementKey, content: content)
            .panelMeasure("detail:" + id)
            .background {
                Color.clear.preference(
                    key: PanelNaturalMeasurements.self,
                    value: ["available:" + id: CGSize(width: available ? 1 : 0, height: 0)])
            }
            .allowsHitTesting(available && isExpanded)
            .accessibilityHidden(!available || !isExpanded)

    }
}

/// 父明细只组合已登记的子几何，重内容由各子分区自己的自然尺寸包装缓存。
struct SingleHostChildren: View {
    let id: String
    let isExpanded: Bool
    let group: PanelChildGroup
    @ObservedObject var motion: SingleHostMotionCoordinator
    var nativeItems: [NativePanelContentItem] = []

    var body: some View {

        NativePanelChildren(id: id, isExpanded: isExpanded, group: group, motion: motion, items: nativeItems)

    }
}

/// 控制区与档案保留各自的固定自然提议，视口在两个真实高度之间插值。
struct SingleHostReplacement<Collapsed: View, Expanded: View>: View {
    let id: String
    let isExpanded: Bool
    @EnvironmentObject private var expansion: PanelExpansionDriver
    let collapsed: Collapsed
    let expanded: Expanded

    @ViewBuilder var body: some View {

        NativePanelReplacement(
            id: id, isExpanded: isExpanded, motion: expansion.motion,
            collapsed: collapsed, expanded: expanded)

    }
}

func withPanelExpansionState(_ updates: () -> Void) {

    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)

}
