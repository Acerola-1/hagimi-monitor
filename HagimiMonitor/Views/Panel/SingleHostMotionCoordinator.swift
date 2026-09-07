import AppKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - DampedSpring

/// 欠阻尼弹簧解析求解器（response 0.32 / damping 0.82）。
/// 纯解析闭式解，零数值累积误差，帧率无关，支持无缝 C1 连续中断重定向。
struct DampedSpring: Sendable {
    let response: Double
    let dampingRatio: Double

    private let omega: Double
    private let zetaOmega: Double
    private let dampedOmega: Double

    init(response: Double = MonitorConstants.panelExpansionSpringResponse,
         dampingRatio: Double = MonitorConstants.panelExpansionSpringDamping) {
        self.response = max(0.01, response)
        self.dampingRatio = max(0.0, dampingRatio)

        self.omega = 2.0 * Double.pi / self.response
        self.zetaOmega = self.dampingRatio * self.omega
        let underdamped = max(0.0001, 1.0 - pow(self.dampingRatio, 2))
        self.dampedOmega = self.omega * underdamped.squareRoot()
    }

    /// 计算自 t0 起经过 elapsed 秒后的位置与速度。
    func evaluate(
        start: Double,
        target: Double,
        startVelocity: Double,
        elapsed: Double
    ) -> (position: Double, velocity: Double) {
        guard elapsed > 0 else {
            return (start, startVelocity)
        }

        let distance = target - start
        let a = -distance
        let b = (startVelocity + zetaOmega * a) / dampedOmega
        let decay = exp(-zetaOmega * elapsed)

        let phase = dampedOmega * elapsed
        let cosP = cos(phase)
        let sinP = sin(phase)

        let position = target + decay * (a * cosP + b * sinP)
        let velocity = decay * (
            -zetaOmega * (a * cosP + b * sinP)
            + (-a * dampedOmega * sinP + b * dampedOmega * cosP)
        )

        return (position, velocity)
    }

    /// 判定是否收敛到目标。
    func isSettled(position: Double, target: Double, velocity: Double) -> Bool {
        abs(position - target) < 0.002 && abs(velocity) < 0.02
    }

    /// 目标为零时首次到达下边界的时间，跨过负相位区间的迟到采样也可识别。
    func firstZeroCrossing(start: Double, startVelocity: Double) -> Double {
        guard start >= 0, start > 0 || startVelocity > 0 else { return 0 }
        let b = (startVelocity + zetaOmega * start) / dampedOmega
        return atan2(start, -b) / dampedOmega
    }
}

/// 每个明细单独发布表现尺寸，静止的兄弟内容不订阅整块面板的帧变化。
@MainActor
final class PanelDetailPresentation: ObservableObject {
    @Published var sample = Sample()

    struct Sample: Equatable {
        var revealHeight: CGFloat = 0
        var opacity: Double = 0
    }
}

struct SectionMotionTrack: Sendable {
    var startPhase: Double
    var targetPhase: Double
    var startVelocity: Double
    var startTime: CFTimeInterval
    var currentPhase: Double
    var currentVelocity: Double
    var isSettled: Bool
    // 到达收起边界后保持零揭示，解析轨迹继续衰减直至能量收敛。
    var holdsCollapsedReveal = false

    var revealPhase: Double { holdsCollapsedReveal ? 0 : max(0, currentPhase) }
}

private struct ScrollMotionTrack {
    var start: Double
    var target: Double
    var velocity: Double
    var startTime: CFTimeInterval
    var currentVelocity: Double
}

@MainActor
protocol PanelWindowSubmissionAdapter: AnyObject {
    var isWindowUnoccluded: Bool { get }
    func bindMotion(_ motion: SingleHostMotionCoordinator)
    func geometryDidPrepare()
    func submitWindowFrame(size: CGSize, frameID: UInt)
    func currentScreen() -> NSScreen?
    func completePresentationLayout()
}

