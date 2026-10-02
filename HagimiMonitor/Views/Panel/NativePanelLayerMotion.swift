import AppKit
import Combine
import SwiftUI
import QuartzCore

nonisolated enum NativePanelMotionMode {
    static let testHost = ProcessInfo.processInfo.environment["HAGIMI_PANEL_TEST_HOST"]
        ?? Bundle.main.object(forInfoDictionaryKey: "HagimiPanelPreviewHost") as? String
    static let diagnostics = ProcessInfo.processInfo.environment["HAGIMI_PANEL_BENCH"] != nil

    /// 实机夹具显式选择屏幕；不改变用户的主屏、菜单栏或其他窗口。
    @MainActor static var testScreen: NSScreen? {
        guard let raw = ProcessInfo.processInfo.environment["HAGIMI_PANEL_TEST_DISPLAY"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "HagimiPanelPreviewDisplay") as? NSNumber)?.stringValue,
              let id = UInt32(raw) else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == id
        }
    }
}

/// 临界阻尼解析解；轨迹准备与事件查询使用同一函数，不依赖显示帧回调。
nonisolated struct NativePanelSpring {
    let frequency: Double
    init(frequency: Double = MonitorConstants.panelNativeMotionFrequency) { self.frequency = frequency }

    func sample(start: Double, target: Double, velocity: Double, elapsed: Double) -> (position: Double, velocity: Double) {
        let t = max(0, elapsed)
        let a = start - target
        let b = velocity + frequency * a
        let decay = exp(-frequency * t)
        return (target + (a + b * t) * decay, (b - frequency * (a + b * t)) * decay)
    }
}

nonisolated struct NativePanelPhaseTrack {
    var start: Double
    var target: Double
    var velocity: Double
    var time: CFTimeInterval

    func pointSample(at now: CFTimeInterval) -> (position: Double, velocity: Double) {
        NativePanelSpring().sample(start: start, target: target, velocity: velocity, elapsed: now - time)
    }

    func sample(at now: CFTimeInterval) -> (position: Double, velocity: Double) {
        let value = pointSample(at: now)
        // 合法边界是接触条件；所有几何从约束后的相位一起派生。
        if value.position <= 0 { return (0, max(0, value.velocity)) }
        if value.position >= 1 { return (1, min(0, value.velocity)) }
        return value
    }
}

nonisolated struct NativePanelMotionSample {
    var frame: PanelFrame
    var phases: [String: CGFloat]
}

nonisolated struct NativePanelAnimationPlan {
    var startTime: CFTimeInterval
    var duration: Double
    var samples: [NativePanelMotionSample]
    var generation: UInt
}

@MainActor
protocol NativePanelLayerRenderer: AnyObject {
    func applyNativePlan(_ plan: NativePanelAnimationPlan)
    func stopNativeMotion()
    func nativePanelDidShow()
}

extension NativePanelLayerRenderer { func nativePanelDidShow() {} }

@MainActor
private final class NativePanelRendererReference {
    weak var value: (any NativePanelLayerRenderer)?
    init(_ value: any NativePanelLayerRenderer) { self.value = value }
}

/// 与可见圆角路径同一几何，输入判定无需为每个候选时刻重新解算整块面板。
nonisolated enum NativePanelInputGeometry {
    static func contains(_ point: CGPoint, width: CGFloat, height: CGFloat,
                         radius: CGFloat = MonitorConstants.panelCornerRadius) -> Bool {
        guard width > 0, height > 0,
              CGRect(x: 0, y: 0, width: width, height: height).contains(point) else { return false }
        let rx = max(0, min(radius, width / 2))
        let ry = max(0, min(radius, height / 2))
        guard rx > 0, ry > 0 else { return true }
        let x = min(max(point.x, rx), width - rx)
        let y = min(max(point.y, ry), height - ry)
        let dx = (point.x - x) / rx
        let dy = (point.y - y) / ry
        return dx * dx + dy * dy <= 1
    }
}

