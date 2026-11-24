import CoreGraphics
import Combine
import Foundation
import Testing
@testable import HagimiMonitorDirect

nonisolated enum ConnectionFixtures {
    static func screen(_ id: UInt32, builtin: Bool = false, online: Bool = true,
                       physical: Bool = true, visible: Bool = true) -> DisplayConnectionScreen {
        .init(id: id, identity: .init(uuid: "uuid-\(id)", vendor: 100, model: builtin ? 1 : 2, serial: id, isBuiltIn: builtin),
              name: "Screen \(id)", isPhysical: physical, isOnline: online, hasDesktop: online,
              isVisible: visible, mirrorTarget: nil, bounds: .init(x: 0, y: 0, width: 1920, height: 1080))
    }
    static func storage() -> (DisplayPersistence, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: "DisplayConnectionTests.\(UUID())")!
        return (DisplayPersistence(defaults: defaults, connectionJournalURL: dir.appendingPathComponent("state.json")), dir)
    }
}

struct DisplayConnectionPolicyTests {
    @Test func headerKeepsBrightnessForDisabledAndConnectedDevices() {
        let internalScreen = ConnectionFixtures.screen(900001, builtin: true, online: false)
        let externalScreen = ConnectionFixtures.screen(900002)
        let backend = ConnectionControlBackendFake(ConnectionBackendFake([internalScreen, externalScreen]))
        let live = backend.displays()
        var internalRecord = DisplayConnectionRecord(identity: internalScreen.identity, name: internalScreen.name)
        internalRecord.brightness = 37.5
        let entries = [
            DisplayConnectionEntry(record: internalRecord, screen: internalScreen, observation: .disabled),
            DisplayConnectionEntry(record: .init(identity: externalScreen.identity, name: externalScreen.name),
                screen: externalScreen, observation: .connected)
        ]
        #expect(live.count == 1)
        #expect(entries.map { $0.headerBrightness(in: live) } == [37.5, 50])
        var unknown = entries[0]
        unknown.observation = .absent
        #expect(unknown.headerBrightness(in: live) == nil)
        unknown.observation = .disabled; unknown.record.brightness = nil
        #expect(unknown.headerBrightness(in: live) == nil)
    }

    @Test func headerNeverReadsBrightnessFromAReusedNumericID() {
        let original = ConnectionFixtures.screen(900001)
        var replacement = original
        replacement.identity.uuid = "replacement"; replacement.identity.serial = 42
        let live = ConnectionControlBackendFake(ConnectionBackendFake([replacement])).displays()
        let entry = DisplayConnectionEntry(record: .init(identity: original.identity, name: original.name),
            screen: original, observation: .connected)
        #expect(entry.headerBrightness(in: live) == nil)
    }

    @Test func reusedIDCannotSelectAnotherDevice() {
        let original = ConnectionFixtures.screen(1)
        var replacement = ConnectionFixtures.screen(2)
        replacement.id = original.id
        #expect(DisplayConnectionPolicy.resolve(original.identity, in: [replacement]) == nil)
    }

    @Test func sameNameAndModelWithoutUniqueEvidenceAreRejected() {
        var first = ConnectionFixtures.screen(1), second = ConnectionFixtures.screen(2)
        first.identity.serial = 0; second.identity.serial = 0
        second.identity.uuid = first.identity.uuid
        second.name = first.name
        #expect(DisplayConnectionPolicy.resolve(first.identity, in: [first, second]) == nil)
        second.identity.uuid = nil
        #expect(!first.identity.matches(second.identity))
    }

    @Test func contradictorySerialAndUUIDAreRejected() {
        let first = ConnectionFixtures.screen(1)
        var second = first
        second.identity.serial = 50
        #expect(!first.identity.matches(second.identity))
        second = first; second.identity.uuid = "changed"
        #expect(!first.identity.matches(second.identity))
    }

    @Test func lastPhysicalProtectionIgnoresVirtualHiddenAndOfflineScreens() {
        let target = ConnectionFixtures.screen(1)
        for other in [ConnectionFixtures.screen(2, physical: false),
                      ConnectionFixtures.screen(2, builtin: true, visible: false),
                      ConnectionFixtures.screen(2, online: false)] {
            #expect(!DisplayConnectionPolicy.canDisable(target, in: [target, other]))
        }
        #expect(DisplayConnectionPolicy.canDisable(target, in: [target, ConnectionFixtures.screen(2, builtin: true)]))
    }

    @Test func offlineIsNotAutomaticallyAppDisabled() {
        let offline = ConnectionFixtures.screen(1, online: false)
        var record = DisplayConnectionRecord(identity: offline.identity, name: offline.name)
        #expect(DisplayConnectionPolicy.observation(record, in: [offline]) == .unknown)
        record.ownedDisabled = true
        #expect(DisplayConnectionPolicy.observation(record, in: [offline]) == .disabled)
        #expect(DisplayConnectionPolicy.observation(record, in: []) == .absent)
        var online = offline; online.isOnline = true; online.hasDesktop = true
        #expect(DisplayConnectionPolicy.observation(record, in: [online]) == .connected)
    }

    @Test func mirrorGroupAndExternalLayoutConflictAreExplicit() {
        let root = ConnectionFixtures.screen(1)
        var member = ConnectionFixtures.screen(2)
        member.mirrorTarget = root.id
        let group = DisplayConnectionPolicy.mirrorGroup(for: root, in: [root, member, ConnectionFixtures.screen(3)])
        #expect(group.count == 2)
        #expect(DisplayConnectionPolicy.mirrorsMatch(group, current: [root, member]))
        member.bounds.x = 400
        #expect(!DisplayConnectionPolicy.mirrorsMatch(group, current: [root, member]))
    }

    @Test func ownMainDisplayReanchorAllowsOnlyCommonTranslation() {
        var root = ConnectionFixtures.screen(1), member = ConnectionFixtures.screen(2)
        member.bounds.x = 1920
        let saved = DisplayConnectionPolicy.members([root, member], all: [root, member])
        root.bounds.x -= 1920; member.bounds.x -= 1920
        #expect(!DisplayConnectionPolicy.mirrorsMatch(saved, current: [root, member]))
        #expect(DisplayConnectionPolicy.mirrorsMatch(saved, current: [root, member], allowTranslation: true))
        member.bounds.y += 100
        #expect(!DisplayConnectionPolicy.mirrorsMatch(saved, current: [root, member], allowTranslation: true))
    }
}

