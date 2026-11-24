import AppKit
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

struct StatisticsHoverPopoverTests {
    @Test func nativeHoverGeometryIntersectsBoundsWithVisibleRect() {
        let bounds = CGRect(x: 0, y: 0, width: 203, height: 64)
        // macOS 14+ 默认 `clipsToBounds == false`，`visibleRect` 可能横跨相邻格子。
        let unclippedVisible = CGRect(x: -212, y: -150, width: 495, height: 533)
        #expect(NativeHoverGeometry.activeRect(bounds: bounds, visibleRect: unclippedVisible) == bounds)
        #expect(NativeHoverGeometry.contains(localPoint: CGPoint(x: 100, y: 32), bounds: bounds, visibleRect: unclippedVisible))
        #expect(!NativeHoverGeometry.contains(localPoint: CGPoint(x: -50, y: 32), bounds: bounds, visibleRect: unclippedVisible))
        #expect(!NativeHoverGeometry.contains(localPoint: CGPoint(x: 210, y: 32), bounds: bounds, visibleRect: unclippedVisible))

        // 滚动裁切后只保留视图实际可见的那一段。
        let partiallyClipped = CGRect(x: 0, y: 20, width: 203, height: 44)
        #expect(NativeHoverGeometry.activeRect(bounds: bounds, visibleRect: partiallyClipped) == partiallyClipped)
        #expect(!NativeHoverGeometry.contains(localPoint: CGPoint(x: 100, y: 10), bounds: bounds, visibleRect: partiallyClipped))
        #expect(NativeHoverGeometry.contains(localPoint: CGPoint(x: 100, y: 40), bounds: bounds, visibleRect: partiallyClipped))

        let completelyClipped = CGRect(x: 0, y: 100, width: 203, height: 50)
        #expect(NativeHoverGeometry.activeRect(bounds: bounds, visibleRect: completelyClipped) == .zero)
        #expect(!NativeHoverGeometry.contains(localPoint: CGPoint(x: 100, y: 32), bounds: bounds, visibleRect: completelyClipped))
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @MainActor
    @Test func coordinatorEnforcesSingleActivePopover() async throws {
        let coordinator = HoverPopoverCoordinator()
        let cpu = HoverPopoverController(
            coordinator: coordinator,
            showDelay: .milliseconds(20),
            hideDelay: .milliseconds(15)
        )
        let gpu = HoverPopoverController(
            coordinator: coordinator,
            showDelay: .milliseconds(20),
            hideDelay: .milliseconds(15)
        )

        cpu.setTriggerHover(true)
        #expect(try await waitUntil { cpu.isPresented })
        #expect(!gpu.isPresented)

        // 悬停打开 GPU 时，先前的 CPU 浮层应立刻关闭。
        cpu.setTriggerHover(false)
        gpu.setTriggerHover(true)
        #expect(try await waitUntil { gpu.isPresented })
        #expect(!cpu.isPresented)

        // 点击固定 GPU 后再点击打开 CPU，也必须互斥收起 GPU。
        gpu.setTriggerHover(false)
        gpu.toggle()
        #expect(!gpu.isPresented)
        gpu.toggle()
        #expect(gpu.isPresented)

        cpu.toggle()
        #expect(cpu.isPresented)
        #expect(!gpu.isPresented)
    }

    @MainActor
    @Test func hoverControllerBridgesTriggerToContentAndUsesDeliberateShowDelay() async throws {
        #expect(HoverPopoverController.defaultShowDelay > HoverPopoverController.defaultHideDelay)

        let coordinator = HoverPopoverCoordinator()
        let controller = HoverPopoverController(
            coordinator: coordinator,
            showDelay: .milliseconds(120),
            hideDelay: .milliseconds(80)
        )

        controller.setTriggerHover(true)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!controller.isPresented)

        #expect(try await waitUntil { controller.isPresented })

        // 离开触发区后立即进入浮层本体，应在 hideDelay 内保持展开。
        controller.setTriggerHover(false)
        try await Task.sleep(for: .milliseconds(15))
        controller.setContentHover(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isPresented)

        // 两侧都离开后经过 hideDelay 收起。
        controller.setContentHover(false)
        #expect(try await waitUntil { !controller.isPresented })
    }

    @MainActor
    @Test func adjacentWorkloadHoverTrackersRemainStrictlyDisjointInScrollView() throws {
        struct ProbeGrid: View {
            var body: some View {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 164)
                    Rectangle().frame(width: 1)
                    GeometryReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 24) {
                                Color.clear.frame(height: 150)
                                HStack(spacing: 0) {
                                    Button {} label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("CPU")
                                            Text("平均 12%")
                                            Text("高负载 0%")
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                    .buttonStyle(.plain)
                                    .background(NativeHoverTracker { _ in })
                                    .padding(4)

                                    Rectangle().frame(width: 1)

                                    Button {} label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("GPU")
                                            Text("平均 4%")
                                            Text("峰值 18%")
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                    .buttonStyle(.plain)
                                    .background(NativeHoverTracker { _ in })
                                    .padding(4)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .controlSize(.small)
                            .padding(.top, 34)
                            .padding(.horizontal, 36)
                            .padding(.bottom, 28)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .frame(minHeight: proxy.size.height, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .top)
                }
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 660, height: 533),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "TestSettingsToolbar")
        window.toolbarStyle = .unified

        let hostingController = NSHostingController(rootView: ProbeGrid())
        hostingController.sizingOptions = []
        let containerController = NSViewController()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 533))
        containerController.view = containerView
        containerController.addChild(hostingController)
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)
        window.contentViewController = containerController
        window.setContentSize(NSSize(width: 660, height: 533))
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        func collectTrackers(in view: NSView) -> [NativeHoverTracker.TrackingView] {
            var found: [NativeHoverTracker.TrackingView] = []
            if let tracker = view as? NativeHoverTracker.TrackingView {
                found.append(tracker)
            }
            for subview in view.subviews {
                found.append(contentsOf: collectTrackers(in: subview))
            }
            return found
        }

        let trackers = collectTrackers(in: containerView).sorted {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }
        try #require(trackers.count == 2)
        let cpuTracker = trackers[0]
        let gpuTracker = trackers[1]

        let cpuRect = cpuTracker.convert(cpuTracker.bounds, to: nil)
        let gpuRect = gpuTracker.convert(gpuTracker.bounds, to: nil)

        #expect(!cpuRect.intersects(gpuRect))
        #expect(abs((gpuRect.minX - cpuRect.maxX) - 9) < 0.5)

        let gpuArea = try #require(gpuTracker.trackingAreas.first)
        #expect(gpuTracker.trackingAreas.count == 1)
        #expect(!gpuArea.options.contains(.inVisibleRect))
        #expect(gpuArea.rect == NativeHoverGeometry.activeRect(bounds: gpuTracker.bounds, visibleRect: gpuTracker.visibleRect))

        for x in stride(from: cpuRect.minX, to: cpuRect.maxX, by: 4) {
            let gpuLocal = gpuTracker.convert(NSPoint(x: x, y: cpuRect.midY), from: nil)
            #expect(!NativeHoverGeometry.contains(localPoint: gpuLocal, bounds: gpuTracker.bounds, visibleRect: gpuTracker.visibleRect))
        }
        let cpuTrailing = gpuTracker.convert(NSPoint(x: cpuRect.maxX - 0.5, y: cpuRect.midY), from: nil)
        #expect(!NativeHoverGeometry.contains(localPoint: cpuTrailing, bounds: gpuTracker.bounds, visibleRect: gpuTracker.visibleRect))
    }
}