extension PanelWindowSubmissionAdapter {
    var isWindowUnoccluded: Bool { true }
    func bindMotion(_ motion: SingleHostMotionCoordinator) {}
    func geometryDidPrepare() {}
    func completePresentationLayout() {}
}

/// 活动期的显示帧时钟共享一个几何样本。实际屏幕呈现由原生回归验证。
@MainActor
final class SingleHostMotionCoordinator: NSObject, ObservableObject {
    @Published private(set) var currentFrame: PanelFrame?
    private(set) var tracks: [String: SectionMotionTrack] = [:]
    private let spring = DampedSpring()
    private var displayLink: CADisplayLink?
    private var displayScreen: NSScreen?
    @Published private(set) var isSuspended = false
    let hiddenPanelReset = PassthroughSubject<Void, Never>()
    private var frameID: UInt = 0
    private var lastSampleTime: CFTimeInterval = 0
    private var snapshot: GeometrySnapshot?
    private var presentations: [String: PanelDetailPresentation] = [:]
    private var pendingTargets: [String: CGFloat] = [:]
    private var desiredTargets: [String: CGFloat] = [:]
    private var scrollTrack: ScrollMotionTrack?
    private var scrollOffset: CGFloat = 0
    private var autoRevealID: String?
    private(set) var isUserScrolling = false
    private var onSettle: (() -> Void)?
    var onMotionFrame: (() -> Void)?
    var resetForHiddenPanel: (() -> Void)?
    var registry: PanelDimensionRegistry
    weak var submissionAdapter: PanelWindowSubmissionAdapter?
    var isAnimating: Bool { displayLink != nil }

    init(registry: PanelDimensionRegistry, adapter: PanelWindowSubmissionAdapter? = nil) {
        self.registry = registry
        submissionAdapter = adapter
        super.init()
    }

    deinit { displayLink?.invalidate() }

    func presentation(for id: String) -> PanelDetailPresentation {
        if let value = presentations[id] { return value }
        let value = PanelDetailPresentation()
        let height = currentFrame?.revealHeights[id] ?? 0
        value.sample = PanelDetailPresentation.Sample(revealHeight: height,
            opacity: height > 0 ? min(1, max(0, tracks[id]?.revealPhase ?? 0)) : 0)
        presentations[id] = value
        return value
    }

    /// 等待完整版本就绪，再以可见点数和速度承接正在运动的分区。
    func geometryDidChange() {
        guard let next = registry.makeSnapshot(), next != snapshot else { return }
        let previous = snapshot
        let now = max(CACurrentMediaTime(), lastSampleTime)
        if let previous = snapshot, isAnimating {
            sampleTracks(at: now)
            let rebased = PanelDimensionRegistry.rebaseline(
                currentPhases: tracks.mapValues { CGFloat($0.currentPhase) },
                currentVelocities: tracks.mapValues { CGFloat($0.currentVelocity) },
                oldSnapshot: previous, newSnapshot: next,
                closedSections: Set(tracks.compactMap { $0.value.holdsCollapsedReveal ? $0.key : nil })
            )
            for id in tracks.keys {
                guard let phase = rebased.phases[id], var track = tracks[id] else { continue }
                track.startPhase = Double(phase)
                track.currentPhase = Double(phase)
                track.startVelocity = Double(rebased.velocities[id] ?? 0)
                track.currentVelocity = track.startVelocity
                track.startTime = now
                tracks[id] = track
            }
        }
        snapshot = next
        desiredTargets = desiredTargets.filter { next.sections[$0.key] != nil }
        tracks = tracks.filter { next.sections[$0.key] != nil }
        for (id, section) in next.sections where !section.isAvailable {
            tracks[id] = restingTrack(target: 0, at: now)
        }
        retargetScroll(at: now)
        submit(at: now)
        var targets = pendingTargets
        for (id, target) in desiredTargets where next.sections[id]?.isAvailable == true
            && previous?.sections[id]?.isAvailable != true && tracks[id]?.targetPhase != Double(target) {
            targets[id] = target
        }
        if !targets.isEmpty {
            pendingTargets.removeAll()
            retarget(targets: targets)
        }
        if previous == nil { submissionAdapter?.geometryDidPrepare() }
    }

