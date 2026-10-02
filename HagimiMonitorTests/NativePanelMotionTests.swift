import AppKit
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct NativePanelMotionTests {
    private final class Clock { var time: Double = 100 }
    private final class Renderer: NativePanelLayerRenderer {
        var plans: [NativePanelAnimationPlan] = []
        var stopped = 0
        func applyNativePlan(_ plan: NativePanelAnimationPlan) { plans.append(plan) }
        func stopNativeMotion() { stopped += 1 }
    }
    private func fixture(_ clock: Clock, cap: CGFloat = 900, nested: Bool = false) -> (PanelDimensionRegistry, NativePanelLayerMotion) {
        let ids = ["cpu", "gpu", "fan", "memory", "storage", "network", "battery", "bluetooth", "display"]
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(width: 340,
            localeIdentifier: "zh_CN", dynamicTypeSize: "default", backingScale: 2, structureSignature: ids.joined(separator: ",")))
        registry.configureStructure(topLevelIDs: ids, hierarchy: nested ? ["display": ["device"], "device": ["archive"]] : [:])
        registry.panelHeaderHeight = 22; registry.footerHeight = 34; registry.contentHeightCap = cap
        for id in ids { registry.reportMeasurement(id: id, headerHeight: 34, detailHeight: 240, revision: registry.currentRevision) }
        if nested {
            registry.reportMeasurement(id: "device", parentID: "display", headerHeight: 30, detailHeight: 90, revision: registry.currentRevision)
            registry.reportMeasurement(id: "archive", parentID: "device", headerHeight: 24, detailHeight: 160, revision: registry.currentRevision)
        }
        let motion = NativePanelLayerMotion(registry: registry, clock: { clock.time })
        motion.reduceMotionOverride = false
        motion.geometryDidChange()
        return (registry, motion)
    }

    @Test func allModuleCompoundPlanUsesOneBoundedTimeline() throws {
        let clock = Clock()
        let (_, motion) = fixture(clock, cap: 600, nested: true)
        let targets = try #require(motion.snapshot).sections.mapValues { _ in CGFloat(1) }
        motion.retarget(targets)
        let plan = try #require(motion.plan)
        #expect(plan.duration == MonitorConstants.panelNativeMotionDuration)
        #expect(plan.samples.count < 600)
        for pair in zip(plan.samples, plan.samples.dropFirst()) {
            let time = (pair.0.frame.sampleTime + pair.1.frame.sampleTime) / 2
            let exact = try #require(motion.sample(at: time)).frame
            #expect(abs((pair.0.frame.windowContentSize.height + pair.1.frame.windowContentSize.height) / 2 - exact.windowContentSize.height) < 0.5)
            #expect(abs((pair.0.frame.scrollOffset + pair.1.frame.scrollOffset) / 2 - exact.scrollOffset) < 0.5)
            for (id, rect) in exact.childFrames {
                let left = try #require(pair.0.frame.childFrames[id]); let right = try #require(pair.1.frame.childFrames[id])
                #expect(abs((left.height + right.height) / 2 - rect.height) < 0.5)
            }
        }
        let final = try #require(plan.samples.last)
        #expect(final.frame.windowContentSize.height == 600)
        #expect(final.frame.cardFrames.count == 10)
        #expect(final.frame.childFrames.count == 2)
        #expect(final.phases.values.allSatisfy { $0 == 1 })
        motion.suspend()
    }

    @Test func reverseRetainsPositionAndVelocityAndCancelsDescendants() throws {
        let clock = Clock(); let (_, motion) = fixture(clock, nested: true)
        motion.retarget(["display": 1, "device": 1, "archive": 1])
        clock.time += 0.09
        let before = try #require(motion.sample(at: clock.time))
        let velocity = try #require(motion.tracks["display"]).sample(at: clock.time).velocity
        motion.retarget(["display": 0])
        let after = try #require(motion.sample(at: clock.time))
        #expect(abs(before.frame.windowContentSize.height - after.frame.windowContentSize.height) < 0.0001)
        #expect(abs(try #require(motion.tracks["display"]).sample(at: clock.time).velocity - velocity) < 0.0001)
        #expect(motion.tracks["device"]?.target == 0)
        #expect(motion.tracks["archive"]?.target == 0)
        #expect(after.phases.values.allSatisfy { (0...1).contains($0) })
        motion.suspend()
    }

    @Test func shorterPagePreservesVisibleHeightAndVelocity() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock, cap: 2000, nested: true)
        motion.retarget(["display": 1, "device": 1, "archive": 1])
        clock.time += 0.19
        let step = 0.0000001
        let before = try #require(motion.sample(at: clock.time)).frame
        let nextBefore = try #require(motion.sample(at: clock.time + step)).frame
        registry.reportMeasurement(id: "archive", parentID: "device", headerHeight: 24, detailHeight: 12, revision: registry.currentRevision)
        registry.reportMeasurement(id: "device", parentID: "display", headerHeight: 30, detailHeight: 15, revision: registry.currentRevision)
        motion.geometryDidChange()
        let after = try #require(motion.sample(at: clock.time)).frame
        let nextAfter = try #require(motion.sample(at: clock.time + step)).frame
        for id in ["display", "device", "archive"] {
            #expect(abs(try #require(before.revealHeights[id]) - (try #require(after.revealHeights[id]))) < 0.001)
            let oldSpeed = (try #require(nextBefore.revealHeights[id]) - (try #require(before.revealHeights[id]))) / step
            let newSpeed = (try #require(nextAfter.revealHeights[id]) - (try #require(after.revealHeights[id]))) / step
            #expect(abs(oldSpeed - newSpeed) < 0.02)
        }
        #expect(abs(before.bodyDocumentHeight - after.bodyDocumentHeight) < 0.001)
        #expect(motion.tracks.values.allSatisfy { (0...1).contains($0.sample(at: clock.time).position) })
        motion.suspend()
    }

    @Test func playbackDoesNotPublishFramesAndSuspendFreezesThenResumes() throws {
        let clock = Clock(); let (_, motion) = fixture(clock)
        let renderer = Renderer(); motion.register(renderer)
        var commits = 0; motion.onCommit = { _, _ in commits += 1 }
        motion.retarget(["cpu": 1])
        #expect(commits == 1)
        for i in 0..<100 { _ = motion.sample(at: clock.time + Double(i) / 200) }
        #expect(commits == 1)
        clock.time += 0.08
        let value = try #require(motion.sample(at: clock.time)).phases["cpu"]
        let generation = motion.generation
        motion.suspend()
        clock.time += 5
        #expect(motion.sample(at: clock.time)?.phases["cpu"] == value)
        #expect(!motion.isAnimating)
        #expect(motion.plan == nil)
        #expect(motion.generation > generation)
        #expect(renderer.stopped == 1)
        motion.resume()
        #expect(motion.sample(at: clock.time)?.phases["cpu"] == 1)
        #expect(motion.plan?.duration == 0)
        motion.suspend()
    }

    @Test func userScrollTakesOverWithoutAutomaticPullback() throws {
        let clock = Clock(); let (_, motion) = fixture(clock, cap: 550)
        motion.retarget(["cpu": 1, "display": 1])
        clock.time += 0.12
        let current = try #require(motion.sample(at: clock.time)).frame.scrollOffset
        motion.userScrollBegan(at: current)
        motion.updateUserScroll(25)
        #expect(motion.sample(at: clock.time)?.frame.scrollOffset == 25)
        clock.time += 0.3
        #expect(motion.sample(at: clock.time)?.frame.scrollOffset == 25)
        motion.userScrollEnded(at: 30)
        #expect(motion.sample(at: clock.time)?.frame.scrollOffset == 30)
        motion.suspend()
    }

    @Test func hiddenGeometryAndLogicalChangesDoNotRestartRendering() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock)
        let renderer = Renderer(); motion.register(renderer)
        motion.retarget(["cpu": 1])
        clock.time += 0.08
        motion.suspend()
        let frozen = try #require(motion.sample(at: clock.time)).frame
        let count = renderer.plans.count
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 480, revision: registry.currentRevision)
        motion.geometryDidChange()
        motion.retarget(["gpu": 1, "cpu": 0], instantly: true)
        clock.time += 2
        #expect(renderer.plans.count == count)
        #expect(motion.plan == nil)
        #expect(!motion.isAnimating)
        #expect(motion.sample(at: clock.time)?.frame.windowContentSize == frozen.windowContentSize)
        motion.resume()
        #expect(renderer.plans.count == count + 1)
        #expect(motion.plan?.duration == 0)
        #expect(motion.snapshot?.sections["cpu"]?.detailHeight == 480)
        #expect(motion.sample(at: clock.time)?.phases["cpu"] == 0)
        #expect(motion.sample(at: clock.time)?.phases["gpu"] == 1)
        motion.suspend()
    }

    @Test func inputBoundaryMatchesRoundedContourDuringHeightChange() {
        let width: CGFloat = 340
        var mismatches: [String] = []
        for height: CGFloat in [12, 40, 400, 800] {
            let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                cornerWidth: MonitorConstants.panelCornerRadius,
                cornerHeight: MonitorConstants.panelCornerRadius, transform: nil)
            for x in stride(from: CGFloat(-1), through: width + 1, by: 2) {
                for y in stride(from: CGFloat(-1), through: height + 1, by: 2) {
                    let point = CGPoint(x: x, y: y)
                    if NativePanelInputGeometry.contains(point, width: width, height: height) != path.contains(point) {
                        mismatches.append("height=\(height) point=\(point)")
                    }
                }
            }
        }
        #expect(mismatches.isEmpty)
        let point = CGPoint(x: 170, y: 450)
        #expect(!NativePanelInputGeometry.contains(point, width: width, height: 400))
        #expect(NativePanelInputGeometry.contains(point, width: width, height: 500))
        #expect(!NativePanelInputGeometry.contains(point, width: width, height: 0))
    }

    @Test func reduceMotionCommitsExactEndpoints() throws {
        let clock = Clock(); let (_, motion) = fixture(clock)
        motion.reduceMotionOverride = true
        motion.retarget(["cpu": 1])
        #expect(motion.plan?.duration == 0)
        #expect(motion.sample(at: clock.time)?.phases["cpu"] == 1)
        #expect(!motion.isAnimating)
        motion.suspend()
    }

    @Test func reducedMotionAlsoAppliesPageAndStructureEndpoints() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock)
        motion.retarget(["battery": 1], instantly: true)
        motion.reduceMotionOverride = true
        registry.reportMeasurement(id: "battery", headerHeight: 34, detailHeight: 80, revision: registry.currentRevision)
        motion.geometryDidChange()
        #expect(motion.plan?.duration == 0)
        #expect(motion.sample(at: clock.time)?.frame.revealHeights["battery"] == 80)
        #expect(!motion.isAnimating)
        motion.suspend()
    }

    @Test func renderersAndPendingCompletionDoNotRetainOwners() {
        let clock = Clock()
        var motion: NativePanelLayerMotion? = fixture(clock).1
        weak var weakMotion = motion
        var renderer: Renderer? = Renderer()
        weak var weakRenderer = renderer
        motion?.register(renderer!)
        motion?.retarget(["cpu": 1])
        renderer = nil
        #expect(weakRenderer == nil)
        motion = nil
        #expect(weakMotion == nil)
    }

    @Test func headerBulkExpansionKeepsFirstCardAtTopAcrossCapAndReverse() throws {
        let clock = Clock(); let (_, motion) = fixture(clock, cap: 600)
        let targets = try #require(motion.snapshot).sections.mapValues { _ in CGFloat(1) }
        motion.retarget(targets, scrollToTop: true)
        for sample in try #require(motion.plan).samples {
            #expect(sample.frame.scrollOffset == 0)
            #expect(sample.frame.cardFrames["cpu"]?.minY == 0)
        }
        #expect(motion.plan?.samples.last?.frame.isCapped == true)
        clock.time += 0.13
        motion.retarget(targets.mapValues { _ in 0 }, scrollToTop: true)
        for sample in try #require(motion.plan).samples {
            #expect(sample.frame.scrollOffset == 0)
            #expect(sample.frame.cardFrames["cpu"]?.minY == 0)
        }
        #expect(motion.plan?.samples.last?.frame.isCapped == false)
        motion.suspend()
    }

    @Test func pageChangesKeepScrollAndEarlierHeadersInsteadOfRevealingOldTarget() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock, cap: 600)
        motion.retarget(["cpu": 1, "battery": 1], instantly: true)
        let before = try #require(motion.sample(at: clock.time)).frame
        #expect(before.scrollOffset > 0)
        for height: CGFloat in [390, 280, 360] {
            registry.reportMeasurement(id: "battery", headerHeight: 34, detailHeight: height, revision: registry.currentRevision)
            motion.geometryDidChange()
            for sample in try #require(motion.plan).samples {
                #expect(abs(sample.frame.scrollOffset - before.scrollOffset) < 0.001)
                #expect(abs(try #require(sample.frame.cardFrames["battery"]).minY
                    - (try #require(before.cardFrames["battery"]).minY)) < 0.001)
                #expect(sample.frame.cardFrames["cpu"]?.minY == 0)
            }
            clock.time += 0.08
        }
        motion.suspend()
    }

    @Test func shorterPageClampsScrollContinuouslyWithoutMovingEarlierCards() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock, cap: 600)
        motion.retarget(["cpu": 1, "battery": 1], instantly: true)
        let before = try #require(motion.sample(at: clock.time)).frame
        registry.reportMeasurement(id: "battery", headerHeight: 34, detailHeight: 20, revision: registry.currentRevision)
        motion.geometryDidChange()
        let plan = try #require(motion.plan)
        #expect(abs(try #require(plan.samples.first).frame.scrollOffset - before.scrollOffset) < 0.001)
        for pair in zip(plan.samples, plan.samples.dropFirst()) {
            #expect(pair.1.frame.scrollOffset <= pair.0.frame.scrollOffset + 0.001)
            #expect(pair.1.frame.cardFrames["battery"]?.minY == before.cardFrames["battery"]?.minY)
            #expect(pair.1.frame.scrollOffset <= max(0, pair.1.frame.bodyDocumentHeight - pair.1.frame.viewportHeight))
        }
        motion.suspend()
    }
    @Test func pinnedFooterFollowsContourAcrossPageGeometryChanges() throws {
        let clock = Clock(); let (registry, motion) = fixture(clock, cap: 900)
        motion.retarget(["battery": 1], instantly: true)
        registry.reportMeasurement(id: "battery", headerHeight: 34, detailHeight: 20, revision: registry.currentRevision)
        motion.geometryDidChange()
        for sample in try #require(motion.plan).samples {
            let footer = try #require(sample.frame.cardFrames["__footer__"])
            #expect(abs(footer.minY - sample.frame.viewportHeight - PanelGeometrySolver.cardToCardSpacing) < 0.001)
        }
        motion.suspend()
    }

}