struct DisplayConnectionPersistenceTests {
    @Test func roundtripKeepsPreferencesMirrorAndPauseWithoutRuntimeID() throws {
        let (p, directory) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = ConnectionFixtures.screen(1)
        var state = DisplayConnectionState()
        state.records = [DisplayConnectionRecord(identity: screen.identity, name: screen.name, wantsDisabled: true, ownedDisabled: true)]
        state.records[0].mirror = .init(original: [.init(identity: screen.identity, target: nil, bounds: screen.bounds)], expected: [])
        state.automaticPaused = true; state.operationPending = true
        try p.saveConnectionState(state)
        #expect(try p.loadConnectionState() == state)
        let text = try String(contentsOf: directory.appendingPathComponent("state.json"), encoding: .utf8)
        #expect(!text.contains("displayID"))
    }

    @Test func absentCorruptFutureAndUnwritableStores() throws {
        let (p, directory) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try p.loadConnectionState().records.isEmpty)
        var state = DisplayConnectionState(); state.schema = 2
        #expect(throws: DisplayConnectionIssue.self) { try p.saveConnectionState(state) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bad".utf8).write(to: directory.appendingPathComponent("state.json"))
        #expect(throws: (any Error).self) { try p.loadConnectionState() }
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let broken = DisplayPersistence(connectionJournalURL: blocker.appendingPathComponent("state.json"))
        #expect(throws: (any Error).self) { try broken.saveConnectionState(.init()) }
    }
}

struct DisplayConnectionBridgeTests {
    private func api() -> DisplayConnectionSystemAPI {
        .init(list: { _, _, count in count?.pointee = 0; return .success },
              enable: { _, _, _ in .success },
              begin: { ref in ref = unsafeBitCast(UInt(1), to: CGDisplayConfigRef.self); return .success },
              complete: { _ in .success }, cancel: { _ in .success }, mirror: { _, _, _ in .success })
    }

    @Test func enumerationGrowsBeyondSixteenAndBeginErrorsAreReported() throws {
        let ids = try DisplayConnectionBridge.enumerate { capacity, buffer, count in
            let n = min(capacity, 40)
            count?.pointee = n
            for i in 0..<Int(n) { buffer?[i] = UInt32(i + 1) }
            return .success
        }
        #expect(ids.count == 40)
        let first = ConnectionFixtures.screen(1), second = ConnectionFixtures.screen(2)
        var functions = api()
        functions.begin = { _ in .failure }
        let bridge = DisplayConnectionBridge(api: functions, snapshotProvider: { [first, second] })
        do {
            try bridge.configure([.enabled(first.identity, false)])
            Issue.record("Begin failure must be reported")
        } catch let error as DisplayConnectionAPIError {
            #expect(error.stage == "begin")
        }
    }

    @Test func missingSymbolsRefuseWritesWithoutTerminating() {
        let bridge = DisplayConnectionBridge(api: .init(list: nil, enable: nil))
        #expect(!bridge.isAvailable)
        #expect(throws: DisplayConnectionIssue.self) { try bridge.configure([]) }
    }

    @Test func noOpDoesNotBeginAndLastScreenCannotBeDisabled() throws {
        let only = ConnectionFixtures.screen(1)
        var functions = api()
        functions.begin = { _ in Issue.record("No-op must not create transaction"); return .failure }
        let bridge = DisplayConnectionBridge(api: functions, snapshotProvider: { [only] })
        try bridge.configure([.enabled(only.identity, true)])
        #expect(throws: DisplayConnectionIssue.self) { try bridge.configure([.enabled(only.identity, false)]) }
    }

    @Test func configureFailureCancelsButCompleteFailureIsNotClaimedRolledBack() {
        let first = ConnectionFixtures.screen(1), second = ConnectionFixtures.screen(2)
        var functions = api()
        functions.enable = { _, _, _ in .failure }
        functions.cancel = { _ in .success }
        let bridge = DisplayConnectionBridge(api: functions, snapshotProvider: { [first, second] })
        #expect(throws: DisplayConnectionAPIError.self) { try bridge.configure([.enabled(first.identity, false)]) }
        functions.enable = { _, _, _ in .success }
        functions.complete = { _ in .failure }
        functions.cancel = { _ in Issue.record("Cannot cancel an already submitted transaction"); return .success }
        let submitted = DisplayConnectionBridge(api: functions, snapshotProvider: { [first, second] })
        #expect(throws: DisplayConnectionAPIError.self) { try submitted.configure([.enabled(first.identity, false)]) }
    }

    @Test func rememberedDisplayIDIsEnabledEvenWhenMissingAndCompletionCodeIsIgnored() {
        let enabled = TestBox<[CGDirectDisplayID]>([])
        var functions = api()
        functions.enable = { _, id, value in
            if value { enabled.value = enabled.value + [id] }
            return .failure
        }
        functions.complete = { _ in .failure }
        let bridge = DisplayConnectionBridge(api: functions, snapshotProvider: { [] })
        bridge.forceEnableRemembered([1, 1])
        #expect(enabled.value == [1])
    }
}

struct DisplayConnectionRediscoveryTests {
    @Test func cancelledAndConcurrentCallersStillCompleteOnePairedWake() async throws {
        let started = TestBox(0), woke = TestBox(0)
        let release = AsyncStream<Void>.makeStream()
        let recovery = DisplayConnectionRediscovery(clock: { 100 }, sleepDisplays: {
            started.value += 1; return true
        }, settle: {
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }, wakeDisplays: { woke.value += 1; return true })
        let first = Task { await recovery.recover { true } }
        for _ in 0..<100 where started.value == 0 { try await Task.sleep(for: .milliseconds(2)) }
        try #require(started.value == 1)
        let second = Task { await recovery.recover { true } }
        first.cancel(); second.cancel()
        release.continuation.yield(())
        #expect(await first.value)
        _ = await second.value
        #expect(started.value == 1)
        #expect(woke.value == 1)
        #expect(await recovery.recover { true } == false)
        release.continuation.finish()
    }

    @Test func rejectedRecoveryDoesNotSleepDisplaysAndFailedSleepStillGetsWake() async {
        let slept = TestBox(0), woke = TestBox(0)
        let recovery = DisplayConnectionRediscovery(clock: { 100 }, sleepDisplays: {
            slept.value += 1; return false
        }, settle: {}, wakeDisplays: { woke.value += 1; return true })
        #expect(await recovery.recover { false } == false)
        #expect(slept.value == 0 && woke.value == 0)
        #expect(await recovery.recover { true })
        #expect(slept.value == 1 && woke.value == 1)
    }
}

