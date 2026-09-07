import AppKit
import Foundation
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

struct SingleHostMotionTests {


    @Test func springMaintainsPositionAndVelocityContinuityOnReversal() {
        let spring = DampedSpring(response: 0.32, dampingRatio: 0.82)

        // 从 0 运动向 1.0
        let tInterrupt = 0.10
        let stateAtInterrupt = spring.evaluate(start: 0, target: 1.0, startVelocity: 0, elapsed: tInterrupt)

        #expect(stateAtInterrupt.position > 0)
        #expect(stateAtInterrupt.velocity > 0)

        // 在 tInterrupt 时刻反转：从当前位置与速度出发，目标设回 0
        let stateAfterReversalInstant = spring.evaluate(
            start: stateAtInterrupt.position,
            target: 0,
            startVelocity: stateAtInterrupt.velocity,
            elapsed: 0
        )

        // 验证位置与速度严格 C1 连续，无瞬时阶跃
        #expect(abs(stateAfterReversalInstant.position - stateAtInterrupt.position) < 0.0001)
        #expect(abs(stateAfterReversalInstant.velocity - stateAtInterrupt.velocity) < 0.0001)

        // 验证速度随有限差分吻合 (v ≈ (x(t+dt) - x(t))/dt)
        let dt = 0.0001
        let stateNext = spring.evaluate(start: 0, target: 1.0, startVelocity: 0, elapsed: tInterrupt + dt)
        let finiteDiffVelocity = (stateNext.position - stateAtInterrupt.position) / dt
        #expect(abs(finiteDiffVelocity - stateAtInterrupt.velocity) < 0.05)
    }


    @Test func springSettlesAccuratelyNearZeroAndOne() {
        let spring = DampedSpring(response: 0.32, dampingRatio: 0.82)

        // 在 0.5s 后应该非常接近目标
        let stateAtSettle = spring.evaluate(start: 0, target: 1.0, startVelocity: 0, elapsed: 0.50)
        #expect(abs(stateAtSettle.position - 1.0) < 0.01)

        // 位置很近但速度很大时不应提前判定收敛
        #expect(!spring.isSettled(position: 0.999, target: 1.0, velocity: 0.5))
        // 位置很近且速度很小时才判定收敛
        #expect(spring.isSettled(position: 0.9999, target: 1.0, velocity: 0.005))
    }


    @MainActor
    private final class MockSubmissionAdapter: PanelWindowSubmissionAdapter {
        var submittedSizes: [CGSize] = []
        var submittedFrameIDs: [UInt] = []

        func submitWindowFrame(size: CGSize, frameID: UInt) {
            submittedSizes.append(size)
            submittedFrameIDs.append(frameID)
        }

        func currentScreen() -> NSScreen? {
            nil
        }
    }

    @Test @MainActor func instantTargetsSubmitMatchingGeometry() {
        let env = GeometryEnvironmentToken(
            width: 340,
            localeIdentifier: "en_US",
            dynamicTypeSize: "default",
            backingScale: 2.0,
            structureSignature: "cpu"
        )
        let registry = PanelDimensionRegistry(initialEnvironment: env)
        registry.configureStructure(topLevelIDs: ["cpu"])
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 100, revision: 1)

        let adapter = MockSubmissionAdapter()
        let coordinator = SingleHostMotionCoordinator(registry: registry, adapter: adapter)

        // 瞬时提交
        coordinator.setInstantly(targets: ["cpu": 1.0])

        #expect(adapter.submittedSizes.count == 1)
        #expect(coordinator.currentFrame?.revealHeights["cpu"] == 100.0)

        coordinator.setInstantly(targets: ["cpu": 0.0])
        #expect(adapter.submittedSizes.count == 2)
        #expect(coordinator.currentFrame?.revealHeights["cpu"] == 0.0)
    }
}

