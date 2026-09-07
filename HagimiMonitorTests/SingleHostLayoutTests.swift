import AppKit
import Combine
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

struct SingleHostLayoutTests {
    @MainActor private final class HeaderFixtureState: ObservableObject {
        @Published var hasChart = false
        var measuredHeight: CGFloat = 0
    }

    private struct HeaderFixture: View {
        @ObservedObject var state: HeaderFixtureState
        var body: some View {
            PanelCardLayout(measurementKey: state.hasChart ? "chart" : "progress") {
                Color.clear.frame(height: state.hasChart ? 18 : 15).padding(.vertical, 8)
                Color.clear.frame(height: 0)
            }
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { state.measuredHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in state.measuredHeight = height }
            })
        }
    }

    @Test @MainActor func headerStructureChangeInvalidatesCachedHeight() async throws {
        let state = HeaderFixtureState()
        let hosting = NSHostingView(rootView: HeaderFixture(state: state))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 328, height: 200)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(state.measuredHeight == 31)
        state.hasChart = true
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(state.measuredHeight == 34)
    }

    /// 原生 hosting 内的叶子探针，记录实际经过布局系统的提议。
    struct ProposalProbeLayout: Layout {
        final class ProbeBox {
            var proposals: [ProposedViewSize] = []
        }
        let box: ProbeBox
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            box.proposals.append(proposal)
            return CGSize(width: proposal.width ?? 280, height: 160)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    @Test @MainActor func nestedRevealKeepsActualWidthAndStableLeafProposals() async throws {
        let box = ProposalProbeLayout.ProbeBox()
        let presentation = PanelDetailPresentation()
        let content = ProposalProbeLayout(box: box) { Color.red }
        let root = SingleHostDetail(id: "archive", isExpanded: true, available: true,
            content: content, presentation: presentation)
            .padding(.leading, 28)
            .padding(.horizontal, 10)
            .frame(width: 328, alignment: .topLeading)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 328, height: 200)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        hosting.layoutSubtreeIfNeeded()
        #expect(!box.proposals.isEmpty)
        #expect(box.proposals.allSatisfy { $0.width == 280 })
        box.proposals.removeAll()
        for height: CGFloat in [10, 40, 100, 160, 70, 0] {
            presentation.sample = .init(revealHeight: height, opacity: height > 0 ? 1 : 0)
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(box.proposals.allSatisfy { $0.width == 280 && ($0.height == nil || $0.height == 160) })
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(width: 328, height: nil)
        var renderedSize = CGSize.zero
        renderer.render { size, _ in renderedSize = size }
        #expect(renderedSize.width == 328)
        #expect(renderedSize.height == 0)
    }

    @Test @MainActor func replacementCachesBothLeavesAtTheirActualIndentedWidth() async throws {
        let controls = ProposalProbeLayout.ProbeBox()
        let archive = ProposalProbeLayout.ProbeBox()
        let presentation = PanelDetailPresentation()
        presentation.sample = .init(revealHeight: 167, opacity: 0)
        let root = SingleHostReplacement(id: "archive", isExpanded: false, measurementKey: "two-leaves",
            presentation: presentation,
            collapsed: ProposalProbeLayout(box: controls) { Color.clear }.padding(.leading, 22).padding(.top, 7),
            expanded: ProposalProbeLayout(box: archive) { Color.clear }.padding(.leading, 22).padding(.top, 7))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 280, height: 167)
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!controls.proposals.isEmpty && !archive.proposals.isEmpty)
        #expect((controls.proposals + archive.proposals).allSatisfy { $0.width == 258 })
        controls.proposals.removeAll()
        archive.proposals.removeAll()
        for height: CGFloat in [180, 230, 300, 210, 167] {
            presentation.sample = .init(revealHeight: height, opacity: 0.5)
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((controls.proposals + archive.proposals).allSatisfy { $0.width == 258 && $0.height == 160 })
    }

    @Test @MainActor func headerAndFooterRemainInsideSixPointOuterMargins() {
        let root = PanelChromeLayout(headerHeight: 22, viewportHeight: 160, panelWidth: 328) {
            Color.clear
            Color.clear
        }
        .padding(.top, 8).padding(.horizontal, 6).padding(.bottom, 6)
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)
        var renderedSize = CGSize.zero
        renderer.render { size, _ in renderedSize = size }
        #expect(renderedSize == CGSize(width: 340, height: 200))
    }

    @Test @MainActor func fixedColumnsMatchOriginalGridAtSupportedWidths() throws {
        let cells = ForEach(0..<5) { index in
            Color.red.opacity(Double(index + 1) / 5).frame(height: index.isMultiple(of: 2) ? 24 : 30)
        }
        for width: CGFloat in [240, 280, 400] {
            let original = ImageRenderer(content:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: MetricGridMetrics.columnSpacing), GridItem(.flexible())],
                          spacing: MetricGridMetrics.gridRowGap) { cells }.frame(width: width))
            let candidate = ImageRenderer(content:
                PanelMetricColumnsLayout(measurementKey: "five") { cells }.frame(width: width))
            let expected = try #require(original.cgImage)
            let actual = try #require(candidate.cgImage)
            #expect(actual.width == expected.width)
            #expect(actual.height == expected.height)
            #expect(actual.dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
        }
    }

    @Test @MainActor func fullSizePinnedContentUsesFrameHeightWithoutTitlebarAddition() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        let hosting = NSHostingView(rootView: Color.clear.ignoresSafeArea())
        hosting.sizingOptions = []
        panel.contentView = hosting
        for height: CGFloat in [193, 476, 300] {
            panel.setFrame(CGRect(x: 0, y: 900 - height, width: 340, height: height), display: false)
            hosting.layoutSubtreeIfNeeded()
            #expect(hosting.bounds.size == CGSize(width: 340, height: height))
            #expect(panel.frame.maxY == 900)
        }
    }
}
