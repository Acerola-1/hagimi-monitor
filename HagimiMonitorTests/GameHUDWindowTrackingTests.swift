import AppKit
import SwiftUI
import Combine
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct GameHUDWindowTrackingTests {
    private func info(pid: Int = 42, onScreen: Bool = true) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: 7,
         kCGWindowLayer as String: 0, kCGWindowAlpha as String: CGFloat(1),
         kCGWindowIsOnscreen as String: onScreen,
         kCGWindowBounds as String: ["X": CGFloat(-300), "Y": CGFloat(80),
                                    "Width": CGFloat(900), "Height": CGFloat(600)]]
    }

    @Test func candidateRequiresOwnerVisibilityAndCompleteFiniteBounds() {
        #expect(GameHUDWindowLocator.candidate(from: info(), ownedBy: 42)?.windowID == 7)
        #expect(GameHUDWindowLocator.candidate(from: info(pid: 43), ownedBy: 42) == nil)
        #expect(GameHUDWindowLocator.candidate(from: info(onScreen: false), ownedBy: 42) == nil)
        for key in [kCGWindowAlpha, kCGWindowBounds, kCGWindowIsOnscreen] {
            var missing = info()
            missing.removeValue(forKey: key as String)
            #expect(GameHUDWindowLocator.candidate(from: missing, ownedBy: 42) == nil)
        }
        for bounds in [["X": CGFloat.nan, "Y": 0, "Width": 900, "Height": 600],
                       ["X": 0, "Y": 0, "Width": 0, "Height": 600],
                       ["Y": 0, "Width": 900, "Height": 600]] {
            var bad = info()
            bad[kCGWindowBounds as String] = bounds
            #expect(GameHUDWindowLocator.candidate(from: bad, ownedBy: 42) == nil)
        }
    }

    @Test func visibleRegionFlipsCoordinatesAndSelectsLargestScreenIntersection() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 900),
                       CGRect(x: -1000, y: -200, width: 1000, height: 900)]
        let result = GameHUDWindowLocator.visibleRegion(
            cgFrame: CGRect(x: -700, y: 300, width: 900, height: 600), primaryMaxY: 900,
            screens: screens, minimumSize: CGSize(width: 260, height: 200))
        #expect(result?.screenIndex == 1)
        #expect(result?.rect == CGRect(x: -700, y: 0, width: 700, height: 600))
        #expect(GameHUDWindowLocator.visibleRegion(
            cgFrame: CGRect(x: 990, y: 0, width: 900, height: 600), primaryMaxY: 900,
            screens: screens, minimumSize: CGSize(width: 260, height: 200)) == nil)
    }

    @Test func trackedLookupUsesOnlyKnownIDAndRejectsReusedIdentity() throws {
        let identity = GameHUDWindowIdentity(processIdentifier: 42, windowID: 7)
        var calls: [(CGWindowListOption, CGWindowID)] = []
        var record = info()
        let locator = GameHUDWindowLocator(windowInfo: { options, id in
            calls.append((options, id))
            return [record]
        })
        _ = locator.resolveTrackedWindow(identity, minimumSize: .zero)
        #expect(calls.count == 1)
        #expect(calls[0].0 == .optionIncludingWindow)
        #expect(calls[0].1 == 7)
        record[kCGWindowOwnerPID as String] = 99
        #expect(locator.resolveTrackedWindow(identity, minimumSize: .zero) == .unavailable)
        record = info()
        record[kCGWindowNumber as String] = 8
        #expect(locator.resolveTrackedWindow(identity, minimumSize: .zero) == .unavailable)
    }

    /// 保留取消过的回调，以模拟停止或换目标后已入队的定时器事件。
    private final class Clock {
        var time: TimeInterval = 0
        var pressed = false
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        func schedule(_ interval: TimeInterval, _ callback: @escaping @MainActor () -> Void) -> Timer {
            scheduled.append((interval, callback))
            return Timer(timeInterval: interval, repeats: false) { _ in }
        }
        func fire() {
            let item = scheduled.removeFirst()
            time += item.0
            item.1()
        }
    }

    @Test func cadenceDoesNotAccumulateQueryAndPresentationTimeOrReplayExpiredTicks() throws {
        let screen = try #require(NSScreen.screens.first)
        let clock = Clock()
        var workDuration: TimeInterval = 0.009
        var queryStarts: [TimeInterval] = []
        let tracker = GameHUDWindowTracker(readTarget: { identity in
            queryStarts.append(clock.time)
            clock.time += workDuration
            return .target(windowID: identity.windowID, rect: screen.frame, screen: screen)
        }, isPermitted: { _ in true }, mousePressed: { true }, now: { clock.time }, schedule: clock.schedule)
        tracker.start(identity: .init(processIdentifier: 42, windowID: 7),
                      initialTarget: .target(windowID: 7, rect: screen.frame, screen: screen))
        for _ in 0..<5 { clock.fire() }
        for (a, b) in zip(queryStarts, queryStarts.dropFirst()) {
            #expect(abs((b - a) - GameHUDWindowTracker.movingInterval) < 0.000001)
        }
        workDuration = 0.04
        clock.fire()
        let next = try #require(clock.scheduled.first?.0)
        #expect(next > 0)
        #expect(next <= GameHUDWindowTracker.movingInterval)
        #expect(clock.scheduled.count == 1)
        tracker.stop()
    }

    @Test func stoppedAndReplacedTimersCannotQueryOldWindow() throws {
        let screen = try #require(NSScreen.screens.first)
        let clock = Clock()
        let rect = CGRect(x: 0, y: 0, width: 900, height: 600)
        var queries: [CGWindowID] = []
        let tracker = GameHUDWindowTracker(
            readTarget: { identity in
                queries.append(identity.windowID)
                return .target(windowID: identity.windowID, rect: rect, screen: screen)
            }, isPermitted: { _ in true }, now: { clock.time }, schedule: clock.schedule)
        tracker.start(identity: .init(processIdentifier: 42, windowID: 7),
                      initialTarget: .target(windowID: 7, rect: rect, screen: screen))
        tracker.start(identity: .init(processIdentifier: 43, windowID: 8),
                      initialTarget: .target(windowID: 8, rect: rect, screen: screen))
        clock.fire()
        #expect(queries.isEmpty)
        clock.fire()
        #expect(queries == [8])
        tracker.stop()
        clock.fire()
        #expect(queries == [8])
    }

    @Test func permissionLossStopsBeforeQueryAndUnavailableStopsAfterQuery() throws {
        let screen = try #require(NSScreen.screens.first)
        for permitted in [false, true] {
            let clock = Clock()
            var queries = 0
            var invalidations = 0
            let tracker = GameHUDWindowTracker(readTarget: { _ in queries += 1; return .unavailable },
                                               isPermitted: { _ in permitted }, schedule: clock.schedule)
            tracker.onChange = { target, _ in if target == .unavailable { invalidations += 1 } }
            tracker.start(identity: .init(processIdentifier: 42, windowID: 7),
                          initialTarget: .target(windowID: 7, rect: screen.frame, screen: screen))
            clock.fire()
            #expect(queries == (permitted ? 1 : 0))
            #expect(invalidations == 1)
            #expect(tracker.identity == nil)
            #expect(clock.scheduled.isEmpty)
        }
    }

    private func withSettings(_ body: (MonitorSettings) throws -> Void) throws {
        let suite = "GameHUDWindowTrackingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(MonitorSettings(defaults: defaults))
    }

    private final class MotionFixture {
        let screen: NSScreen
        let clock = Clock()
        var rect = CGRect(x: 100, y: 100, width: 900, height: 600)
        var sourceFrame: CGRect?
        var events: [Bool] = []
        init(screen: NSScreen) { self.screen = screen }
        lazy var tracker: GameHUDWindowTracker = {
            let tracker = GameHUDWindowTracker(readTarget: { [weak self] identity in
                guard let self else { return .unavailable }
                return .target(windowID: identity.windowID, rect: self.rect, screen: self.screen, sourceFrame: self.sourceFrame)
            }, isPermitted: { _ in true }, mousePressed: { [weak self] in self?.clock.pressed ?? false },
               now: { [weak self] in self?.clock.time ?? 0 }, schedule: clock.schedule)
            tracker.onChange = { [weak self] _, moving in self?.events.append(moving) }
            return tracker
        }()
        func start() {
            tracker.start(identity: .init(processIdentifier: 42, windowID: 7),
                          initialTarget: .target(windowID: 7, rect: rect, screen: screen, sourceFrame: sourceFrame))
        }
        func advance(_ duration: TimeInterval) {
            let end = clock.time + duration
            while clock.time < end { clock.fire() }
        }
    }

    @Test func ordinaryClicksDoNotHideAndHoldingStillDuringDragDoesNotRestore() throws {
        let f = MotionFixture(screen: try #require(NSScreen.screens.first))
        f.start()
        defer { f.tracker.stop() }
        f.clock.pressed = true
        f.advance(0.5)
        #expect(f.events.isEmpty)
        #expect(!f.tracker.isMoving)
        f.rect.origin.x += 60
        f.clock.fire()
        #expect(f.events == [true])
        f.advance(1)
        #expect(f.events == [true])
        f.clock.pressed = false
        f.clock.fire()
        #expect(f.events == [true, false])
    }

    @Test func releaseWaitsForStableGeometryAndNewMotionExtendsTheWait() throws {
        let f = MotionFixture(screen: try #require(NSScreen.screens.first))
        f.start()
        defer { f.tracker.stop() }
        f.clock.pressed = true
        f.rect.origin.x += 60
        f.clock.fire()
        f.clock.pressed = false
        f.advance(0.09)
        #expect(f.tracker.isMoving)
        f.rect.size.width -= 100
        f.clock.fire()
        f.advance(0.09)
        #expect(f.tracker.isMoving)
        f.advance(0.12)
        #expect(!f.tracker.isMoving)
        #expect(f.events.last == false)
    }

    @Test func programmaticMoveAndClippedRawBoundsAreDetected() throws {
        let f = MotionFixture(screen: try #require(NSScreen.screens.first))
        f.sourceFrame = CGRect(x: -2000, y: -2000, width: 5000, height: 5000)
        f.start()
        defer { f.tracker.stop() }
        // 裁剪后的可见矩形不变，原始窗口确实发生了位移。
        f.sourceFrame?.origin.x -= 20
        f.clock.fire()
        #expect(f.events == [true])
        f.advance(0.25)
        #expect(f.events == [true, false])
    }

    @Test func newlyDiscoveredTargetWaitsForReleaseWithoutHidingOrdinaryClicks() throws {
        let f = MotionFixture(screen: try #require(NSScreen.screens.first))
        f.clock.pressed = true
        f.start()
        defer { f.tracker.stop() }
        #expect(f.events == [true])
        f.advance(0.5)
        #expect(f.tracker.isMoving)
        f.clock.pressed = false
        f.clock.fire()
        #expect(f.events == [true, false])
    }

    @Test func locatorPreservesRawBoundsWhenVisibleClippingIsUnchanged() throws {
        let screen = try #require(NSScreen.screens.first)
        var record = info()
        record[kCGWindowBounds as String] = ["X": CGFloat(-3000), "Y": CGFloat(-3000),
                                            "Width": CGFloat(10000), "Height": CGFloat(10000)]
        let locator = GameHUDWindowLocator(windowInfo: { _, _ in [record] })
        let identity = GameHUDWindowIdentity(processIdentifier: 42, windowID: 7)
        let first = locator.resolveTrackedWindow(identity, minimumSize: .zero)
        record[kCGWindowBounds as String] = ["X": CGFloat(-3100), "Y": CGFloat(-3000),
                                            "Width": CGFloat(10000), "Height": CGFloat(10000)]
        let second = locator.resolveTrackedWindow(identity, minimumSize: .zero)
        guard case .target(_, let a, _, let rawA) = first,
              case .target(_, let b, _, let rawB) = second else {
            Issue.record("真实屏幕应与超大窗口相交：\(screen.frame)")
            return
        }
        #expect(a == b)
        #expect(rawA != rawB)
        #expect(first != second)
    }

    private final class SnapshotSource: GameHUDSnapshotProviding {
        let subject = PassthroughSubject<GameHUDSnapshot, Never>()
        var currentReads = 0
        var subscriptions = 0
        var cancellations = 0
        func currentSnapshot(enabledIDs: Set<GameHUDMetricID>) -> GameHUDSnapshot {
            currentReads += 1
            return .empty
        }
        var snapshotPublisher: AnyPublisher<GameHUDSnapshot, Never> {
            subject.handleEvents(receiveSubscription: { [weak self] _ in self?.subscriptions += 1 },
                                 receiveCancel: { [weak self] in self?.cancellations += 1 }).eraseToAnyPublisher()
        }
    }

    private final class FrameMeter: GameHUDFrameMeasuring {
        let subject = CurrentValueSubject<GameHUDFPSStats?, Never>(nil)
        var stats: GameHUDFPSStats? { subject.value }
        var statsPublisher: AnyPublisher<GameHUDFPSStats?, Never> { subject.eraseToAnyPublisher() }
        private var pid: pid_t?
        var starts = 0
        var stops = 0
        func start(target app: NSRunningApplication) {
            guard pid != app.processIdentifier else { return }
            pid = app.processIdentifier
            starts += 1
        }
        func stop() {
            if pid != nil { stops += 1 }
            pid = nil
        }
    }

    @Test func coordinatorSuppressesAllQueuedPresentationWhileMovingAndRetainsSession() throws {
        let app = NSRunningApplication.current
        let bundleID = try #require(app.bundleIdentifier)
        try withSettings { settings in
            settings.addGameHUDManualApp(bundleID: bundleID, name: "Test", applicationPath: nil)
            for id in settings.gameHUDEnabledMetricIDs where id != .cpuUsage {
                settings.setGameHUDMetric(id, enabled: false)
            }
            settings.gameHUDPresentationStyle = .card
            settings.gameHUDSidePreference = .topRight
            let clock = Clock()
            var record = info(pid: Int(app.processIdentifier))
            let session = GameHUDSessionController(settings: settings,
                windowLocator: GameHUDWindowLocator(windowInfo: { _, _ in [record] }),
                frontmostApplication: { app }, trackerScheduler: clock.schedule,
                trackingMousePressed: { clock.pressed }, trackingNow: { clock.time })
            let panel = GameHUDPanelController(settings: settings)
            let source = SnapshotSource()
            let meter = FrameMeter()
            let coordinator = GameHUDCoordinator(settings: settings, dataSource: source,
                                                  sessionController: session, panelController: panel, frameMeter: meter)
            // 使用注入的身份/数据源，不运行第三方应用偏好清理。
            session.onGameLaunched = nil
            defer { settings.gameHUDMasterEnabled = false; session.poll() }
            settings.gameHUDMasterEnabled = true
            session.poll()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            #expect(panel.isVisible)
            let host = try #require(panel.contentHostIdentity)
            let originalFrame = panel.frame
            let revision = panel.contentRevision
            clock.pressed = true
            var bounds = try #require(record[kCGWindowBounds as String] as? [String: CGFloat])
            bounds["X"] = (bounds["X"] ?? 0) + 50
            record[kCGWindowBounds as String] = bounds
            // 每秒发现先捕获移动，也必须通过状态机隐藏。
            session.poll()
            #expect(session.isMotionHidden)
            #expect(session.isTargetPermitted)
            #expect(!session.isPresentationPermitted)
            #expect(!panel.isVisible)
            #expect(!coordinator.isShowing)
            #expect(panel.frame == originalFrame)
            source.subject.send(GameHUDSnapshot(readings: [GameHUDReading(metricID: "cpu-usage", kind: .cpu,
                                                                           value: "42%", percent: 42)], date: Date()))
            meter.subject.send(GameHUDFPSStats(currentFPS: 60, averageFPS: 59, onePercentLow: 50))
            settings.gameHUDPresentationStyle = .topStrip
            settings.gameHUDSidePreference = .bottomRight
            settings.setGameHUDBackgroundTransparency(0.5, for: .topStrip)
            settings.addGameHUDManualApp(bundleID: "com.example.other", name: "Other", applicationPath: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            session.poll()
            for _ in 0..<12 { clock.fire() }
            #expect(!panel.isVisible)
            #expect(panel.contentRevision == revision)
            #expect(panel.contentHostIdentity == host)
            #expect(source.currentReads == 1)
            #expect(source.subscriptions == 1)
            #expect(source.cancellations == 0)
            #expect(meter.starts == 1)
            #expect(meter.stops == 0)
            clock.pressed = false
            clock.fire()
            #expect(!session.isMotionHidden)
            #expect(panel.isVisible)
            #expect(coordinator.isShowing)
            #expect(panel.contentRevision == revision + 1)
            #expect(panel.contentHostIdentity == host)
            #expect(source.currentReads == 1)
            #expect(meter.starts == 1)
        }
    }

    @Test func sessionStopsForFocusMasterExclusionAndClosedWindow() throws {
        let app = NSRunningApplication.current
        let bundleID = try #require(app.bundleIdentifier)
        for reason in ["focus", "master", "exclude", "closed"] {
            try withSettings { settings in
                settings.addGameHUDManualApp(bundleID: bundleID, name: "Test", applicationPath: nil)
                let clock = Clock()
                var frontmost: NSRunningApplication? = app
                var record = info(pid: Int(app.processIdentifier))
                var trackedQueries = 0
                let locator = GameHUDWindowLocator(windowInfo: { options, _ in
                    if options == .optionIncludingWindow { trackedQueries += 1 }
                    return [record]
                })
                let session = GameHUDSessionController(settings: settings, windowLocator: locator,
                                                       frontmostApplication: { frontmost }, trackerScheduler: clock.schedule, trackingMousePressed: { clock.pressed }, trackingNow: { clock.time })
                settings.gameHUDMasterEnabled = true
                session.poll()
                #expect(session.isTargetPermitted)
                var bounds = try #require(record[kCGWindowBounds as String] as? [String: CGFloat])
                bounds["X"] = (bounds["X"] ?? 0) + 10
                record[kCGWindowBounds as String] = bounds
                session.poll()
                #expect(session.isMotionHidden)
                switch reason {
                case "focus": frontmost = nil
                case "master": settings.gameHUDMasterEnabled = false
                case "exclude": settings.excludeGameHUDGame(bundleID: bundleID, name: "Test", applicationPath: nil)
                default: record[kCGWindowIsOnscreen as String] = false
                }
                clock.fire()
                #expect(!session.isTargetPermitted)
                #expect(session.targetRect == nil)
                #expect(session.targetIdentity == nil)
                #expect(!session.isMotionHidden)
                #expect(clock.scheduled.isEmpty)
                #expect(trackedQueries == (reason == "closed" ? 1 : 0))
                // 模拟后续采样/测帧回调复核资格；不能再次显示旧目标。
                #expect(!session.isTargetPermitted)
            }
        }
    }

    @Test func sessionPublishesCommittedGeometryWithoutFullSessionRefresh() throws {
        let app = NSRunningApplication.current
        let bundleID = try #require(app.bundleIdentifier)
        try withSettings { settings in
            settings.addGameHUDManualApp(bundleID: bundleID, name: "Test", applicationPath: nil)
            let clock = Clock()
            var record = info(pid: Int(app.processIdentifier))
            let locator = GameHUDWindowLocator(windowInfo: { _, _ in [record] })
            let session = GameHUDSessionController(settings: settings, windowLocator: locator,
                                                   frontmostApplication: { app }, trackerScheduler: clock.schedule, trackingMousePressed: { clock.pressed }, trackingNow: { clock.time })
            settings.gameHUDMasterEnabled = true
            session.poll()
            let oldRect = try #require(session.targetRect)
            var fullUpdates = 0
            var geometryUpdates = 0
            session.onSessionUpdated = { fullUpdates += 1 }
            session.onGeometryChanged = {
                geometryUpdates += 1
                #expect(session.targetRect?.minX == oldRect.minX + 60)
                #expect(session.targetScreen != nil)
            }
            var bounds = try #require(record[kCGWindowBounds as String] as? [String: CGFloat])
            bounds["X"] = oldRect.minX + 60
            record[kCGWindowBounds as String] = bounds
            clock.fire()
            #expect(geometryUpdates == 1)
            #expect(fullUpdates == 0)
            record[kCGWindowNumber as String] = 8
            session.poll()
            #expect(session.targetIdentity?.windowID == 8)
            let stale = clock.scheduled.removeFirst()
            stale.1()
            #expect(geometryUpdates == 1)
            #expect(session.targetIdentity?.windowID == 8)
            session.suspendTrackingForUnavailableLayout()
            session.onGeometryChanged = nil
        }
    }

    @Test func panelMovesBothStylesWithoutContentSubmissionAndHandlesFallback() throws {
        let screen = try #require(NSScreen.screens.first)
        try withSettings { settings in
            settings.gameHUDSidePreference = .topRight
            let controller = GameHUDPanelController(settings: settings)
            defer { controller.hide() }
            let content = GameHUDContent(
                cardView: AnyView(Text("Card").frame(width: 240, height: 120)),
                topStripView: AnyView(Text("Strip").frame(width: 600, height: 30)))
            let window = CGRect(x: screen.frame.minX + 50, y: screen.frame.minY + 50, width: 1000, height: 700)
            for style in [GameHUDPresentationStyle.card, .topStrip] {
                settings.gameHUDPresentationStyle = style
                controller.show(in: window, screen: screen, reserveTop: false, content: content)
                let first = try #require(controller.frame)
                let revision = controller.contentRevision
                let moved = window.offsetBy(dx: 60, dy: -30)
                #expect(!controller.updateFrame(in: moved, screen: screen, reserveTop: false))
                #expect(controller.frame == first.offsetBy(dx: 60, dy: -30))
                #expect(controller.contentRevision == revision)
            }
            let narrow = CGRect(x: window.minX, y: window.minY, width: 500, height: 600)
            #expect(controller.updateFrame(in: narrow, screen: screen, reserveTop: false))
            controller.show(in: narrow, screen: screen, reserveTop: false, content: content)
            let revision = controller.contentRevision
            #expect(!controller.updateFrame(in: narrow.offsetBy(dx: 20, dy: 0), screen: screen, reserveTop: false))
            #expect(controller.contentRevision == revision)
            #expect(controller.updateFrame(in: window, screen: screen, reserveTop: false))
            controller.show(in: window, screen: screen, reserveTop: false, content: content)
            #expect(controller.isVisible)
            #expect(controller.updateFrame(in: CGRect(x: 0, y: 0, width: 100, height: 50),
                                           screen: screen, reserveTop: false))
            controller.show(in: CGRect(x: 0, y: 0, width: 100, height: 50), screen: screen, reserveTop: false, content: content)
            #expect(!controller.isVisible)
        }
    }
}