/// 队列内的可控拓扑，测试从不访问实际显示配置。
private nonisolated final class ConnectionBackendFake: DisplayConnectionBackend, @unchecked Sendable {
    let isAvailable = true
    private let lock = NSLock()
    private var values: [DisplayConnectionScreen]
    private var ignore = false
    private var failingIDs: Set<UInt32> = []
    private var failingEnableIDs: Set<UInt32> = []
    private var writes = 0
    private var reads = 0
    private var enabledIDs: [UInt32] = []
    private var rediscoveredScreens: [DisplayConnectionScreen]?
    private var rediscoveries = 0
    private var forcedIDs: [UInt32] = []
    private var reviveOnForceEnable: [DisplayConnectionScreen]?
    init(_ values: [DisplayConnectionScreen]) { self.values = values }
    func screens() throws -> [DisplayConnectionScreen] { lock.withLock { reads += 1; return values } }
    var screenReadCount: Int { lock.withLock { reads } }
    var enableAttempts: [UInt32] { lock.withLock { enabledIDs } }
    var rediscoveryCount: Int { lock.withLock { rediscoveries } }
    var forcedEnableIDs: [UInt32] { lock.withLock { forcedIDs } }
    func setRediscoveredScreens(_ screens: [DisplayConnectionScreen]) { lock.withLock { rediscoveredScreens = screens } }
    func setReviveOnForceEnable(_ screens: [DisplayConnectionScreen]?) { lock.withLock { reviveOnForceEnable = screens } }
    func rediscoverPhysicalDisplays() async -> Bool {
        lock.withLock {
            rediscoveries += 1
            guard let rediscoveredScreens else { return false }
            values = rediscoveredScreens
            return true
        }
    }
    func forceEnableRemembered(_ ids: [CGDirectDisplayID]) {
        lock.withLock {
            forcedIDs.append(contentsOf: ids)
            if let reviveOnForceEnable { values = reviveOnForceEnable }
        }
    }
    func setIgnoring(_ value: Bool) { lock.withLock { ignore = value } }
    func setFailing(_ ids: Set<UInt32>) { lock.withLock { failingIDs = ids } }
    func setFailingEnable(_ ids: Set<UInt32>) { lock.withLock { failingEnableIDs = ids } }
    func update(_ transform: (inout [DisplayConnectionScreen]) -> Void) { lock.withLock { transform(&values) } }
    var count: Int { lock.withLock { writes } }
    func configure(_ commands: [DisplayConnectionCommand]) throws {
        try lock.withLock {
            for command in commands {
                writes += 1
                if ignore { continue }
                switch command {
                case let .enabled(identity, enabled):
                    guard let screen = DisplayConnectionPolicy.resolve(identity, in: values),
                          let index = values.firstIndex(where: { $0.id == screen.id }) else { throw DisplayConnectionIssue.ambiguous }
                    if enabled { enabledIDs.append(screen.id) }
                    if failingIDs.contains(screen.id) || failingEnableIDs.contains(screen.id) { throw DisplayConnectionIssue.failed }
                    values[index].isOnline = enabled; values[index].hasDesktop = enabled
                case let .mirror(identity, target):
                    guard let screen = DisplayConnectionPolicy.resolve(identity, in: values),
                          let index = values.firstIndex(where: { $0.id == screen.id }) else { throw DisplayConnectionIssue.ambiguous }
                    if failingIDs.contains(screen.id) { throw DisplayConnectionIssue.failed }
                    values[index].mirrorTarget = target.flatMap { DisplayConnectionPolicy.resolve($0, in: values)?.id }
                }
            }
        }
    }
}