/// 分区语义和自然尺寸在操作/结构变化时提交，系统图层负责两个提交之间的播放。
@MainActor
final class NativePanelLayerMotion {
    let registry: PanelDimensionRegistry
    private(set) var snapshot: GeometrySnapshot?
    private(set) var tracks: [String: NativePanelPhaseTrack] = [:]
    private(set) var generation: UInt = 0
    private(set) var isSuspended = false
    private(set) var isUserScrolling = false
    private(set) var plan: NativePanelAnimationPlan?
    var onCommit: ((PanelFrame, [String: CGFloat]) -> Void)?
    var onStart: (() -> Void)?
    private var renderers: [UUID: NativePanelRendererReference] = [:]
    private var measurements: [String: [String: CGSize]] = [:]
    private var groupSources: [String: [String: PanelChildGroup]] = [:]
    private var ids: [String] = []
    private var environment = GeometryEnvironmentToken(width: MonitorConstants.panelIdealWidth,
        localeIdentifier: Locale.current.identifier, dynamicTypeSize: "default", backingScale: 2, structureSignature: "")
    private var cap: CGFloat = 800
    private var geometryTicket: UInt = 0
    private var completion: DispatchWorkItem?
    private var desired: [String: CGFloat] = [:]
    private var scroll: NativePanelPhaseTrack?
    private var scrollOffset: CGFloat = 0
    private var revealID: String?
    private var moveOffsets: [String: NativePanelPhaseTrack] = [:]
    private var revealCorrections: [String: NativePanelPhaseTrack] = [:]
    private let clock: () -> CFTimeInterval
    var reduceMotionOverride: Bool?

    var isAnimating: Bool { !isSuspended && completion != nil }
    var hasAutomaticScroll: Bool { scroll != nil && !isUserScrolling }
    var fullFrame: PanelFrame? {
        snapshot.map { PanelGeometrySolver.solve(snapshot: $0, phases: $0.sections.mapValues { _ in 1 }) }
    }

    init(registry: PanelDimensionRegistry, clock: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.registry = registry; self.clock = clock
    }

    @discardableResult
    func register(_ renderer: any NativePanelLayerRenderer) -> UUID {
        let key = UUID()
        renderers[key] = NativePanelRendererReference(renderer)
        if let plan { renderer.applyNativePlan(plan) }
        return key
    }

    func unregister(_ key: UUID, owner: String) {
        renderers.removeValue(forKey: key)
        measurements.removeValue(forKey: owner)
        groupSources.removeValue(forKey: owner)
    }

    func configure(ids: [String], cap: CGFloat, environment: GeometryEnvironmentToken) {
        guard self.ids != ids || self.cap != cap || self.environment != environment else { return }
        self.ids = ids; self.cap = cap; self.environment = environment
        scheduleGeometry()
    }

    func report(owner: String, values: [String: CGSize], groups: [String: PanelChildGroup]? = nil) {
        let changed = measurements[owner] != values || (groups != nil && groupSources[owner] != groups)
        guard changed else { return }
        measurements[owner] = values
        if let groups { groupSources[owner] = groups }
        scheduleGeometry()
    }

    private func scheduleGeometry() {
        geometryTicket &+= 1
        let ticket = geometryTicket
        DispatchQueue.main.async { [weak self] in
            guard let self, ticket == self.geometryTicket else { return }
            self.prepareGeometry()
        }
    }

    private func prepareGeometry() {
        let values = measurements.values.reduce(into: [String: CGSize]()) { result, next in
            result.merge(next) { _, new in new }
        }
        let groups = groupSources.values.reduce(into: [String: PanelChildGroup]()) { result, next in
            result.merge(next) { _, new in new }
        }
        var allIDs = ids
        var seen = Set(ids)
        var index = 0
        while index < allIDs.count {
            for child in groups[allIDs[index]]?.ids ?? [] where seen.insert(child).inserted { allIDs.append(child) }
            index += 1
        }
        guard values["__header__"] != nil, values["__footer__"] != nil,
              allIDs.allSatisfy({ values["row:" + $0] != nil && values["detail:" + $0] != nil
                  && values["available:" + $0] != nil }) else {
            if ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil
                || Bundle.main.object(forInfoDictionaryKey: "HagimiPanelNativePreview") as? Bool == true {
                NSLog("[native-geometry] waiting ids=%@ values=%@", allIDs.joined(separator: ","), values.keys.sorted().joined(separator: ","))
            }
            return
        }
        var token = environment
        token.structureSignature = allIDs.map {
            "\($0):\(values["row:" + $0]!.height):\(values["detail:" + $0]!.height):\(values["collapsed:" + $0]?.height ?? 0):\(values["available:" + $0]!.width)"
        }.joined(separator: "|") + groups.keys.sorted().map { "\($0):\(groups[$0]!)" }.joined()
        _ = registry.updateEnvironment(token)
        registry.configureStructure(topLevelIDs: ids, hierarchy: groups.mapValues(\.ids), childGroups: groups)
        registry.contentHeightCap = cap
        registry.panelHeaderHeight = values["__header__"]!.height
        registry.footerHeight = values["__footer__"]!.height
        for id in allIDs {
            registry.reportMeasurement(id: id, parentID: groups.first { $0.value.ids.contains(id) }?.key,
                headerHeight: values["row:" + id]!.height, detailHeight: values["detail:" + id]!.height,
                isAvailable: values["available:" + id]!.width == 1, revision: registry.currentRevision,
                collapsedDetailHeight: values["collapsed:" + id]?.height ?? 0)
        }
        geometryDidChange()
    }

