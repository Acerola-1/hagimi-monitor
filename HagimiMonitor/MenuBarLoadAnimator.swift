import AppKit
import Combine
import Foundation

/// 连续轨迹独立于计时器频率；整数取整仅用于最终图标，不回灌运动状态。
nonisolated struct MenuBarLoadMotion {
    var start: Double
    var target: Double
    var velocity: Double
    var startTime: TimeInterval

    func sample(at time: TimeInterval) -> (position: Double, velocity: Double) {
        let elapsed = max(0, time - startTime)
        let frequency = MonitorConstants.menuBarLoadMotionFrequency
        let displacement = start - target
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * elapsed)
        let position = target + (displacement + coefficient * elapsed) * decay
        let speed = (coefficient - frequency * (displacement + coefficient * elapsed)) * decay
        if position <= 0 { return (0, max(0, speed)) }
        if position >= 100 { return (100, min(0, speed)) }
        return (position, speed)
    }
}

/// 仅在目标变化时运行；与面板内容的发布通道独立，避免拖动整个 ViewGraph。
@MainActor
final class MenuBarLoadAnimator: ObservableObject {
    @Published private(set) var displayedComputeLoad = 0.0
    private var motion: MenuBarLoadMotion
    private var smoothingTimerCancellable: AnyCancellable?
    private var animationEnabled = true
    private var suspensionDeadline: TimeInterval = 0
    private let now: () -> TimeInterval
    private let wallNow: () -> Date
    private let reduceMotion: () -> Bool
    private let scheduleFrames: (@escaping () -> Void) -> AnyCancellable

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallNow: @escaping () -> Date = { Date() },
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         scheduleFrames: ((@escaping () -> Void) -> AnyCancellable)? = nil) {
        self.now = now
        self.wallNow = wallNow
        self.reduceMotion = reduceMotion
        self.scheduleFrames = scheduleFrames ?? { tick in
            Timer.publish(every: MonitorConstants.menuBarLoadSmoothFrameInterval, on: .main, in: .common)
                .autoconnect().sink { _ in tick() }
        }
        motion = MenuBarLoadMotion(start: 0, target: 0, velocity: 0, startTime: now())
    }

    func updateTarget(_ value: Double) {
        let target = min(100, max(0, value))
        guard ComputeLoadModel.shouldUpdateMenuBarTarget(currentTarget: motion.target, nextTarget: target) else { return }
        let time = now()
        let current = motion.sample(at: time)
        motion = MenuBarLoadMotion(start: current.position, target: target, velocity: current.velocity,
            startTime: max(time, suspensionDeadline))
        if !animationEnabled || reduceMotion() {
            settle()
        } else {
            ensureSmoothingTimer()
        }
    }

    /// 纯指标模式不运行图标动画；切回环形模式时已有最新有效读数。
    func setAnimationEnabled(_ enabled: Bool) {
        guard animationEnabled != enabled else { return }
        animationEnabled = enabled
        if !enabled { settle() }
    }

    /// 展开期间停在已显示位置，恢复时从静止渐进，不把暂停时间算成动画时间。
    func suspend(until deadline: Date) {
        let time = now()
        let resumeTime = time + max(0, deadline.timeIntervalSince(wallNow()))
        guard resumeTime > max(time, suspensionDeadline) else { return }
        suspensionDeadline = resumeTime
        motion = MenuBarLoadMotion(start: displayedComputeLoad, target: motion.target,
            velocity: 0, startTime: resumeTime)
    }

    private func advanceSmoothing() {
        let time = now()
        guard time >= suspensionDeadline else { return }
        let value = motion.sample(at: time)
        if abs(value.position - motion.target) <= MonitorConstants.menuBarLoadSmoothStopThreshold,
           abs(value.velocity) <= MonitorConstants.menuBarLoadSmoothStopVelocity {
            settle()
        } else {
            publish(value.position)
        }
    }

    private func ensureSmoothingTimer() {
        guard animationEnabled, smoothingTimerCancellable == nil else { return }
        smoothingTimerCancellable = scheduleFrames { [weak self] in self?.advanceSmoothing() }
    }

    private func publish(_ load: Double) {
        let bucket = min(100, max(0, load)).rounded()
        if bucket != displayedComputeLoad { displayedComputeLoad = bucket }
    }

    private func settle() {
        let target = motion.target
        motion = MenuBarLoadMotion(start: target, target: target, velocity: 0, startTime: now())
        publish(target)
        smoothingTimerCancellable?.cancel()
        smoothingTimerCancellable = nil
    }
}