struct DisplayConnectionCoordinatorTests {
    @Test func missingBuiltInRecoversThroughFreshTopologyWithoutWritingHistoricalID() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = ConnectionFixtures.screen(1, builtin: true)
        var state = DisplayConnectionState()
        state.records = [.init(identity: original.identity, name: original.name, ownedDisabled: true)]
        try p.saveConnectionState(state)
        let placeholder = ConnectionFixtures.screen(7, physical: false)
        let backend = ConnectionBackendFake([placeholder])
        var rediscovered = original
        rediscovered.id = 42; rediscovered.isOnline = false; rediscovered.hasDesktop = false
        backend.setRediscoveredScreens([rediscovered])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let result = await executor.boot()
        #expect(backend.rediscoveryCount == 1)
        #expect(backend.forcedEnableIDs.isEmpty)
        #expect(backend.enableAttempts == [42])
        #expect(result.entries.first?.observation == .connected)
        #expect(try p.loadConnectionState().records.first?.ownedDisabled == false)
    }

    @Test func vanishedBuiltInUsesSessionIDBeforeDisplayPowerCycle() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builtin = ConnectionFixtures.screen(1, builtin: true)
        let external = ConnectionFixtures.screen(2)
        let backend = ConnectionBackendFake([builtin, external])
        backend.setReviveOnForceEnable([builtin])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await executor.boot()
        let builtinID = try #require(boot.entries.first { $0.record.identity.isBuiltIn }?.id)
        _ = await executor.setEnabled(false, for: builtinID)
        backend.update { $0 = [ConnectionFixtures.screen(7, physical: false)] }
        _ = await executor.checkSafety(forceRestore: true)
        #expect(backend.forcedEnableIDs == [1])
        #expect(backend.rediscoveryCount == 0)
        #expect(try p.loadConnectionState().records.first { $0.identity.isBuiltIn }?.ownedDisabled == false)
    }

    @Test func failedSessionIDStillSleepsOnceThenEnablesTheRebuiltBuiltIn() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builtin = ConnectionFixtures.screen(1, builtin: true)
        let external = ConnectionFixtures.screen(2)
        let backend = ConnectionBackendFake([builtin, external])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await executor.boot()
        let builtinID = try #require(boot.entries.first { $0.record.identity.isBuiltIn }?.id)
        _ = await executor.setEnabled(false, for: builtinID)
        backend.update { $0 = [ConnectionFixtures.screen(7, physical: false)] }
        var rebuilt = builtin
        rebuilt.id = 42
        rebuilt.isOnline = false
        rebuilt.hasDesktop = false
        backend.setRediscoveredScreens([rebuilt])
        _ = await executor.checkSafety(forceRestore: true)
        #expect(backend.forcedEnableIDs == [1])
        #expect(backend.rediscoveryCount == 1)
        #expect(backend.enableAttempts == [42])
        #expect(try p.loadConnectionState().records.first { $0.identity.isBuiltIn }?.ownedDisabled == false)
    }

    @Test func sessionIDOccupiedByAnotherDisplayIsNotReused() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let builtin = ConnectionFixtures.screen(1, builtin: true)
        let external = ConnectionFixtures.screen(2)
        let backend = ConnectionBackendFake([builtin, external])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await executor.boot()
        let builtinID = try #require(boot.entries.first { $0.record.identity.isBuiltIn }?.id)
        _ = await executor.setEnabled(false, for: builtinID)
        backend.update { $0 = [ConnectionFixtures.screen(1, online: false)] }
        var rebuilt = builtin
        rebuilt.id = 42
        rebuilt.isOnline = false
        rebuilt.hasDesktop = false
        backend.setRediscoveredScreens([rebuilt])
        _ = await executor.checkSafety(forceRestore: true)
        #expect(backend.forcedEnableIDs.isEmpty)
        #expect(backend.rediscoveryCount == 1)
        #expect(backend.enableAttempts == [42])
    }

    @Test func failedRediscoveryDoesNotCycleContinuouslyOrInventAConnectedScreen() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = ConnectionFixtures.screen(1, builtin: true)
        var state = DisplayConnectionState()
        state.records = [.init(identity: original.identity, name: original.name, ownedDisabled: true)]
        try p.saveConnectionState(state)
        let placeholder = ConnectionFixtures.screen(7, physical: false)
        let backend = ConnectionBackendFake([placeholder])
        backend.setRediscoveredScreens([placeholder])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        _ = await executor.boot()
        for _ in 0..<3 { _ = await executor.checkSafety() }
        #expect(backend.rediscoveryCount == 1)
        #expect(backend.count == 0)
        #expect(try p.loadConnectionState().records.first?.ownedDisabled == true)
    }

    @Test func missingBuiltInDoesNotTriggerDisplayPowerCycleWhileSystemSleeps() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = ConnectionFixtures.screen(1, builtin: true)
        var state = DisplayConnectionState()
        state.records = [.init(identity: original.identity, name: original.name, ownedDisabled: true)]
        try p.saveConnectionState(state)
        let backend = ConnectionBackendFake([])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { true })
        _ = await executor.boot()
        #expect(backend.rediscoveryCount == 0)
    }

    @Test func recoveryPrioritizesVisibleBuiltInBeforeFailingExternalTarget() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let external = ConnectionFixtures.screen(2, online: false)
        let internalScreen = ConnectionFixtures.screen(1, builtin: true, online: false)
        var saved = DisplayConnectionState()
        saved.records = [external, internalScreen].map {
            .init(identity: $0.identity, name: $0.name, ownedDisabled: true)
        }
        try p.saveConnectionState(saved)
        let backend = ConnectionBackendFake([external, internalScreen])
        backend.setFailingEnable([2])
        let executor = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let result = await executor.boot()
        #expect(backend.enableAttempts.first == 1)
        #expect(result.entries.first { $0.screen?.id == 1 }?.observation == .connected)
    }

    @Test func startupDiscardsLegacyDisableMemoryWithoutChangingConnectedScreens() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = ConnectionFixtures.screen(1, builtin: true)
        var saved = DisplayConnectionState()
        saved.records = [.init(identity: first.identity, name: first.name, wantsDisabled: true)]
        try p.saveConnectionState(saved)
        let backend = ConnectionBackendFake([first, ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        #expect(await worker.boot().entries.allSatisfy { $0.observation == .connected })
        _ = await worker.refresh(recoverIfNeeded: true)
        #expect(backend.count == 0)
        #expect(try p.loadConnectionState().records.allSatisfy { !$0.wantsDisabled })
    }

    @Test func explicitEnableIntentCannotInvertWhenTheDisplayedStateIsStale() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = boot.entries[0].id
        _ = await worker.setEnabled(false, for: id)
        backend.update { $0[0].isOnline = true; $0[0].hasDesktop = true }
        let enabled = await worker.setEnabled(true, for: id)
        #expect(enabled.entries.first { $0.id == id }?.observation == .connected)
        #expect(backend.count == 1, "启用请求遇到已经在线的目标只能 no-op，不能反向停用")
        backend.update { $0[0].isOnline = false; $0[0].hasDesktop = false }
        _ = await worker.setEnabled(false, for: id)
        #expect(backend.count == 1)
    }

    @Test func failedDisableAfterUnmirrorRestoresOriginalRelationshipAndKeepsNoNewPreference() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = ConnectionFixtures.screen(1)
        var member = ConnectionFixtures.screen(2); member.mirrorTarget = 1
        let backend = ConnectionBackendFake([root, member])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = try #require(boot.entries.first { $0.screen?.id == 2 }?.id)
        backend.setFailingEnable([2])
        let failed = await worker.toggle(id)
        #expect(failed.entries.first { $0.id == id }?.observation == .connected)
        #expect(failed.entries.first { $0.id == id }?.issue == .failed)
        #expect(failed.entries.first { $0.id == id }?.record.wantsDisabled == false)
        #expect(try backend.screens().first { $0.id == 2 }?.mirrorTarget == 1)
        #expect(try p.loadConnectionState().records.first { $0.id == id }?.mirror == nil)
    }

    @Test func rescueFailureKeepsPreferenceAndRetriesOnlyOnAnotherEvent() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = boot.entries[0].id
        _ = await worker.toggle(id)
        backend.update { $0.removeAll { $0.id == 2 } }
        backend.setFailingEnable([1])
        let failed = await worker.refresh(recoverIfNeeded: true)
        #expect(failed.entries.first { $0.id == id }?.observation == .disabled)
        #expect(failed.entries.first { $0.id == id }?.issue == .failed)
        #expect(failed.entries.first { $0.id == id }?.record.wantsDisabled == false)
        let attempts = backend.count
        _ = await worker.refresh(recoverIfNeeded: false)
        #expect(backend.count == attempts)
        backend.setFailingEnable([])
        #expect(await worker.refresh(recoverIfNeeded: true).entries.first { $0.id == id }?.observation == .connected)
        #expect(try p.loadConnectionState().records.first { $0.id == id }?.wantsDisabled == false)
    }

    @Test @MainActor func terminationRejectsLaterEventsAndUserRequests() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let coordinator = DisplayConnectionCoordinator(executor: worker)
        coordinator.willChange = { _ in true }
        coordinator.start()
        for _ in 0..<100 where coordinator.isBusy { try await Task.sleep(for: .milliseconds(2)) }
        try #require(!coordinator.isBusy)
        let id = try #require(coordinator.entries.first?.id)
        #expect(await coordinator.prepareToQuit())
        coordinator.refresh(recoverIfNeeded: true)
        coordinator.toggle(id)
        coordinator.setEnabled(false, for: id)
        try await Task.sleep(for: .milliseconds(10))
        #expect(backend.count == 0)
        #expect(try p.loadConnectionState().runActive == false)
    }

    @Test func quitLeavesDisabledScreenAndMirrorUntouched() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = ConnectionFixtures.screen(1), unrelated = ConnectionFixtures.screen(4)
        var second = ConnectionFixtures.screen(2), third = ConnectionFixtures.screen(3)
        second.mirrorTarget = 1; third.mirrorTarget = 1
        let backend = ConnectionBackendFake([root, second, third, unrelated])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = try #require(boot.entries.first { $0.screen?.id == 2 }?.id)
        _ = await worker.toggle(id)
        #expect(try backend.screens().first { $0.id == 4 } == unrelated)
        let writes = backend.count
        let offline = try backend.screens().first { $0.id == 2 }?.isOnline
        #expect(await worker.prepareToQuit())
        #expect(backend.count == writes)
        #expect(try backend.screens().first { $0.id == 2 }?.isOnline == offline)
        let restarted = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        #expect(await restarted.boot().entries.first { $0.id == id }?.observation == .disabled)
        #expect(backend.count == writes)
    }

    @Test func missingMirrorMemberKeepsConnectionUsableAndRestoresAfterMemberReturns() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = ConnectionFixtures.screen(1)
        var member = ConnectionFixtures.screen(2); member.mirrorTarget = 1
        let backend = ConnectionBackendFake([root, member, ConnectionFixtures.screen(3)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = try #require(boot.entries.first { $0.screen?.id == 2 }?.id)
        _ = await worker.toggle(id)
        backend.update { $0.removeAll { $0.id == 1 } }
        let restored = await worker.toggle(id)
        #expect(restored.entries.first { $0.id == id }?.observation == .connected)
        #expect(restored.entries.first { $0.id == id }?.issue == .waiting)
        #expect(try p.loadConnectionState().records.first { $0.id == id }?.mirror != nil)
        backend.update { $0.append(root) }
        let mirroredAgain = await worker.refresh(recoverIfNeeded: true)
        #expect(try backend.screens().first { $0.id == 2 }?.mirrorTarget == 1)
        #expect(try p.loadConnectionState().records.first { $0.id == id }?.mirror == nil)
        #expect(mirroredAgain.entries.first { $0.id == id }?.issue == nil)
    }

    @Test func actualSystemSleepDefersRescueUntilWakeWithoutDisablingAgain() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sleeping = TestBox(false)
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { sleeping.value })
        let boot = await worker.boot()
        _ = await worker.toggle(boot.entries[0].id)
        #expect(backend.count == 1)
        sleeping.value = true
        backend.update { $0.removeAll { $0.id == 2 } }
        _ = await worker.refresh(recoverIfNeeded: true)
        #expect(backend.count == 1)
        sleeping.value = false
        let rescued = await worker.refresh(recoverIfNeeded: true)
        #expect(rescued.entries.first?.observation == .connected)
        #expect(rescued.entries.first?.record.wantsDisabled == false)
        _ = await worker.refresh(recoverIfNeeded: true)
        #expect(backend.count == 2)
    }

    @Test func failedQuitKeepsRecoveryJournalAndNextBootOnlyRecovers() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, observationAttempts: 2, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        _ = await worker.toggle(boot.entries[0].id)
        let writes = backend.count
        backend.setIgnoring(true)
        #expect(await worker.prepareToQuit())
        #expect(try p.loadConnectionState().runActive == false)
        #expect(backend.count == writes)
        backend.setIgnoring(false)
        let restarted = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let again = await restarted.boot()
        #expect(again.entries.first { $0.screen?.id == 1 }?.observation == .disabled)
        #expect(backend.count == writes)
    }

    @Test func normalExitKeepsDisabledScreenOffAcrossRestart() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1, builtin: true), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let id = try #require(boot.entries.first { !$0.record.identity.isBuiltIn }?.id)
        let disabled = await worker.toggle(id)
        #expect(disabled.entries.first { $0.id == id }?.observation == .disabled)
        #expect(try p.loadConnectionState().records.first { $0.id == id }?.wantsDisabled == false)
        let writes = backend.count
        #expect(await worker.prepareToQuit())
        #expect(try backend.screens().first { $0.id == 2 }?.isOnline == false)
        #expect(backend.count == writes)
        let restarted = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let again = await restarted.boot()
        #expect(again.entries.first { $0.id == id }?.observation == .disabled)
        #expect(backend.count == writes)
    }

    @Test func interruptedRunRecoversAndDiscardsLegacyDisablePreferences() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = ConnectionFixtures.screen(2, online: false)
        var state = DisplayConnectionState()
        state.records = [.init(identity: target.identity, name: target.name, wantsDisabled: true, ownedDisabled: true)]
        state.runActive = true; state.operationPending = true; state.automaticPaused = true
        try p.saveConnectionState(state)
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), target])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let result = await worker.boot()
        #expect(result.entries.first { $0.record.identity == target.identity }?.observation == .disabled)
        #expect(try p.loadConnectionState().records.allSatisfy { !$0.wantsDisabled && $0.ownedDisabled })
        #expect(backend.count == 0)
        #expect(await worker.prepareToQuit())
        let next = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        #expect(await next.boot().entries.first { $0.record.identity == target.identity }?.observation == .disabled)
        #expect(backend.count == 0)
    }

    @Test func successfulReturnWithoutObservedChangeIsNotSuccess() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, observationAttempts: 2, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        backend.setIgnoring(true)
        let id = try #require(boot.entries.first?.id)
        let result = await worker.toggle(id)
        #expect(result.entries.first { $0.id == id }?.issue == .unconfirmed)
        #expect(result.entries.first { $0.id == id }?.record.wantsDisabled == false)
        #expect(backend.count == 1)
    }

    @Test func mirrorRestoresAndExternalChangesWin() async throws {
        for conflict in [false, true] {
            let (p, dir) = ConnectionFixtures.storage()
            defer { try? FileManager.default.removeItem(at: dir) }
            let root = ConnectionFixtures.screen(1)
            var member = ConnectionFixtures.screen(2); member.mirrorTarget = root.id
            let backend = ConnectionBackendFake([root, member])
            let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
            let boot = await worker.boot()
            let id = try #require(boot.entries.first { $0.screen?.id == member.id }?.id)
            _ = await worker.toggle(id)
            if conflict { backend.update { $0[0].bounds.x = 500 } }
            let result = await worker.toggle(id)
            let actual = try backend.screens().first { $0.id == member.id }
            #expect(actual?.mirrorTarget == (conflict ? nil : root.id))
            #expect(result.entries.first { $0.id == id }?.issue == (conflict ? .mirrorConflict : nil))
        }
    }

    @Test func lastScreenChoiceIsRejectedAndSurvivorLossTriggersRecovery() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        let first = boot.entries[0].id, second = boot.entries[1].id
        _ = await worker.toggle(first)
        let denied = await worker.toggle(second)
        #expect(denied.entries.first { $0.id == second }?.issue == .lastScreen)
        #expect(denied.entries.first { $0.id == second }?.record.wantsDisabled == false)
        backend.update { $0.removeAll { $0.id == 2 } }
        let rescued = await worker.refresh(recoverIfNeeded: true)
        #expect(rescued.entries.first { $0.id == first }?.observation == .connected)
        #expect(rescued.entries.first { $0.id == first }?.record.wantsDisabled == false)
    }

    @Test func delayedObservationSettlesWithoutRepeatedWrites() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        backend.setIgnoring(true)
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, observationAttempts: 3,
            sleep: { backend.update { $0[0].isOnline.toggle(); $0[0].hasDesktop.toggle() } }, systemSleeping: { false })
        let boot = await worker.boot()
        let id = boot.entries[0].id
        #expect(await worker.toggle(id).entries.first { $0.id == id }?.observation == .disabled)
        #expect(await worker.toggle(id).entries.first { $0.id == id }?.observation == .connected)
        #expect(backend.count == 2)
    }

    @Test func externalReconnectionIsNeverAutomaticallyDisabledAgain() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = ConnectionBackendFake([ConnectionFixtures.screen(1), ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        let boot = await worker.boot()
        _ = await worker.toggle(boot.entries[0].id)
        _ = await worker.refresh(recoverIfNeeded: true)
        #expect(backend.count == 1)
        for _ in 0..<3 {
            backend.update { $0[0].isOnline = true; $0[0].hasDesktop = true }
            let result = await worker.refresh(recoverIfNeeded: true)
            #expect(result.entries.first { $0.screen?.id == 1 }?.observation == .connected)
        }
        #expect(backend.count == 1)
    }

    @Test func savedArchiveCannotMoveToAReusedDisplayID() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = ConnectionFixtures.screen(1)
        let backend = ConnectionBackendFake([original, ConnectionFixtures.screen(2)])
        let worker = DisplayConnectionExecutor(backend: backend, persistence: p, sleep: {}, systemSleeping: { false })
        _ = await worker.boot()
        let info = DisplayInfo(id: 1, name: original.name, isBuiltIn: false, resolution: "1920×1080", refreshRate: "60 Hz",
            hdrSupported: nil, hdrActive: nil, colorDepth: "--", sizeInches: nil, ppi: nil, hidpiScale: nil,
            adaptiveSync: nil, gamut: nil, manufacturer: nil, model: nil, serial: nil, manufactureDate: nil)
        let cached = await worker.cache([info], identities: [1: original.identity])
        #expect(cached.entries.first { $0.screen?.id == 1 }?.record.archive?.info == info)
        backend.update { $0[0].identity.uuid = "replacement"; $0[0].identity.serial = 500 }
        let replaced = await worker.cache([info], identities: [1: original.identity])
        #expect(replaced.entries.first { $0.screen?.id == 1 }?.record.archive == nil)
    }
}