    func retarget(targets: [String: CGFloat], onSettle: (() -> Void)? = nil) {
        retarget(targets: targets, at: max(CACurrentMediaTime(), lastSampleTime),
                 reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 onSettle: onSettle)
    }

    func retarget(targets: [String: CGFloat], at time: CFTimeInterval,
                  reduceMotion: Bool = false, onSettle: (() -> Void)? = nil) {
        let targets = targetsIncludingCollapsedChildren(targets)
        desiredTargets.merge(targets) { _, new in new }
        if isSuspended {
            setInstantly(targets: targets)
            return
        }
        guard registry.isReady else {
            pendingTargets.merge(targets) { _, new in new }
            return
        }
        if snapshot == nil { snapshot = registry.makeSnapshot() }
        let now = max(time, lastSampleTime)
        sampleTracks(at: now)
        let added = Set(targets.compactMap { id, target in
            target > 0 && (tracks[id]?.targetPhase ?? 0) == 0
                && snapshot?.sections[id]?.isAvailable == true ? id : nil
        })
        self.onSettle = onSettle
        for (id, target) in targets {
            guard snapshot?.sections[id]?.isAvailable == true else { continue }
            if tracks[id]?.targetPhase == Double(target) { continue }
            let old = tracks[id] ?? restingTrack(target: 0, at: now)
            // 零揭示保持态的可见位置与速度均为零，重新展开从此边界启动。
            let reopeningFromBoundary = old.holdsCollapsedReveal && target > 0
            let phase = reopeningFromBoundary ? 0 : old.currentPhase
            let velocity = reopeningFromBoundary ? 0 : old.currentVelocity
            tracks[id] = SectionMotionTrack(
                startPhase: phase, targetPhase: Double(target),
                startVelocity: velocity, startTime: now,
                currentPhase: phase, currentVelocity: velocity,
                isSettled: false, holdsCollapsedReveal: target == 0 && old.holdsCollapsedReveal
            )
        }
        if let snapshot {
            if let target = PanelScrollCoordinator.targetSectionForAutoReveal(addedIDs: added,
                    visualOrder: snapshot.visualOrder) {
                autoRevealID = target
            } else if let id = autoRevealID, targets[id] == 0 {
                autoRevealID = nil
            }
            retargetScroll(at: now)
        }
        if reduceMotion {
            settleAll(at: now)
        } else {
            submit(at: now)
            ensureDisplayLink()
        }
    }

    /// 父级关闭时，同一采样时刻把全部后代一起重定向到各自收起端点。
    private func targetsIncludingCollapsedChildren(_ targets: [String: CGFloat]) -> [String: CGFloat] {
        var result = targets
        var visited: Set<String> = []
        func collapse(_ id: String) {
            guard visited.insert(id).inserted else { return }
            for child in registry.childrenByParent[id] ?? [] {
                result[child] = 0
                collapse(child)
            }
        }
        for (id, target) in targets where target == 0 { collapse(id) }
        return result
    }

    func setInstantly(targets: [String: CGFloat]) {
        let targets = targetsIncludingCollapsedChildren(targets)
        desiredTargets.merge(targets) { _, new in new }
        let now = max(CACurrentMediaTime(), lastSampleTime)
        if snapshot == nil { snapshot = registry.makeSnapshot() }
        for (id, target) in targets {
            let available = snapshot?.sections[id]?.isAvailable != false
            tracks[id] = restingTrack(target: available ? Double(target) : 0, at: now)
        }
        settleAll(at: now)
    }

