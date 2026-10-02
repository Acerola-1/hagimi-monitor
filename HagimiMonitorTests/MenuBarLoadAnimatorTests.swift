import AppKit
import Combine
import SwiftUI
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct MenuBarLoadAnimatorTests {
    private final class Frames {
        var time = 100.0
        var tick: (() -> Void)?
        var starts = 0
        var stops = 0
        var wallTime: Date { Date(timeIntervalSince1970: time) }
        func schedule(_ callback: @escaping () -> Void) -> AnyCancellable {
            tick = callback
            starts += 1
            return AnyCancellable { [weak self] in
                MainActor.assumeIsolated {
                    self?.tick = nil
                    self?.stops += 1
                }
            }
        }
        func fire(after interval: TimeInterval) { time += interval; tick?() }
    }

    private func animator(_ frames: Frames, reduced: Bool = false) -> MenuBarLoadAnimator {
        MenuBarLoadAnimator(now: { frames.time }, wallNow: { frames.wallTime },
            reduceMotion: { reduced }, scheduleFrames: frames.schedule)
    }

    @Test func newTargetDoesNotReplaceCurrentPresentation() {
        let frames = Frames(); let animator = animator(frames)
        animator.updateTarget(80)
        #expect(animator.displayedComputeLoad == 0)
        frames.fire(after: MonitorConstants.menuBarLoadSmoothFrameInterval)
        #expect(animator.displayedComputeLoad > 0)
        #expect(animator.displayedComputeLoad < 8)
        #expect(frames.starts == 1)
    }

    @Test func callbackCadenceDoesNotChangeElapsedTimePosition() {
        let regular = Frames(); let irregular = Frames()
        let first = animator(regular); let second = animator(irregular)
        first.updateTarget(80); second.updateTarget(80)
        for _ in 0..<6 { regular.fire(after: 1.0 / 24) }
        for interval in [0.02, 0.07, 0.16] { irregular.fire(after: interval) }
        #expect(first.displayedComputeLoad == second.displayedComputeLoad)
        #expect(first.displayedComputeLoad == 48)
        first.setAnimationEnabled(false); second.setAnimationEnabled(false)
    }

    @Test func reversalPreservesPositionAndVelocity() {
        let upward = MenuBarLoadMotion(start: 20, target: 90, velocity: 0, startTime: 0)
        let current = upward.sample(at: 0.18)
        let reverse = MenuBarLoadMotion(start: current.position, target: 10,
            velocity: current.velocity, startTime: 0.18)
        let initial = reverse.sample(at: 0.18)
        #expect(abs(initial.position - current.position) < 1e-9)
        #expect(abs(initial.velocity - current.velocity) < 1e-9)
        #expect(abs(reverse.sample(at: 2).position - 10) < 0.01)
    }

    @Test func largeStepIsBoundedAndMonotonicWithoutRoundingFeedback() {
        for (start, target) in [(0.0, 100.0), (100.0, 0.0)] {
            let motion = MenuBarLoadMotion(start: start, target: target, velocity: 0, startTime: 0)
            var previous = start
            for index in 0...240 {
                let sample = motion.sample(at: Double(index) / 120)
                #expect((0...100).contains(sample.position))
                #expect(sample.position.isFinite && sample.velocity.isFinite)
                #expect(target > start ? sample.position >= previous : sample.position <= previous)
                previous = sample.position
            }
            #expect(abs(previous - target) < 0.001)
        }
    }

    @Test func suspensionFreezesThenEasesToNewestTarget() {
        let frames = Frames(); let animator = animator(frames)
        animator.updateTarget(80)
        frames.fire(after: 0.2)
        let held = animator.displayedComputeLoad
        animator.suspend(until: frames.wallTime.addingTimeInterval(1))
        frames.fire(after: 0.7)
        animator.updateTarget(10)
        frames.fire(after: 0.2)
        #expect(animator.displayedComputeLoad == held)
        frames.fire(after: 0.1)
        #expect(animator.displayedComputeLoad == held)
        frames.fire(after: 1.0 / 24)
        #expect(animator.displayedComputeLoad < held)
        #expect(held - animator.displayedComputeLoad < 4)
        frames.fire(after: 2)
        #expect(animator.displayedComputeLoad == 10)
        #expect(frames.tick == nil)
    }

    @Test func stableTargetsAndMetricsModeStopFrameWork() {
        let frames = Frames(); let animator = animator(frames)
        animator.setAnimationEnabled(false)
        animator.updateTarget(80)
        #expect(animator.displayedComputeLoad == 80)
        #expect(frames.starts == 0)
        animator.setAnimationEnabled(true)
        animator.updateTarget(20)
        frames.fire(after: 2)
        #expect(animator.displayedComputeLoad == 20)
        #expect(frames.tick == nil)
        #expect(frames.stops == 1)
        animator.updateTarget(20)
        #expect(frames.starts == 1)
    }

    @Test func smallThresholdCrossingIsNotDropped() {
        let frames = Frames(); let animator = animator(frames)
        animator.updateTarget(49); frames.fire(after: 2)
        animator.updateTarget(51)
        #expect(frames.starts == 2)
        #expect(animator.displayedComputeLoad == 49)
        frames.fire(after: 2)
        #expect(animator.displayedComputeLoad == 51)
    }

    @Test func reducedMotionAppliesEndpointWithoutSchedulingFrames() {
        let frames = Frames(); let animator = animator(frames, reduced: true)
        animator.updateTarget(92)
        #expect(animator.displayedComputeLoad == 92)
        #expect(frames.starts == 0)
    }

    @Test func previewLeafObservesAnimationWithoutStorePublication() async throws {
        let frames = Frames(); let animator = animator(frames)
        let renderer = ImageRenderer(content: MenuBarLoadRingPreview(animator: animator, darkMode: false))
        renderer.scale = 2
        let before = try #require(renderer.cgImage?.dataProvider?.data) as Data
        animator.updateTarget(80)
        frames.fire(after: 0.25)
        try await Task.sleep(for: .milliseconds(30))
        let after = try #require(renderer.cgImage?.dataProvider?.data) as Data
        #expect(before != after)
    }

    @Test func colorIsContinuousAcrossEveryLevelBoundary() throws {
        for dark in [false, true] {
            for boundary in MonitorConstants.menuBarLoadLevelBoundaries {
                let before = try #require(MenuBarComputeLoadLevel.ringColor(for: boundary - 0.001, darkMode: dark).usingColorSpace(.deviceRGB))
                let after = try #require(MenuBarComputeLoadLevel.ringColor(for: boundary + 0.001, darkMode: dark).usingColorSpace(.deviceRGB))
                #expect(abs(before.redComponent - after.redComponent) < 0.001)
                #expect(abs(before.greenComponent - after.greenComponent) < 0.001)
                #expect(abs(before.blueComponent - after.blueComponent) < 0.001)
            }
        }
    }

    @Test func aggregateRemainsMonotonicAndBetweenMeanAndMaximum() {
        for pressure in [MemoryPressureLevel.normal, .warning, .critical] {
            for gpu in stride(from: 0.0, through: 100.0, by: 10) {
                var previous = -1.0
                for cpu in stride(from: 0.0, through: 100.0, by: 5) {
                    let value = ComputeLoadModel.combined(cpuValue: cpu, gpuValue: gpu, memoryPressure: pressure)
                    let memory = ComputeLoadModel.memoryPressureScore(pressure)
                    #expect(value >= previous)
                    #expect(value >= (cpu + gpu + memory) / 3 - 1e-9)
                    #expect(value <= max(cpu, gpu, memory) + 1e-9)
                    previous = value
                }
            }
        }
    }
}