private nonisolated final class ConnectionControlBackendFake: DisplayControlBackend, @unchecked Sendable {
    let topology: ConnectionBackendFake
    private let lock = NSLock()
    private var nextRead: (@Sendable () -> Void)?
    private var nextWrite: (@Sendable () -> Void)?
    private var written: [(UInt32, Double)] = []
    private var invalidated = 0
    private var detected = 0
    init(_ topology: ConnectionBackendFake) { self.topology = topology }
    func blockNextRead(_ action: @escaping @Sendable () -> Void) { lock.withLock { nextRead = action } }
    func blockNextWrite(_ action: @escaping @Sendable () -> Void) { lock.withLock { nextWrite = action } }
    var writes: [(UInt32, Double)] { lock.withLock { written } }
    var invalidations: Int { lock.withLock { invalidated } }
    var readCount: Int { lock.withLock { detected } }
    func displays() -> [ControlledDisplay] {
        lock.withLock { detected += 1 }
        let online = (try? topology.screens())?.filter { $0.isOnline && $0.hasDesktop } ?? []
        let action = lock.withLock { let result = nextRead; nextRead = nil; return result }
        action?()
        return online.map { screen in
            ControlledDisplay(id: screen.id, kind: screen.identity.isBuiltIn ? .builtIn : .appleNative,
                dimmingMode: .hardware, storageID: screen.name, name: screen.name,
                isBuiltIn: screen.identity.isBuiltIn, supportsBrightness: true, supportsVolume: false, supportsContrast: false,
                brightnessIsReadable: true, volumeIsReadable: false, contrastIsReadable: false,
                brightnessValueKnown: true, volumeValueKnown: false, contrastValueKnown: false,
                brightness: 50, volume: 0, contrast: 0, connectionIdentity: screen.identity)
        }
    }
    func setValue(_ value: Double, for control: DisplayControlKind, display: ControlledDisplay) -> DisplayWriteOutcome {
        let action = lock.withLock {
            written.append((display.id, value))
            let result = nextWrite; nextWrite = nil; return result
        }
        action?()
        return .written
    }
    func makeEngineTransport() -> any DDCTransport { FakeDDCTransport() }
    func engineConnections(for displays: [ControlledDisplay]) -> [DisplayConnection] { [] }
    func invalidateConnectionTokens() { lock.withLock { invalidated += 1 } }
}

