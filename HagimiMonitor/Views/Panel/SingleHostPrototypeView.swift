import AppKit
import SwiftUI
import os

/// 原生实验开关仅选择运动与布局路径，行内容和材质继续使用生产组件。
enum PanelMotionExperiment {
    static let enabled = ProcessInfo.processInfo.environment["HAGIMI_PANEL_SINGLE_HOST"] == "1"
}

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
        if PanelMotionExperiment.enabled {
            background(GeometryReader { geometry in
                Color.clear.preference(key: PanelNaturalMeasurements.self, value: [id: geometry.size])
            })
        } else {
            self
        }
    }
}

/// 实验采集仅累计自有自然测量，关闭实验采集时不进入锁或输出日志。
final class PanelLayoutCounters: @unchecked Sendable {
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
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }

    var label: String = "content"
    var measurementKey: String = ""
    private static var measureLog: OSLog { OSLog(subsystem: "HagimiMonitor.Panel", category: "Geometry") }
    struct Cache {
        var width: CGFloat?
        var key: String?
        var size: CGSize = .zero
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}
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
        PanelNaturalContentLayout(label: label,
            measurementKey: "\(measurementKey)|\(locale.identifier)|\(dynamicTypeSize)|\(scale)") { content }
    }
}

/// 视口只裁剪明细；其宽度直接继承所在层的实际提议，包含嵌套缩进。
struct DetailViewportLayout: Layout {
    // 外壳按顶部几何定位，内容基线不参与外层对齐。
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    let height: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: max(0, height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

struct SingleHostDetail<Content: View>: View {
    let id: String
    let isExpanded: Bool
    let available: Bool
    let content: Content
    let presentation: PanelDetailPresentation
    var measurementKey: String = ""

    var body: some View {
        PanelDetailViewport(isExpanded: isExpanded, available: available,
                            presentation: presentation,
                            content: PanelNaturalContent(label: id, measurementKey: measurementKey, content: content)
                                .panelMeasure("detail:" + id))
            .background {
                Color.clear.preference(key: PanelNaturalMeasurements.self,
                    value: ["available:" + id: CGSize(width: available ? 1 : 0, height: 0)])
            }
    }
}

/// 帧订阅止于裁剪包装，内容值在外层构造，保持测量子树的依赖稳定。
private struct PanelDetailViewport<Content: View>: View {
    let isExpanded: Bool
    let available: Bool
    @ObservedObject var presentation: PanelDetailPresentation
    let content: Content

    var body: some View {
        let height = available ? presentation.sample.revealHeight : 0
        let content = self.content
        DetailViewportLayout(height: height) { content }
            .layoutValue(key: PanelRevealHeightKey.self, value: height)
            .opacity(height > 0 ? presentation.sample.opacity : 0)
            .clipped(antialiased: false)
            .contentShape(Rectangle())
            .allowsHitTesting(available && isExpanded && height > 0)
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!available || !isExpanded || height == 0)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// 父明细只组合已登记的子几何，重内容由各子分区自己的自然尺寸包装缓存。
struct SingleHostChildren<Content: View>: View {
    let id: String
    let isExpanded: Bool
    let group: PanelChildGroup
    @ObservedObject var motion: SingleHostMotionCoordinator
    let content: Content

    var body: some View {
        PanelDetailViewport(isExpanded: isExpanded, available: !group.ids.isEmpty,
                            presentation: motion.presentation(for: id), content:
            AccordionLayout(cardFrames: motion.currentFrame?.childFrames ?? [:],
                            documentHeight: motion.currentFrame?.detailContentHeights[id] ?? 0,
                            cardWidth: motion.registry.makeSnapshot()?.width(for: id) ?? motion.registry.panelWidth - 12,
                            naturalHeights: motion.registry.makeSnapshot()?.sections.mapValues(\.totalNaturalHeight) ?? [:],
                            group: group) { content })
        .background { Color.clear.preference(key: PanelChildGroups.self, value: [id: group]) }
        .background {
            Color.clear.preference(key: PanelNaturalMeasurements.self, value: [
                "detail:" + id: .zero,
                "available:" + id: CGSize(width: group.ids.isEmpty ? 0 : 1, height: 0)
            ])
        }
    }
}

/// 控制区与档案保留各自的固定自然提议，视口在两个真实高度之间插值。
struct SingleHostReplacement<Collapsed: View, Expanded: View>: View {
    let id: String
    let isExpanded: Bool
    let measurementKey: String
    @ObservedObject var presentation: PanelDetailPresentation
    let collapsed: Collapsed
    let expanded: Expanded

    var body: some View {
        let phase = presentation.sample.opacity
        let height = presentation.sample.revealHeight
        DetailViewportLayout(height: height) {
            ZStack(alignment: .topLeading) {
                PanelNaturalContent(label: id + ":controls", measurementKey: measurementKey, content: collapsed)
                    .panelMeasure("collapsed:" + id)
                    .opacity(1 - phase)
                    .allowsHitTesting(!isExpanded)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(isExpanded)
                PanelNaturalContent(label: id + ":archive", measurementKey: measurementKey, content: expanded)
                    .panelMeasure("detail:" + id)
                    .opacity(phase)
                    .allowsHitTesting(isExpanded)
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(!isExpanded)
            }
        }
        .layoutValue(key: PanelRevealHeightKey.self, value: height)
        .clipped(antialiased: false)
        .background {
            Color.clear.preference(key: PanelNaturalMeasurements.self,
                                   value: ["available:" + id: CGSize(width: 1, height: 0)])
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// 角标与视口消费同一帧相位，避免另起一个局部动画时钟。
struct PanelPhaseRotation: ViewModifier {
    @ObservedObject var presentation: PanelDetailPresentation
    var collapsed: Double = 0
    var expanded: Double = 90
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(collapsed + (expanded - collapsed) * presentation.sample.opacity))
    }
}

func withPanelExpansionState(_ updates: () -> Void) {
    if PanelMotionExperiment.enabled {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    } else {
        withAnimation(.spring(response: MonitorConstants.panelExpansionSpringResponse,
                              dampingFraction: MonitorConstants.panelExpansionSpringDamping), updates)
    }
}

/// 只观察表现帧的根包装，Header 与卡片闭包保持独立的内容依赖。
struct SingleHostPrototypeView<Header: View, Cards: View>: View {
    @ObservedObject var motion: SingleHostMotionCoordinator
    let ids: [String]
    let cap: CGFloat
    let header: Header
    let cards: Cards
    @State private var measurements: [String: CGSize] = [:]
    @State private var childGroups: [String: PanelChildGroup] = [:]
    @State private var measurementGeneration: UInt = 0
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var nativeScrollOffset: CGFloat = 0
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale

    init(motion: SingleHostMotionCoordinator, ids: [String], cap: CGFloat,
         @ViewBuilder header: () -> Header, @ViewBuilder cards: () -> Cards) {
        self.motion = motion
        self.ids = ids
        self.cap = cap
        self.header = header()
        self.cards = cards()
    }

    var body: some View {
        let frame = motion.currentFrame
        let header = self.header
        let cards = self.cards
        let hasMoreBelow = frame.map { $0.isCapped && $0.scrollOffset + $0.viewportHeight < $0.bodyDocumentHeight - 1 } ?? false
        PanelChromeLayout(headerHeight: motion.registry.panelHeaderHeight,
                          viewportHeight: frame?.viewportHeight ?? 200,
                          panelWidth: MonitorConstants.panelIdealWidth - 12) {
            PanelNaturalContent(label: "header", content: header)
                .panelMeasure("__header__")
            ScrollView(.vertical) {
                AccordionLayout(cardFrames: frame?.cardFrames ?? [:],
                                documentHeight: frame?.bodyDocumentHeight ?? 200,
                                cardWidth: MonitorConstants.panelIdealWidth - 12,
                                naturalHeights: motion.registry.makeSnapshot()?.sections.mapValues(\.totalNaturalHeight) ?? [:]) {
                    cards
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                nativeScrollOffset = offset
                motion.updateUserScroll(offset)
            }
            .onScrollPhaseChange { previous, phase in
                switch phase {
                case .tracking, .interacting:
                    if !motion.isUserScrolling || previous == .decelerating {
                        motion.userScrollBegan(at: nativeScrollOffset)
                    }
                case .decelerating:
                    if !motion.isUserScrolling { motion.userScrollBegan(at: nativeScrollOffset) }
                case .idle:
                    motion.userScrollEnded(at: nativeScrollOffset)
                default: break
                }
            }
            .onChange(of: frame?.scrollOffset ?? 0) { _, offset in
                guard !motion.isUserScrolling else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { scrollPosition.scrollTo(y: offset) }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: (frame?.scrollOffset ?? 0) > 1 ? 12 : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: hasMoreBelow ? 12 : 0)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .frame(width: MonitorConstants.panelIdealWidth, alignment: .topLeading)
        .onPreferenceChange(PanelNaturalMeasurements.self) { values in
            guard values != measurements else { return }
            measurements = values
            // 自然尺寸在布局完成后整批登记，运动期间的窗口高度不读取该反馈。
            measurementGeneration &+= 1
            let generation = measurementGeneration
            DispatchQueue.main.async {
                guard generation == measurementGeneration else { return }
                updateGeometry(values)
            }
        }
        .onPreferenceChange(PanelChildGroups.self) { groups in
            guard groups != childGroups else { return }
            childGroups = groups
            DispatchQueue.main.async { updateGeometry(measurements) }
        }
        .onChange(of: cap) { _, _ in updateGeometry(measurements) }
        .onChange(of: ids) { _, _ in updateGeometry(measurements) }
    }

    private func updateGeometry(_ values: [String: CGSize]) {
        var groups: [String: PanelChildGroup] = [:]
        var allIDs = ids
        var visited = Set(ids)
        var index = 0
        while index < allIDs.count {
            let id = allIDs[index]
            if let group = childGroups[id] {
                groups[id] = group
                for child in group.ids where visited.insert(child).inserted { allIDs.append(child) }
            }
            index += 1
        }
        let hierarchy = groups.mapValues(\.ids)
        guard values["__header__"] != nil, values["__footer__"] != nil,
              allIDs.allSatisfy({ values["row:" + $0] != nil && values["detail:" + $0] != nil
                  && values["available:" + $0] != nil }) else { return }
        let registry = motion.registry
        let signature = allIDs.map { id in
            "\(id):\(values["row:" + id]!.height):\(values["detail:" + id]!.height):\(values["available:" + id]!.width):\(values["collapsed:" + id]?.height ?? 0)"
        }.joined(separator: "|") + groups.keys.sorted().map { "\($0):\(groups[$0]!)" }.joined()
        _ = registry.updateEnvironment(GeometryEnvironmentToken(
            width: values["__header__"]!.width + 12,
            localeIdentifier: locale.identifier, dynamicTypeSize: String(describing: typeSize),
            backingScale: scale, structureSignature: signature))
        registry.configureStructure(topLevelIDs: ids, hierarchy: hierarchy, childGroups: groups)
        registry.contentHeightCap = cap
        if let height = values["__header__"]?.height { registry.panelHeaderHeight = height }
        if let height = values["__footer__"]?.height { registry.footerHeight = height }
        for id in allIDs {
            guard let header = values["row:" + id], let detail = values["detail:" + id] else { continue }
            registry.reportMeasurement(id: id, parentID: groups.first(where: { $0.value.ids.contains(id) })?.key, headerHeight: header.height,
                detailHeight: detail.height,
                isAvailable: values["available:" + id]?.width == 1,
                revision: registry.currentRevision, collapsedDetailHeight: values["collapsed:" + id]?.height ?? 0)
        }
        motion.geometryDidChange()
        if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil {
            NSLog("[panel-geometry] ready=%d values=%@", registry.isReady ? 1 : 0,
                  values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: ","))
        }
    }
}