    private var measuredSnapshot: GeometrySnapshot? {
        var result = registry.makeSnapshot()
        result?.pinsFooter = true
        return result
    }

    func geometryDidChange(instantly: Bool = false) {
        guard !isSuspended, let next = measuredSnapshot, next != snapshot else { return }
        let now = clock()
        let oldFrame = sample(at: now)?.frame
        let step = 0.0000001
        let oldNext = sample(at: now + step)?.frame
        if let old = snapshot {
            let current = tracks.mapValues { $0.sample(at: now) }
            let rebased = PanelDimensionRegistry.rebaseline(currentPhases: current.mapValues { CGFloat($0.position) },
                currentVelocities: current.mapValues { CGFloat($0.velocity) }, oldSnapshot: old, newSnapshot: next)
            for id in next.sections.keys {
                tracks[id] = NativePanelPhaseTrack(start: Double(min(1, max(0, rebased.phases[id] ?? desired[id] ?? 0))),
                    target: Double(desired[id] ?? 0), velocity: Double(rebased.velocities[id] ?? 0), time: now)
            }
        }
        snapshot = next
        tracks = tracks.filter { next.sections[$0.key] != nil }
        for (id, section) in next.sections {
            if tracks[id] == nil { tracks[id] = NativePanelPhaseTrack(start: 0, target: Double(desired[id] ?? 0), velocity: 0, time: now) }
            if !section.isAvailable { tracks[id] = NativePanelPhaseTrack(start: 0, target: 0, velocity: 0, time: now) }
        }
        moveOffsets.removeAll()
        revealCorrections.removeAll()
        // 自然内容变矮时相位不能越过 1。独立的点数余量保住当前揭示高度与速度，
        // 并沿同一解析弹簧归零；父分区同时继承子分区的余量。
        if let oldFrame, let oldNext {
            var visited = Set<String>()
            func preserveReveal(_ id: String) {
                guard visited.insert(id).inserted else { return }
                for child in next.childrenByParent[id] ?? [] { preserveReveal(child) }
                guard next.sections[id]?.isAvailable == true,
                      let before = oldFrame.revealHeights[id], let beforeNext = oldNext.revealHeights[id],
                      let current = sample(at: now)?.frame.revealHeights[id],
                      let currentNext = sample(at: now + step)?.frame.revealHeights[id] else { return }
                revealCorrections[id] = NativePanelPhaseTrack(start: Double(before - current), target: 0,
                    velocity: Double((beforeNext - before - currentNext + current) / step), time: now)
            }
            for id in next.orderedTopLevelIDs { preserveReveal(id) }
        }
        if let oldFrame, let newFrame = sample(at: now)?.frame {
            let newNext = sample(at: now + step)?.frame
            for (id, rect) in newFrame.cardFrames {
                guard id != "__footer__" else { continue }
                if let previous = oldFrame.cardFrames[id] {
                    let speed = ((oldNext?.cardFrames[id]?.minY ?? previous.minY) - previous.minY
                        - (newNext?.cardFrames[id]?.minY ?? rect.minY) + rect.minY) / step
                    moveOffsets[id] = NativePanelPhaseTrack(start: Double(previous.minY - rect.minY), target: 0,
                        velocity: Double(speed), time: now)
                }
            }
        }
        // 内容换页只改变自然尺寸，不重用上一次点击展开的滚动揭示目标。
        retargetScroll(at: now, reveal: false)
        commit(at: now, instantly: instantly || oldFrame == nil
            || (reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    }

    func retarget(_ targets: [String: CGFloat], instantly: Bool = false, scrollToTop: Bool = false) {
        let now = clock()
        var targets = targets
        var closed = Set<String>()
        func closeChildren(_ id: String) {
            guard closed.insert(id).inserted else { return }
            for child in registry.childrenByParent[id] ?? [] { targets[child] = 0; closeChildren(child) }
        }
        for (id, target) in targets where target == 0 { closeChildren(id) }
        let added = Set(targets.compactMap { id, value in value > 0 && (desired[id] ?? 0) == 0 ? id : nil })
        desired.merge(targets) { _, new in new }
        guard !isSuspended, let snapshot else { return }
        for (id, value) in targets where snapshot.sections[id]?.isAvailable == true {
            let current = tracks[id]?.sample(at: now) ?? (position: 0, velocity: 0)
            tracks[id] = NativePanelPhaseTrack(start: current.position, target: Double(value),
                velocity: current.velocity, time: now)
        }
        if scrollToTop {
            revealID = nil
        } else if let id = PanelScrollCoordinator.targetSectionForAutoReveal(addedIDs: added, visualOrder: snapshot.visualOrder) {
            revealID = id
        } else if let id = revealID, targets[id] == 0 { revealID = nil }
        retargetScroll(at: now, scrollToTop: scrollToTop)
        commit(at: now, instantly: instantly || isSuspended
            || (reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    }

    private func retargetScroll(at now: CFTimeInterval, reveal: Bool = true, scrollToTop: Bool = false) {
        guard let snapshot, !isUserScrolling else { return }
        let current = scroll.map { NativePanelSpring().sample(start: $0.start, target: $0.target,
            velocity: $0.velocity, elapsed: now - $0.time) } ?? (position: Double(scrollOffset), velocity: 0)
        let final = PanelGeometrySolver.solve(snapshot: snapshot, phases: desired, scrollOffset: CGFloat(current.position))
        let target: CGFloat
        if scrollToTop { target = 0 }
        else if reveal, revealID != nil { target = PanelScrollCoordinator.calculateScrollOffset(for: revealID, frame: final) }
        else { target = PanelScrollCoordinator.clampUserOffset(offset: CGFloat(current.position), frame: final) }
        scroll = NativePanelPhaseTrack(start: current.position, target: Double(target), velocity: current.velocity, time: now)
    }

    func sample(at now: CFTimeInterval) -> NativePanelMotionSample? {
        guard let snapshot else { return nil }
        let phases = tracks.mapValues { CGFloat($0.sample(at: now).position) }
        // 滚动偏移使用点数解析解，不能应用 0…1 相位边界。
        let offset: CGFloat
        if let scroll, !isUserScrolling {
            offset = CGFloat(NativePanelSpring().sample(start: scroll.start, target: scroll.target,
                velocity: scroll.velocity, elapsed: now - scroll.time).position)
        } else { offset = scrollOffset }
        var frame = PanelGeometrySolver.solve(snapshot: snapshot, phases: phases, sampleTime: now, scrollOffset: offset,
            revealAdjustments: revealCorrections.mapValues { CGFloat($0.pointSample(at: now).position) })
        for (id, track) in moveOffsets {
            let delta = CGFloat(track.pointSample(at: now).position)
            frame.cardFrames[id]?.origin.y += delta
            var descendants = [id]
            var visited = Set<String>()
            while let node = descendants.popLast(), visited.insert(node).inserted {
                frame.sectionFrames[node]?.origin.y += delta
                descendants.append(contentsOf: snapshot.childrenByParent[node] ?? [])
            }
        }
        return NativePanelMotionSample(frame: frame, phases: phases)
    }

    private func commit(at now: CFTimeInterval, instantly: Bool) {
        guard snapshot != nil else { return }
        let preparationStarted = CACurrentMediaTime()
        completion?.cancel(); completion = nil
        generation &+= 1
        let id = generation
        let duration = instantly ? 0 : MonitorConstants.panelNativeMotionDuration
        if instantly {
            for (key, track) in tracks { tracks[key] = NativePanelPhaseTrack(start: track.target, target: track.target, velocity: 0, time: now) }
            if let scroll { scrollOffset = CGFloat(scroll.target) }; scroll = nil
            moveOffsets.removeAll()
            revealCorrections.removeAll()
        }
        let count = max(1, Int(ceil(duration * MonitorConstants.panelNativeMotionSamplingRate)))
        let initial = (0...count).compactMap { sample(at: now + duration * Double($0) / Double(count)) }
        var samples: [NativePanelMotionSample] = []
        let tolerance = 1 / max(1, snapshot!.environment.backingScale)
        func error(_ a: PanelFrame, _ b: PanelFrame, _ middle: PanelFrame) -> CGFloat {
            var result = abs((a.windowContentSize.height + b.windowContentSize.height) / 2 - middle.windowContentSize.height)
            result = max(result, abs((a.viewportHeight + b.viewportHeight) / 2 - middle.viewportHeight),
                abs((a.scrollOffset + b.scrollOffset) / 2 - middle.scrollOffset))
            for (id, rect) in middle.cardFrames {
                guard let left = a.cardFrames[id], let right = b.cardFrames[id] else { continue }
                result = max(result, abs((left.minY + right.minY) / 2 - rect.minY),
                    abs((left.height + right.height) / 2 - rect.height))
            }
            for (id, rect) in middle.childFrames {
                guard let left = a.childFrames[id], let right = b.childFrames[id] else { continue }
                result = max(result, abs((left.minY + right.minY) / 2 - rect.minY),
                    abs((left.height + right.height) / 2 - rect.height))
            }
            return result
        }
        func subdivide(_ a: NativePanelMotionSample, _ b: NativePanelMotionSample, depth: Int) {
            if depth < 6, let middle = sample(at: (a.frame.sampleTime + b.frame.sampleTime) / 2),
               error(a.frame, b.frame, middle.frame) > tolerance * 0.5 {
                subdivide(a, middle, depth: depth + 1); subdivide(middle, b, depth: depth + 1)
            } else { samples.append(a) }
        }
        for index in 0..<max(0, initial.count - 1) { subdivide(initial[index], initial[index + 1], depth: 0) }
        if let last = initial.last { samples.append(last) }
        guard var final = samples.last else { return }
        final.phases = tracks.mapValues { CGFloat($0.target) }
        final.frame = PanelGeometrySolver.solve(snapshot: snapshot!, phases: final.phases,
            sampleTime: now + duration, scrollOffset: CGFloat(scroll?.target ?? Double(scrollOffset)))
        samples[samples.count - 1] = final
        let next = NativePanelAnimationPlan(startTime: now, duration: duration, samples: samples, generation: id)
        plan = next
        renderers = renderers.filter { $0.value.value != nil }
        for renderer in renderers.values { renderer.value?.applyNativePlan(next) }
        onCommit?(final.frame, final.phases)
        if NativePanelMotionMode.diagnostics {
            NSLog("[native-plan] generation=%lu revision=%lu duration=%.3f samples=%ld prepare-ms=%.3f nodes=%ld offset=%.1f height=%.1f",
                id, snapshot!.revision, duration, samples.count, (CACurrentMediaTime() - preparationStarted) * 1000,
                snapshot!.sections.count, final.frame.scrollOffset, final.frame.windowContentSize.height)
        }
        guard duration > 0, !isSuspended else { return }
        onStart?()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == id else { return }
            self.completion = nil
            for (key, track) in self.tracks {
                self.tracks[key] = NativePanelPhaseTrack(start: track.target, target: track.target, velocity: 0, time: now + duration)
            }
            if let scroll = self.scroll { self.scrollOffset = CGFloat(scroll.target) }
            self.scroll = nil; self.moveOffsets.removeAll(); self.revealCorrections.removeAll()
        }
        completion = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func userScrollBegan(at offset: CGFloat) {
        isUserScrolling = true; revealID = nil; scroll = nil; scrollOffset = offset
    }
    func updateUserScroll(_ offset: CGFloat) {
        guard let frame = sample(at: clock())?.frame else { return }
        scrollOffset = PanelScrollCoordinator.clampUserOffset(offset: offset, frame: frame)
    }
    func userScrollEnded(at offset: CGFloat) { updateUserScroll(offset); isUserScrolling = false }
    func suspend() {
        let now = clock()
        for (id, track) in tracks {
            let value = track.sample(at: now).position
            tracks[id] = NativePanelPhaseTrack(start: value, target: value, velocity: 0, time: now)
        }
        if let scroll { scrollOffset = CGFloat(scroll.pointSample(at: now).position) }
        self.scroll = nil
        isUserScrolling = false
        for (id, track) in revealCorrections {
            let value = track.pointSample(at: now).position
            revealCorrections[id] = NativePanelPhaseTrack(start: value, target: value, velocity: 0, time: now)
        }
        for (id, track) in moveOffsets {
            let value = track.pointSample(at: now).position
            moveOffsets[id] = NativePanelPhaseTrack(start: value, target: value, velocity: 0, time: now)
        }
        isSuspended = true; completion?.cancel(); completion = nil; generation &+= 1
        for renderer in renderers.values { renderer.value?.stopNativeMotion() }
        plan = nil
    }
    func panelDidShow() { for renderer in renderers.values { renderer.value?.nativePanelDidShow() } }
    func resume() {
        isSuspended = false
        // 隐藏期间只登记最新结构与逻辑状态，重新显示时一次提交最新端点。
        if measuredSnapshot != snapshot { geometryDidChange(instantly: true) }
        else { retarget(desired, instantly: true) }
    }
    func cancel() { revealID = nil; scroll = nil; retarget(desired, instantly: true) }
}