@Suite(.serialized)
@MainActor
struct DisplayConnectionControllerIntegrationTests {
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<300 where !predicate() { try await Task.sleep(for: .milliseconds(2)) }
        try #require(predicate())
    }

    @Test func ownDisableNotificationDoesNotUndoTheManualAction() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let executor = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let connections = DisplayConnectionCoordinator(executor: executor)
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        connections.setEnabled(false, for: id)
        connections.topologyChanged(displayID: 900001, flags: .removeFlag)
        try await waitUntil { !connections.isBusy && controller.displays.count == 1 }
        connections.topologyChanged(displayID: 900001, flags: .removeFlag)
        let before = topology.screenReadCount
        try await waitUntil { topology.screenReadCount > before }
        #expect(connections.entries.first { $0.id == id }?.observation == .disabled)
        #expect(topology.count == 1)
        #expect(await connections.prepareToQuit())
    }

    @Test(arguments: [true, false])
    func survivorRemovalRecoversEvenWhileDisplaySleepKeepsDDCSuppressed(dropFromList: Bool) async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let executor = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let connections = DisplayConnectionCoordinator(executor: executor)
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        let gate = DDCEnvironmentGate(registerSystemObservers: false)
        let token = gate.addTopologyHandler { displayID, flags in
            Task { @MainActor in connections.topologyChanged(displayID: displayID, flags: flags) }
        }
        defer { gate.removeTopologyHandler(token) }
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        connections.setEnabled(false, for: id)
        try await waitUntil { !connections.isBusy && controller.displays.count == 1 }
        if dropFromList { topology.update { $0.removeAll { $0.id == 900002 } } }
        gate.handleDisplayWillSleep()
        gate.handleReconfigure(displayID: 900002, flags: .removeFlag)
        try await waitUntil { !connections.isBusy && connections.entries.first { $0.id == id }?.observation == .connected }
        #expect(gate.isSuppressed, "DDC 仍受抑制时，连接救援也必须完成")
        #expect(try topology.screens().first { $0.id == 900001 }?.isUsable == true)
        _ = await executor.refresh(recoverIfNeeded: true)
        #expect(try topology.screens().first { $0.id == 900001 }?.isUsable == true)
        #expect(await connections.prepareToQuit())
    }

    @Test func watchdogRecoversWithoutNotificationAndDoesNotPollParameterBackend() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let executor = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let ticks = AsyncStream<Void>.makeStream()
        defer { ticks.continuation.finish() }
        let connections = DisplayConnectionCoordinator(executor: executor, safetyDelay: {
            for await _ in ticks.stream { return }
        })
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        connections.setEnabled(false, for: id)
        try await waitUntil { !connections.isBusy && controller.displays.count == 1 }
        let reads = backend.readCount, topologyReads = topology.screenReadCount
        ticks.continuation.yield(())
        try await waitUntil { topology.screenReadCount > topologyReads }
        #expect(backend.readCount == reads)
        topology.update { $0.removeAll { $0.id == 900002 } }
        ticks.continuation.yield(())
        try await waitUntil { !connections.isBusy && connections.entries.first { $0.id == id }?.observation == .connected }
        #expect(await connections.prepareToQuit())
    }

    @Test func urgentRecoveryBypassesBlockedParameterIOAndInvalidatesItsQueuedInput() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let executor = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let connections = DisplayConnectionCoordinator(executor: executor)
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        connections.setEnabled(false, for: id)
        try await waitUntil { !connections.isBusy && controller.displays.count == 1 }
        let entered = TestBox(false), release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        backend.blockNextRead { entered.value = true; release.wait() }
        controller.refreshAsync()
        try await waitUntil { entered.value }
        controller.setValueAsync(80, for: .brightness, displayID: 900002)
        topology.update { $0.removeAll { $0.id == 900002 } }
        connections.topologyChanged(displayID: 900002, flags: .removeFlag)
        try await waitUntil { !connections.isBusy && connections.entries.first { $0.id == id }?.observation == .connected }
        #expect(try topology.screens().first { $0.id == 900001 }?.isUsable == true)
        release.signal()
        try await waitUntil { controller.displays.map(\.id) == [900001] }
        try await Task.sleep(for: .milliseconds(180))
        #expect(backend.writes.isEmpty)
        #expect(await connections.prepareToQuit())
    }

    @Test func staleRefreshCannotPublishOnlineDeviceAfterNewerRequest() async throws {
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let controller = DisplayControlController(backend: backend, observeChanges: false)
        let entered = TestBox(false), release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        backend.blockNextRead { entered.value = true; release.wait() }
        var publishedOld = false
        let subscription = controller.$displays.sink { if $0.count == 2 { publishedOld = true } }
        defer { subscription.cancel() }
        controller.refreshAsync()
        try await waitUntil { entered.value }
        topology.update { $0[0].isOnline = false; $0[0].hasDesktop = false }
        controller.refreshAsync()
        release.signal()
        try await waitUntil { controller.displays.map(\.id) == [900002] }
        #expect(!publishedOld)
    }

    @Test func topologyChangeClearsQueuedInputRejectsOfflineInputAndDoesNotReplayAfterRestore() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let worker = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let connections = DisplayConnectionCoordinator(executor: worker)
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        var firstEntryUpdates = 0, secondEntryUpdates = 0
        let firstEntry = controller.objectWillChange.sink { firstEntryUpdates += 1 }
        let secondEntry = controller.objectWillChange.sink { secondEntryUpdates += 1 }
        defer { firstEntry.cancel(); secondEntry.cancel() }
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        controller.setValueAsync(70, for: .brightness, displayID: 900001)
        #expect(controller.optionalValue(for: .brightness, displayID: 900001) == 70)
        connections.toggle(id)
        try await waitUntil { !connections.isBusy && controller.displays.map(\.id) == [900002] }
        #expect(connections.entries.first { $0.id == id }?.observation == .disabled)
        controller.setValueAsync(90, for: .brightness, displayID: 900001)
        connections.toggle(id)
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        try await Task.sleep(for: .milliseconds(180))
        #expect(backend.writes.isEmpty)
        #expect(backend.invalidations >= 3)
        controller.setValueAsync(35, for: .brightness, displayID: 900002)
        try await waitUntil { backend.writes.count == 1 }
        #expect(backend.writes.first?.0 == 900002)
        #expect(backend.writes.first?.1 == 35)
        controller.setValueAsync(45, for: .brightness, displayID: 900001)
        try await waitUntil { backend.writes.count == 2 }
        #expect(backend.writes.last?.0 == 900001)
        #expect(backend.writes.last?.1 == 45)
        #expect(firstEntryUpdates > 0 && firstEntryUpdates == secondEntryUpdates)
        #expect(topology.count == 2, "多个观察入口共用一次停用和一次启用")
        #expect(await connections.prepareToQuit())
    }

    @Test func topologyChangeWaitsForStartedWriteAndDiscardsItsLateCallback() async throws {
        let (p, dir) = ConnectionFixtures.storage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let topology = ConnectionBackendFake([ConnectionFixtures.screen(900001, builtin: true), ConnectionFixtures.screen(900002)])
        let backend = ConnectionControlBackendFake(topology)
        let worker = DisplayConnectionExecutor(backend: topology, persistence: p, sleep: {}, systemSleeping: { false })
        let connections = DisplayConnectionCoordinator(executor: worker)
        let controller = DisplayControlController(connections: connections, backend: backend, observeChanges: false)
        connections.start()
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        let id = try #require(connections.entries.first { $0.screen?.id == 900001 }?.id)
        let entered = TestBox(false), release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        backend.blockNextWrite { entered.value = true; release.wait() }
        controller.setValueAsync(70, for: .brightness, displayID: 900001)
        try await waitUntil { entered.value }
        let oldInvalidations = backend.invalidations
        connections.toggle(id)
        try await waitUntil { backend.invalidations > oldInvalidations }
        #expect(topology.count == 0, "已开始的参数 I/O 未返回时不得提交停用")
        release.signal()
        try await waitUntil { !connections.isBusy && controller.displays.count == 1 }
        connections.toggle(id)
        try await waitUntil { !connections.isBusy && controller.displays.count == 2 }
        #expect(controller.optionalValue(for: .brightness, displayID: 900001) == 50)
        #expect(backend.writes.count == 1)
        #expect(await connections.prepareToQuit())
    }
}