extension SingleHostMotionTests {
    @MainActor private func closingMotion(detailHeight: CGFloat = 284) -> SingleHostMotionCoordinator {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2,
            structureSignature: "cpu"))
        registry.configureStructure(topLevelIDs: ["cpu"])
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: detailHeight, revision: 1)
        let motion = SingleHostMotionCoordinator(registry: registry)
        motion.setInstantly(targets: ["cpu": 1])
        motion.retarget(targets: ["cpu": 0], at: motion.currentFrame!.sampleTime + 1)
        return motion
    }

    @Test @MainActor func reopeningUsesVisibleBoundaryAndPreservesMomentumBeforeBoundary() {
        let spring = Spring(response: 0.32, dampingRatio: 0.82)
        for rate in [60.0, 120.0] {
            for elapsed in [0.22, 0.24, 0.30, 0.53] {
                let motion = closingMotion()
                let start = motion.tracks["cpu"]!.startTime
                for step in 1...Int(elapsed * rate) {
                    motion.advance(to: start + Double(step) / rate)
                }
                motion.advance(to: start + elapsed)
                let position: Double = 1 + spring.value(target: -1.0, initialVelocity: 0, time: elapsed)
                let velocity: Double = spring.velocity(target: -1.0, initialVelocity: 0, time: elapsed)
                let before = motion.tracks["cpu"]!
                #expect(abs(before.currentPhase - position) < 0.000001)
                #expect(abs(before.currentVelocity - velocity) < 0.000001)
                #expect(!before.isSettled)
                let height = motion.currentFrame!.revealHeights["cpu"]!

                motion.retarget(targets: ["cpu": 1], at: start + elapsed)
                let after = motion.tracks["cpu"]!
                #expect(abs(after.startVelocity - (before.holdsCollapsedReveal ? 0 : velocity)) < 0.000001)
                #expect(abs(after.startPhase - (before.holdsCollapsedReveal ? 0 : position)) < 0.000001)
                #expect(abs(motion.currentFrame!.revealHeights["cpu"]! - height) < 0.000001)
                if before.holdsCollapsedReveal {
                    motion.advance(to: start + elapsed + 1 / rate)
                    let expected: Double = spring.value(target: 1.0, initialVelocity: 0, time: 1 / rate)
                    #expect(abs(motion.tracks["cpu"]!.currentPhase - expected) < 0.000001)
                    #expect(motion.currentFrame!.revealHeights["cpu"]! > 0)
                }
                motion.cancel()
            }
        }
    }

    @Test @MainActor func collapsedDetailStaysHiddenAcrossSkippedFramesAndSpringRebound() {
        for natural in [CGFloat(284), 1200, 10000] {
            let motion = closingMotion(detailHeight: natural)
            let start = motion.tracks["cpu"]!.startTime
            let presentation = motion.presentation(for: "cpu")
            let closed = PanelGeometrySolver.solve(snapshot: motion.registry.makeSnapshot()!, phases: [:])
            // 两次采样跨过整个负相位区间，仍须识别已经到达收起边界。
            motion.advance(to: start + 0.20)
            for elapsed in [0.53, 0.60, 0.70, 0.90, 1.20, 1.50] {
                motion.advance(to: start + elapsed)
                #expect(motion.currentFrame!.revealHeights["cpu"] == 0)
                #expect(motion.currentFrame!.cardFrames["cpu"]!.height == 34)
                #expect(motion.currentFrame!.windowContentSize == closed.windowContentSize)
                #expect(presentation.sample.revealHeight == 0)
                #expect(presentation.sample.opacity == 0)
            }
            #expect(!motion.isAnimating)
            #expect(motion.tracks["cpu"]!.isSettled)
        }
    }

    @Test @MainActor func geometryChangePreservesHiddenMomentumAndClosedPresentation() {
        for elapsed in [0.24, 0.53] {
            let motion = closingMotion()
            let start = motion.tracks["cpu"]!.startTime
            motion.advance(to: start + elapsed)
            let before = motion.tracks["cpu"]!
            motion.registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 568, revision: 1)
            motion.geometryDidChange()
            let after = motion.tracks["cpu"]!
            #expect(abs(before.currentPhase * 284 - after.currentPhase * 568) < 0.000001)
            #expect(abs(before.currentVelocity * 284 - after.currentVelocity * 568) < 0.000001)
            #expect(motion.currentFrame!.revealHeights["cpu"] == 0)
            motion.retarget(targets: ["cpu": 0], at: start + elapsed)
            motion.advance(to: start + elapsed + 0.1)
            #expect(motion.currentFrame!.revealHeights["cpu"] == 0)
            motion.cancel()
        }
    }

    @Test @MainActor func collapseInitiallyRetainsOutwardMomentumBeforeReachingBoundary() {
        let motion = closingMotion()
        let now = motion.currentFrame!.sampleTime
        motion.setInstantly(targets: ["cpu": 0])
        motion.retarget(targets: ["cpu": 1], at: now)
        motion.advance(to: now + 0.10)
        motion.retarget(targets: ["cpu": 0], at: now + 0.10)
        let height = motion.currentFrame!.revealHeights["cpu"]!
        motion.advance(to: now + 0.11)
        #expect(motion.currentFrame!.revealHeights["cpu"]! > height)
        #expect(motion.tracks["cpu"]!.currentVelocity > 0)
        motion.cancel()
    }

    @Test @MainActor func unavailableContentRetainsIntentUntilRealDataArrives() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu"))
        registry.configureStructure(topLevelIDs: ["cpu"])
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 284, isAvailable: false, revision: 1)
        let motion = SingleHostMotionCoordinator(registry: registry)
        motion.retarget(targets: ["cpu": 1])
        #expect(motion.currentFrame?.revealHeights["cpu"] == 0)
        #expect(!motion.isAnimating)
        registry.setSectionAvailability(id: "cpu", isAvailable: true)
        motion.geometryDidChange()
        let resumedTime = motion.currentFrame!.sampleTime
        motion.advance(to: resumedTime + 0.1)
        #expect((motion.currentFrame?.revealHeights["cpu"] ?? 0) > 0)
        #expect(motion.tracks["cpu"]?.targetPhase == 1)
        motion.cancel()
    }

    @Test func analyticMotionMatchesSwiftUISpringAcrossInterruptions() {
        let analytic = DampedSpring()
        let reference = Spring(response: 0.32, dampingRatio: 0.82)
        for start in [0.0, 37, 300] {
            for target in [0.0, 284] {
                for velocity in [-450.0, 0, 730] {
                    for step in 0...100 {
                        let time = Double(step) / 120
                        let sample = analytic.evaluate(start: start, target: target, startVelocity: velocity, elapsed: time)
                        let position = start + reference.value(target: target - start, initialVelocity: velocity, time: time)
                        let speed = reference.velocity(target: target - start, initialVelocity: velocity, time: time)
                        #expect(abs(sample.position - position) < 0.00001)
                        #expect(abs(sample.velocity - speed) < 0.00001)
                    }
                }
            }
        }
    }

    @Test @MainActor func hiddenMotionRejectsLateDisplayCallbacksAndResumesContinuously() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu"))
        registry.configureStructure(topLevelIDs: ["cpu"])
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 284, revision: 1)
        let adapter = MockSubmissionAdapter()
        let motion = SingleHostMotionCoordinator(registry: registry, adapter: adapter)
        let now = CACurrentMediaTime()
        motion.retarget(targets: ["cpu": 1], at: now)
        motion.advance(to: now + 0.1)
        let before = motion.currentFrame
        let submissions = adapter.submittedSizes.count
        motion.suspend()
        motion.advance(to: now + 3)
        #expect(!motion.isAnimating)
        #expect(motion.currentFrame == before)
        #expect(adapter.submittedSizes.count == submissions)
        motion.resume()
        #expect(motion.currentFrame?.revealHeights == before?.revealHeights)
        motion.cancel()
    }

    @Test @MainActor func parentCollapseRetargetsChildrenTogetherAndRemovalClearsPendingReveal() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "display"))
        registry.contentHeightCap = 250
        registry.configureStructure(topLevelIDs: ["display"], hierarchy: ["display": ["a", "b"]],
            childGroups: ["display": PanelChildGroup(ids: ["a", "b"], leading: 38, trailing: 10, top: 9, bottom: 9, spacing: 17)])
        registry.reportMeasurement(id: "display", headerHeight: 34, detailHeight: 0, revision: 1)
        for id in ["a", "b"] {
            registry.reportMeasurement(id: id, parentID: "display", headerHeight: 18, detailHeight: 400,
                                       revision: 1, collapsedDetailHeight: 80)
        }
        let motion = SingleHostMotionCoordinator(registry: registry)
        motion.setInstantly(targets: ["display": 1, "a": 1, "b": 1])
        let now = motion.currentFrame!.sampleTime + 1
        motion.retarget(targets: ["display": 0], at: now)
        #expect(motion.tracks["display"]!.startTime == motion.tracks["a"]!.startTime)
        #expect(motion.tracks["a"]!.targetPhase == 0 && motion.tracks["b"]!.targetPhase == 0)
        motion.advance(to: now + 0.2)
        #expect(!motion.tracks["display"]!.isSettled)
        for step in 21...120 { motion.advance(to: now + Double(step) / 100) }
        #expect(motion.currentFrame?.cardFrames["display"]?.height == 34)
        motion.setInstantly(targets: ["display": 1])
        motion.userScrollBegan(at: 0)
        motion.retarget(targets: ["b": 1], at: now + 2)
        registry.configureStructure(topLevelIDs: ["display"], hierarchy: ["display": ["a"]],
            childGroups: ["display": PanelChildGroup(ids: ["a"], leading: 38, trailing: 10, top: 9, bottom: 9)])
        motion.geometryDidChange()
        #expect(motion.tracks["b"] == nil)
        #expect(motion.currentFrame?.childFrames["b"] == nil)
        motion.userScrollEnded(at: 0)
        for step in 1...120 { motion.advance(to: now + 2 + Double(step) / 100) }
        #expect(motion.currentFrame?.scrollOffset == 0)
        motion.cancel()
    }

    @Test @MainActor func expansionDuringDecelerationResumesOnlyPendingReveal() {
        for cancelIntent in [false, true] {
            let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
                width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu,gpu"))
            registry.contentHeightCap = 250
            registry.configureStructure(topLevelIDs: ["cpu", "gpu"])
            for id in ["cpu", "gpu"] {
                registry.reportMeasurement(id: id, headerHeight: 34, detailHeight: 284, revision: 1)
            }
            let motion = SingleHostMotionCoordinator(registry: registry)
            motion.setInstantly(targets: ["cpu": 1])
            let now = motion.currentFrame!.sampleTime + 1
            motion.userScrollBegan(at: 20)
            motion.retarget(targets: ["gpu": 1], at: now)
            for step in 1...80 { motion.advance(to: now + Double(step) / 100) }
            #expect(motion.currentFrame?.scrollOffset == 20)
            if cancelIntent { motion.userScrollBegan(at: 20) }
            motion.userScrollEnded(at: 20)
            for step in 81...180 { motion.advance(to: now + Double(step) / 100) }
            let frame = motion.currentFrame!
            #expect(abs(frame.scrollOffset - (cancelIntent ? 20 : frame.cardFrames["gpu"]!.maxY - frame.viewportHeight)) < 0.001)
            motion.cancel()
        }
    }

    @Test @MainActor func userScrollTakesOverAutomaticRevealAndUncappingLeavesNoGap() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu,gpu"))
        registry.contentHeightCap = 250
        registry.configureStructure(topLevelIDs: ["cpu", "gpu"])
        for id in ["cpu", "gpu"] { registry.reportMeasurement(id: id, headerHeight: 34, detailHeight: 284, revision: 1) }
        let motion = SingleHostMotionCoordinator(registry: registry)
        let now = CACurrentMediaTime()
        motion.retarget(targets: ["gpu": 1, "cpu": 1], at: now)
        #expect(motion.currentFrame?.scrollOffset == 0)
        motion.advance(to: now + 0.12)
        #expect((motion.currentFrame?.scrollOffset ?? 0) > 0)
        motion.userScrollBegan(at: 20)
        motion.advance(to: now + 0.2)
        #expect(motion.currentFrame?.scrollOffset == 20)
        motion.userScrollEnded(at: 20)
        motion.retarget(targets: ["cpu": 0, "gpu": 0], at: now + 0.2)
        for step in 21...120 {
            motion.advance(to: now + Double(step) / 100)
            if let frame = motion.currentFrame {
                #expect(frame.scrollOffset >= 0)
                #expect(frame.scrollOffset + frame.viewportHeight <= frame.bodyDocumentHeight + 0.0001)
            }
        }
        #expect(motion.currentFrame?.scrollOffset == 0)
        #expect(!motion.isAnimating)
    }

    @Test @MainActor func realCoordinatorReversesFromLastPresentedTimeAndStopsAtZero() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu"))
        registry.configureStructure(topLevelIDs: ["cpu"])
        registry.reportMeasurement(id: "cpu", headerHeight: 34, detailHeight: 300, revision: 1)
        let motion = SingleHostMotionCoordinator(registry: registry)
        let now = CACurrentMediaTime()
        motion.retarget(targets: ["cpu": 1], at: now)
        motion.advance(to: now + 0.10)
        let before = motion.tracks["cpu"]!
        motion.retarget(targets: ["cpu": 0], at: now + 0.09)
        let after = motion.tracks["cpu"]!
        #expect(abs(before.currentPhase - after.startPhase) < 0.000001)
        #expect(abs(before.currentVelocity - after.startVelocity) < 0.000001)
        for step in 11...150 { motion.advance(to: now + Double(step) / 100) }
        #expect(motion.currentFrame?.revealHeights["cpu"] == 0)
        #expect(!motion.isAnimating)
        #expect(motion.tracks["cpu"]?.currentVelocity == 0)
    }

    @Test @MainActor func reducedMotionSettlesOtherActiveTracksAndInvalidatesClock() {
        let registry = PanelDimensionRegistry(initialEnvironment: GeometryEnvironmentToken(
            width: 340, localeIdentifier: "en", dynamicTypeSize: "default", backingScale: 2, structureSignature: "cpu,gpu"))
        registry.configureStructure(topLevelIDs: ["cpu", "gpu"])
        for id in ["cpu", "gpu"] { registry.reportMeasurement(id: id, headerHeight: 34, detailHeight: 200, revision: 1) }
        let motion = SingleHostMotionCoordinator(registry: registry)
        let now = CACurrentMediaTime()
        motion.retarget(targets: ["cpu": 1, "gpu": 1], at: now)
        motion.advance(to: now + 0.10)
        motion.retarget(targets: ["cpu": 0], at: now + 0.12, reduceMotion: true)
        #expect(!motion.isAnimating)
        #expect(motion.currentFrame?.revealHeights["cpu"] == 0)
        #expect(motion.currentFrame?.revealHeights["gpu"] == 200)
        #expect(motion.tracks.values.allSatisfy { $0.isSettled })
    }
}