    func cancel() {
        pendingTargets.removeAll()
        autoRevealID = nil
        scrollTrack = nil
        settleAll(at: max(CACurrentMediaTime(), lastSampleTime))
    }

    /// 淡出期间保持最后呈现的几何，隐藏后的尺寸登记不再写入窗口。
    func suspend() {
        isSuspended = true
        stopDisplayLink()
        onSettle = nil
        isUserScrolling = false
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        let now = max(CACurrentMediaTime(), lastSampleTime)
        for (id, var track) in tracks {
            track.startPhase = track.currentPhase
            track.startVelocity = track.currentVelocity
            track.startTime = now
            tracks[id] = track
        }
        if var track = scrollTrack {
            track.start = Double(currentFrame?.scrollOffset ?? scrollOffset)
            track.velocity = track.currentVelocity
            track.startTime = now
            scrollTrack = track
        }
        submit(at: now)
        ensureDisplayLink()
    }

    /// 原生滚动开始时从实际偏移接管，卡片轨迹保持运行。
    func userScrollBegan(at offset: CGFloat) {
        isUserScrolling = true
        autoRevealID = nil
        scrollTrack = nil
        updateUserScroll(offset)
    }

    func updateUserScroll(_ offset: CGFloat) {
        guard isUserScrolling, let frame = currentFrame else { return }
        scrollOffset = PanelScrollCoordinator.clampUserOffset(offset: offset, frame: frame)
        if frame.scrollOffset != scrollOffset {
            var next = frame
            next.scrollOffset = scrollOffset
            currentFrame = next
        }
    }