@MainActor
struct DisplayConnectionTerminationTests {
    @Test(arguments: [true, false])
    func finishedRecoveryRepliesOnceAndRejectsRepeatedTermination(success: Bool) async throws {
        let termination = DisplayConnectionTermination()
        let deadline = AsyncStream<Void>.makeStream()
        var recoveries = 0, replies = 0
        termination.begin(restore: { recoveries += 1; return success },
            wait: { for await _ in deadline.stream { return } }, reply: { replies += 1 })
        termination.begin(restore: { recoveries += 1; return false }, reply: { replies += 1 })
        for _ in 0..<100 where !termination.hasReplied { try await Task.sleep(for: .milliseconds(2)) }
        #expect(termination.hasReplied)
        #expect(recoveries == 1)
        #expect(replies == 1)
        deadline.continuation.yield(())
        await Task.yield()
        #expect(replies == 1)
        deadline.continuation.finish()
    }

    @Test func deadlineRepliesWithoutWaitingForBlockedRecoveryAndLateReturnCannotReplyAgain() async throws {
        let termination = DisplayConnectionTermination()
        let deadline = AsyncStream<Void>.makeStream()
        let recovery = TestBox<CheckedContinuation<Bool, Never>?>(nil)
        var replies = 0
        termination.begin(restore: { await withCheckedContinuation { recovery.value = $0 } },
            wait: { for await _ in deadline.stream { return } }, reply: { replies += 1 })
        for _ in 0..<100 where recovery.value == nil { try await Task.sleep(for: .milliseconds(2)) }
        let continuation = try #require(recovery.value)
        #expect(!termination.hasReplied)
        deadline.continuation.yield(())
        for _ in 0..<100 where !termination.hasReplied { try await Task.sleep(for: .milliseconds(2)) }
        #expect(termination.hasReplied)
        #expect(replies == 1)
        continuation.resume(returning: false)
        await Task.yield()
        #expect(replies == 1)
        deadline.continuation.finish()
    }
}

