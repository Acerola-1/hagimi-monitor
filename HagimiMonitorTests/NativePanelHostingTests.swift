import AppKit
import Combine
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
@Suite(.serialized)
struct NativePanelHostingTests {
    private final class RenderProbe {
        var values: [Int] = []
        var locales: [String] = []
    }

    private struct VersionedCard: View, Equatable {
        let probe: RenderProbe
        let value: Int
        let height: CGFloat
        @Environment(\.locale) private var locale
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value && lhs.height == rhs.height }
        var body: some View {
            let _ = probe.values.append(value)
            let _ = probe.locales.append(locale.identifier)
            VStack(spacing: 0) {
                Text("\(value)").frame(height: 34)
                Color.clear.frame(height: height)
            }
            .preference(key: PanelNaturalMeasurements.self, value: [
                "row:cpu": CGSize(width: 328, height: 34),
                "detail:cpu": CGSize(width: 328, height: height),
                "available:cpu": CGSize(width: 1, height: 0)])
        }
    }

    @Test func unchangedCardsStayMountedWhileValuesStructureAndLocaleRefresh() async throws {
        let probe = RenderProbe()
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(width: 340,
            localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: ""))
        let motion = SingleHostMotionCoordinator(registry: registry)
        let surface = NativePanelSurface(motion: motion)
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 380, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = surface
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; motion.nativeLayer.suspend() }
        var environment = EnvironmentValues()
        environment.panelMaxContentHeight = 600
        environment.locale = Locale(identifier: "en")
        func update(_ value: Int, height: CGFloat) {
            let item = NativePanelContentItem(id: "cpu", content: VersionedCard(probe: probe, value: value, height: height))
            surface.update(header: AnyView(Color.clear.frame(height: 22)), ids: ["cpu"],
                views: [item.content, AnyView(Color.clear.frame(height: 34))],
                environment: environment, cap: 600, versions: [item.version])
        }
        func settle(until condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !condition() && ContinuousClock.now < deadline {
                surface.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(condition())
        }
        update(0, height: 60)
        try await settle { surface.contentHost(for: "cpu") != nil && probe.values.last == 0 }
        try await Task.sleep(for: .milliseconds(200))
        let node = try #require(surface.contentHost(for: "cpu"))
        let count = probe.values.count
        #expect(count > 0)
        update(0, height: 60)
        try await Task.sleep(for: .milliseconds(100))
        #expect(surface.contentHost(for: "cpu") === node)
        #expect(probe.values.count == count, "同值更新不应重新提交卡片内容")
        update(1, height: 140)
        try await settle { probe.values.last == 1 && motion.nativeLayer.snapshot?.sections["cpu"]?.detailHeight == 140 }
        #expect(probe.values.last == 1)
        #expect(motion.nativeLayer.snapshot?.sections["cpu"]?.detailHeight == 140)
        environment.locale = Locale(identifier: "zh_CN")
        update(1, height: 140)
        try await settle { probe.locales.last == "zh_CN" }
        #expect(probe.locales.last == "zh_CN", "同值内容仍须接收排版环境变化")
    }

    nonisolated private final class MeasurementProbe: @unchecked Sendable {
        var placedValues: [Int] = []
    }

    private struct MeasuredDetail: Layout {
        let probe: MeasurementProbe
        let height: CGFloat
        let value: Int
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            return CGSize(width: proposal.width ?? 300, height: height + (proposal.width ?? 300) / 10)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            probe.placedValues.append(value)
            subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    private struct CachedDetail: View {
        let probe: MeasurementProbe
        let height: CGFloat
        let value: Int
        let key: String
        var width: CGFloat = 300
        var body: some View {
            PanelNaturalContent(label: "fixture", measurementKey: key,
                content: MeasuredDetail(probe: probe, height: height, value: value) { Text("\(value)") })
                .frame(width: width)
        }
    }

    @Test func naturalSizeTracksStructureAndWidthWhilePlacingNewReadings() {
        let probe = MeasurementProbe()
        let host = NSHostingView(rootView: CachedDetail(probe: probe, height: 100, value: 0, key: "one"))
        host.frame.size = CGSize(width: 300, height: 500)
        #expect(abs(host.fittingSize.height - 130) < 0.01)
        for value in 1...8 {
            host.rootView = CachedDetail(probe: probe, height: 100, value: value, key: "one")
            host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.height - 130) < 0.01)
            #expect(probe.placedValues.last == value)
        }
        host.rootView = CachedDetail(probe: probe, height: 200, value: 9, key: "two")
        #expect(abs(host.fittingSize.height - 230) < 0.01)
        host.rootView = CachedDetail(probe: probe, height: 200, value: 9, key: "two", width: 200)
        #expect(abs(host.fittingSize.height - 220) < 0.01)
    }

    @Test func unregisteredNaturalSizeStillTracksContentChanges() {
        let probe = MeasurementProbe()
        let host = NSHostingView(rootView: CachedDetail(probe: probe, height: 100, value: 0, key: ""))
        host.frame.size = CGSize(width: 300, height: 500)
        #expect(abs(host.fittingSize.height - 130) < 0.01)
        host.rootView = CachedDetail(probe: probe, height: 200, value: 1, key: "")
        #expect(abs(host.fittingSize.height - 230) < 0.01)
    }

    @Test func pageGrowthKeepsReservedBackingAndExistingMaskPlan() async throws {
        let node = NativePanelContentHost()
        node.minimumAllocatedHeight = 600
        let contentLayer = try #require(node.hosting.layer)
        for height: CGFloat in [60, 240, 60, 380, 60, 180] {
            node.hosting.rootView = AnyView(Color.clear.frame(height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
            let measured = node.measure(width: 300)
            try await Task.sleep(for: .milliseconds(30))
            #expect(abs(measured - height) < 0.01)
            #expect(node.hosting.frame == CGRect(x: 0, y: 0, width: 300, height: 600),
                "换页应只改变自然尺寸，内容承载 frame 实际为 \(node.hosting.frame)")
            #expect(node.frame.height == 600)
            #expect(node.hosting.layer === contentLayer)
            if height != 60 {
                #expect(node.appliedGeneration == 9, "尺寸变化不应作废当前遮罩计划")
            }
            node.appliedGeneration = 9
        }
    }

    private final class State: ObservableObject {
        @Published var height: CGFloat = 180
        @Published var value: Double = 50
        var placements: [CGFloat] = []
        var inheritedWidths: [CGFloat] = []
    }

    private struct NestedContent: View {
        @ObservedObject var state: State
        @Environment(\.nativePanelContentWidth) private var width
        var body: some View {
            VStack {
                Text("\(Int(state.value))")
                Slider(value: $state.value, in: 0...100).controlSize(.small)
            }
            .onAppear { state.inheritedWidths.append(width) }
            .onChange(of: width) { _, value in state.inheritedWidths.append(value) }
            .onChange(of: state.value) { _, _ in state.inheritedWidths.append(width) }
        }
    }

    @Test func nestedHostInheritsItsInsetContentWidthDuringControlUpdates() async throws {
        let state = State()
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(width: 332,
            localeIdentifier: "zh_CN", dynamicTypeSize: "default", backingScale: 2, structureSignature: ""))
        let motion = SingleHostMotionCoordinator(registry: registry)
        let host = NSHostingView(rootView: NativePanelChildren(id: "display", isExpanded: true,
            group: PanelChildGroup(ids: ["device"], leading: 10, trailing: 10), motion: motion,
            items: [NativePanelContentItem(id: "device", content: AnyView(NestedContent(state: state)))])
            .environment(\.nativePanelContentWidth, 320))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        for value in [51.0, 52, 53] {
            state.value = value
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(!state.inheritedWidths.isEmpty)
        #expect(state.inheritedWidths.allSatisfy { abs($0 - 300) < 0.01 },
            "嵌套内容继承了 \(state.inheritedWidths)，应扣除左右内衬得到 300")
        motion.nativeLayer.suspend()
    }

    private struct DetailLayout: Layout {
        let state: State
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            CGSize(width: proposal.width ?? 300, height: MainActor.assumeIsolated { state.height })
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            MainActor.assumeIsolated { state.placements.append(proposal.height ?? -1) }
            subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    private struct Card: View {
        @ObservedObject var state: State
        let natural: Bool
        var body: some View {
            PanelCardLayout(usesNaturalDetailHeight: natural, measurementKey: "fixture") {
                Color.clear.frame(height: 34)
                DetailLayout(state: state) {
                    VStack {
                        Slider(value: $state.value, in: 0...100).controlSize(.small)
                        Slider(value: .constant(40), in: 0...100).controlSize(.small)
                    }
                }
            }
        }
    }

    private struct PowerPage: View {
        @ObservedObject var state: State
        var body: some View {
            VStack(spacing: 0) {
                Color.clear.frame(height: 34)
                Color.clear.frame(height: state.height)
            }
            .preference(key: PanelNaturalMeasurements.self, value: [
                "row:battery": CGSize(width: 300, height: 34),
                "detail:battery": CGSize(width: 300, height: state.height),
                "available:battery": CGSize(width: 1, height: 0)])
        }
    }

    @Test func fullSurfaceReservesPowerBackingWithoutReportingCapacityAsPageHeight() async throws {
        let state = State()
        state.height = 60
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(width: 340,
            localeIdentifier: "zh_CN", dynamicTypeSize: "default", backingScale: 2, structureSignature: ""))
        let motion = SingleHostMotionCoordinator(registry: registry)
        let host = NativePanelSurface(motion: motion)
        var environment = EnvironmentValues()
        environment.panelMaxContentHeight = 600
        host.update(header: AnyView(Color.clear.frame(height: 22)), ids: ["battery"], views: [
            AnyView(PowerPage(state: state)), AnyView(Color.clear.frame(height: 34))],
            environment: environment, cap: 600)
        host.frame = CGRect(x: 0, y: 0, width: 380, height: 600)
        // AppKit 只在已呈现的窗口里完整挂载 representable；离屏非激活窗口提供该环境。
        let window = NSPanel(contentRect: CGRect(x: -10000, y: -10000, width: 380, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; motion.nativeLayer.suspend() }
        host.layoutSubtreeIfNeeded()
        for height: CGFloat in [60, 240, 60, 380, 60, 180] {
            state.height = height
            host.layoutSubtreeIfNeeded()
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while host.contentHost(for: "battery") == nil || motion.nativeLayer.snapshot?.sections["battery"]?.detailHeight != height {
                guard ContinuousClock.now < deadline else { break }
                if let node = host.contentHost(for: "battery") {
                    node.hosting.needsLayout = true
                    _ = node.measure(width: 328)
                }
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
            let node = try #require(host.contentHost(for: "battery"))
            #expect(node.window === window)
            #expect(node.hosting.frame.height == 600)
            #expect(motion.nativeLayer.snapshot?.sections["battery"]?.detailHeight == height)
        }
        motion.nativeLayer.suspend()
    }

    @Test func naturalCardPlacesFullDetailAcrossPageAndSliderUpdates() async throws {
        let state = State()
        let host = NSHostingView(rootView: Card(state: state, natural: true))
        host.sizingOptions = []
        for height: CGFloat in [180, 70, 240, 90] {
            state.height = height
            for value in [50.0, 51, 52] {
                state.value = value
                state.placements.removeAll()
                host.frame = CGRect(x: 0, y: 0, width: 300, height: 34 + height)
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
                #expect(!state.placements.isEmpty)
                #expect(state.placements.allSatisfy { abs($0 - height) < 0.01 },
                    "完整明细收到的摆放提议为 \(state.placements)，自然高度为 \(height)")
            }
        }
    }

    @Test func legacyViewportRetainsZeroHeightPlacement() async throws {
        let state = State()
        let host = NSHostingView(rootView: Card(state: state, natural: false))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 34)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!state.placements.isEmpty)
        #expect(state.placements.allSatisfy { $0 == 0 })
    }
}
