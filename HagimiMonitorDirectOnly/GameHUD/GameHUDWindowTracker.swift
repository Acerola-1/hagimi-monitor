import AppKit

/// 检测真实边界变化，移动期只通知隐藏，停稳后通知恢复；不呈现追赶位置。
@MainActor
final class GameHUDWindowTracker {
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Timer
    static let movingInterval: TimeInterval = 1.0 / 30
    static let idleInterval: TimeInterval = 1.0 / 20
    static let settlingDuration: TimeInterval = 0.18

    private let readTarget: (GameHUDWindowIdentity) -> GameHUDWindowTarget
    private let isPermitted: (GameHUDWindowIdentity) -> Bool
    private let mousePressed: () -> Bool
    private let now: () -> TimeInterval
    private let schedule: Scheduler
    private var timer: Timer?
    private(set) var identity: GameHUDWindowIdentity?
    private(set) var isMoving = false
    private var lastTarget: GameHUDWindowTarget = .unavailable
    private var lastMovementAt: TimeInterval = 0
    private var generation = 0
    private var timerGeneration = 0
    var onChange: ((GameHUDWindowTarget, Bool) -> Void)?

    init(readTarget: @escaping (GameHUDWindowIdentity) -> GameHUDWindowTarget,
         isPermitted: @escaping (GameHUDWindowIdentity) -> Bool,
         mousePressed: @escaping () -> Bool = { CGEventSource.buttonState(.combinedSessionState, button: .left) },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Scheduler = GameHUDWindowTracker.scheduleTimer) {
        self.readTarget = readTarget
        self.isPermitted = isPermitted
        self.mousePressed = mousePressed
        self.now = now
        self.schedule = schedule
    }

    isolated deinit { timer?.invalidate() }

    static func scheduleTimer(after interval: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func start(identity: GameHUDWindowIdentity, initialTarget: GameHUDWindowTarget) {
        guard self.identity != identity else { return }
        stop()
        self.identity = identity
        lastTarget = initialTarget
        lastMovementAt = now()
        // 首次发现可能发生在缩放途中；已有稳定 HUD 的普通点击不走此路径。
        isMoving = mousePressed()
        let expectedGeneration = generation
        if isMoving { onChange?(initialTarget, true) }
        guard self.identity == identity, generation == expectedGeneration else { return }
        scheduleNext(at: now() + (isMoving ? Self.movingInterval : Self.idleInterval))
    }

    func stop() {
        generation += 1
        timerGeneration += 1
        timer?.invalidate()
        timer = nil
        identity = nil
        lastTarget = .unavailable
        isMoving = false
        lastMovementAt = 0
    }

    /// 每秒完整发现的同 ID 结果也进入同一状态机，不能绕过移动隐藏。
    func observe(_ target: GameHUDWindowTarget) {
        guard let identity, isPermitted(identity) else { return }
        accept(target, identity: identity)
    }

    private func accept(_ target: GameHUDWindowTarget, identity: GameHUDWindowIdentity) {
        guard case .target(let windowID, _, _, _) = target, windowID == identity.windowID else {
            stop()
            onChange?(.unavailable, false)
            return
        }
        let time = now()
        let changed = target != lastTarget
        let wasMoving = isMoving
        if changed {
            lastMovementAt = time
            isMoving = true
        }
        if isMoving, !mousePressed(), time - lastMovementAt >= Self.settlingDuration {
            isMoving = false
        }
        lastTarget = target
        if changed || wasMoving != isMoving {
            onChange?(target, isMoving)
        }
    }

    private func scheduleNext(at deadline: TimeInterval) {
        timerGeneration += 1
        let expectedGeneration = generation
        let expectedTimer = timerGeneration
        let interval = max(0.001, deadline - now())
        timer = schedule(interval) { [weak self] in
            guard let self, self.generation == expectedGeneration, self.timerGeneration == expectedTimer,
                  let identity = self.identity else { return }
            guard self.isPermitted(identity) else {
                self.stop()
                self.onChange?(.unavailable, false)
                return
            }
            let target = self.readTarget(identity)
            self.accept(target, identity: identity)
            guard self.identity == identity, self.generation == expectedGeneration else { return }
            let cadence = self.isMoving || self.mousePressed() ? Self.movingInterval : Self.idleInterval
            var next = deadline + cadence
            let completedAt = self.now()
            if next <= completedAt {
                next += (floor((completedAt - next) / cadence) + 1) * cadence
            }
            self.scheduleNext(at: next)
        }
    }
}