    func userScrollEnded(at offset: CGFloat) {
        guard isUserScrolling else { return }
        updateUserScroll(offset)
        isUserScrolling = false
        guard autoRevealID != nil else { return }
        let now = max(CACurrentMediaTime(), lastSampleTime)
        retargetScroll(at: now)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settleAll(at: now)
        } else {
            ensureDisplayLink()
        }
    }

    private func retargetScroll(at time: CFTimeInterval) {
        guard let snapshot, !isUserScrolling else { return }
        let finalFrame = PanelGeometrySolver.solve(snapshot: snapshot,
            phases: tracks.mapValues { CGFloat($0.targetPhase) }, scrollOffset: scrollOffset)
        if let id = autoRevealID, finalFrame.sectionFrames[id] == nil || tracks[id]?.targetPhase == 0 {
            autoRevealID = nil
        }
        let target = autoRevealID == nil ? finalFrame.scrollOffset
            : PanelScrollCoordinator.calculateScrollOffset(for: autoRevealID, frame: finalFrame)
        let start = currentFrame?.scrollOffset ?? scrollOffset
        let velocity = abs(start - scrollOffset) < 0.05 ? (scrollTrack?.currentVelocity ?? 0) : 0
        scrollOffset = start
        scrollTrack = abs(target - start) > 0.05 || abs(velocity) > 0.5
            ? ScrollMotionTrack(start: Double(start), target: Double(target), velocity: velocity,
                                startTime: time, currentVelocity: velocity) : nil
    }

    private func restingTrack(target: Double, at time: CFTimeInterval) -> SectionMotionTrack {
        SectionMotionTrack(startPhase: target, targetPhase: target, startVelocity: 0,
                           startTime: time, currentPhase: target, currentVelocity: 0,
                           isSettled: true, holdsCollapsedReveal: target == 0)
    }

    private func settleAll(at time: CFTimeInterval) {
        stopDisplayLink()
        for (id, track) in tracks { tracks[id] = restingTrack(target: track.targetPhase, at: time) }
        if let scrollTrack { scrollOffset = CGFloat(scrollTrack.target) }
        scrollTrack = nil
        submit(at: time)
        let completion = onSettle
        onSettle = nil
        completion?()
    }

    private func ensureDisplayLink() {
        guard !isSuspended, displayLink == nil,
              scrollTrack != nil || tracks.values.contains(where: { !$0.isSettled }) else { return }
        guard let screen = submissionAdapter?.currentScreen() ?? NSScreen.main else {
            settleAll(at: max(CACurrentMediaTime(), lastSampleTime))
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(handleDisplayFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        displayScreen = screen
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayScreen = nil
    }

    @objc private func handleDisplayFrame(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp)
    }

    /// 显式时间入口供中断与不等帧间隔回归复用实际生产采样路径。
    func advance(to time: CFTimeInterval) {
        guard !isSuspended, displayLink != nil, time > lastSampleTime else { return }
        if let screen = submissionAdapter?.currentScreen(), screen != displayScreen {
            stopDisplayLink()
            ensureDisplayLink()
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            settleAll(at: time)
            return
        }
        sampleTracks(at: time)
        onMotionFrame?()
        submit(at: time)
        if tracks.values.allSatisfy(\.isSettled), scrollTrack == nil {
            stopDisplayLink()
            let completion = onSettle
            onSettle = nil
            completion?()
        }
    }

    private func sampleTracks(at time: CFTimeInterval) {
        let targetGeometry = snapshot.map {
            PanelGeometrySolver.solve(snapshot: $0, phases: tracks.mapValues { CGFloat($0.targetPhase) })
        }
        for (id, var track) in tracks where !track.isSettled {
            let elapsed = max(0, time - track.startTime)
            let result = spring.evaluate(start: track.startPhase, target: track.targetPhase,
                                         startVelocity: track.startVelocity, elapsed: elapsed)
            let base = snapshot?.sections[id]?.collapsedDetailHeight ?? 0
            let natural = max(1, abs((targetGeometry?.detailContentHeights[id] ?? 0) - base),
                              abs((currentFrame?.detailContentHeights[id] ?? 0) - base))
            let settled = abs(result.position - track.targetPhase) * natural < 0.05
                && abs(result.velocity) * natural < 0.5
            if settled {
                track = restingTrack(target: track.targetPhase, at: time)
            } else {
                track.currentPhase = result.position
                track.currentVelocity = result.velocity
                if track.targetPhase == 0,
                   elapsed >= spring.firstZeroCrossing(start: track.startPhase, startVelocity: track.startVelocity) {
                    track.holdsCollapsedReveal = true
                }
            }
            tracks[id] = track
        }
        if var track = scrollTrack {
            let value = spring.evaluate(start: track.start, target: track.target, startVelocity: track.velocity,
                                        elapsed: max(0, time - track.startTime))
            if abs(value.position - track.target) < 0.05 && abs(value.velocity) < 0.5 {
                scrollOffset = CGFloat(track.target)
                scrollTrack = nil
            } else {
                scrollOffset = CGFloat(value.position)
                track.currentVelocity = value.velocity
                scrollTrack = track
            }
        }
    }

    private func submit(at time: CFTimeInterval) {
        guard let snapshot else { return }
        lastSampleTime = max(time, lastSampleTime)
        frameID &+= 1
        let frame = PanelGeometrySolver.solve(snapshot: snapshot,
            phases: tracks.mapValues { CGFloat($0.revealPhase) }, frameID: frameID, sampleTime: lastSampleTime,
            scrollOffset: scrollOffset)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        withTransaction(transaction) {
            for (id, value) in presentations {
                let height = frame.revealHeights[id] ?? 0
                let sample = PanelDetailPresentation.Sample(revealHeight: height,
                    opacity: height > 0 ? min(1, max(0, tracks[id]?.revealPhase ?? 0)) : 0)
                if value.sample != sample { value.sample = sample }
            }
            currentFrame = frame
            if !isSuspended {
                submissionAdapter?.submitWindowFrame(size: frame.windowContentSize, frameID: frameID)
                submissionAdapter?.completePresentationLayout()
            }
        }
        CATransaction.commit()
    }
}