struct DisplayConnectionNativeProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HAGIMI_CONNECTION_NATIVE_PROBE"] == "1"))
    func cyclePhysicalDisplaysWithGuaranteedRestoreAttempt() async throws {
        let bridge = DisplayConnectionBridge()
        let initial = try bridge.screens()
        #expect(initial.filter(\.isUsable).count >= 2)
        guard initial.filter(\.isUsable).count >= 2 else { return }
        for target in initial.filter(\.isUsable) {
            guard DisplayConnectionPolicy.mirrorGroup(for: target, in: initial).isEmpty else { continue }
            defer { try? bridge.configure([.enabled(target.identity, true)]) }
            try bridge.configure([.enabled(target.identity, false)])
            try await Task.sleep(for: .milliseconds(700))
            let disconnected = try bridge.screens()
            let offline = DisplayConnectionPolicy.resolve(target.identity, in: disconnected)
            print("NATIVE DISABLED", target.name, "builtin", target.identity.isBuiltIn, "screen", String(describing: offline))
            #expect(offline?.isOnline == false)
            #expect(disconnected.contains { $0.isUsable })
            try bridge.configure([.enabled(target.identity, true)])
            for _ in 0..<30 {
                if try DisplayConnectionPolicy.resolve(target.identity, in: bridge.screens())?.isOnline == true { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            let connected = try DisplayConnectionPolicy.resolve(target.identity, in: bridge.screens())
            print("NATIVE RESTORED", target.name, String(describing: connected))
            #expect(connected?.isUsable == true)
        }
    }
}

struct DisplayConnectionNativeMirrorProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HAGIMI_CONNECTION_NATIVE_PROBE"] == "1"))
    func cycleMirrorMasterAndMemberAndRestoreOriginalLayout() async throws {
        let bridge = DisplayConnectionBridge()
        let original = try bridge.screens().filter(\.isUsable)
        guard original.count == 2 else { return }
        let modes = original.compactMap { screen in CGDisplayCopyDisplayMode(screen.id).map { (screen.id, $0) } }
        defer {
            for screen in original { try? bridge.configure([.enabled(screen.identity, true)]) }
            try? bridge.configure(original.map { screen in
                .mirror(screen.identity, screen.mirrorTarget.flatMap { id in original.first { $0.id == id }?.identity })
            })
            var ref: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&ref) == .success, let ref {
                for (id, mode) in modes { _ = CGConfigureDisplayWithDisplayMode(ref, id, mode, nil) }
                for screen in original {
                    _ = CGConfigureDisplayOrigin(ref, screen.id, Int32(screen.bounds.x), Int32(screen.bounds.y))
                }
                _ = CGCompleteDisplayConfiguration(ref, .forSession)
            }
        }
        let root = original[0], member = original[1]
        for identity in [root.identity, member.identity] {
            try bridge.configure([.mirror(member.identity, root.identity)])
            try await Task.sleep(for: .milliseconds(600))
            let mirrored = try bridge.screens()
            #expect(DisplayConnectionPolicy.resolve(member.identity, in: mirrored)?.mirrorTarget == root.id)
            let (p, dir) = ConnectionFixtures.storage()
            defer { try? FileManager.default.removeItem(at: dir) }
            let worker = DisplayConnectionExecutor(backend: bridge, persistence: p, systemSleeping: { false })
            let boot = await worker.boot()
            let id = try #require(boot.entries.first { $0.record.identity == identity }?.id)
            let off = await worker.toggle(id)
            print("NATIVE MIRROR OFF", identity.isBuiltIn, String(describing: off.entries.first { $0.id == id }))
            #expect(off.entries.first { $0.id == id }?.observation == .disabled)
            let on = await worker.toggle(id)
            print("NATIVE MIRROR ON", identity.isBuiltIn, String(describing: on.entries.first { $0.id == id }))
            #expect(on.entries.first { $0.id == id }?.issue == nil)
            let after = try bridge.screens()
            #expect(DisplayConnectionPolicy.resolve(member.identity, in: after)?.mirrorTarget == root.id)
            #expect(await worker.prepareToQuit())
            try bridge.configure([.mirror(member.identity, nil)])
        }
    }
}
