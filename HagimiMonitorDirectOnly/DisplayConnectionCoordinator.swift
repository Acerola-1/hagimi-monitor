import Combine
import CoreGraphics
import Foundation
import OSLog

nonisolated struct DisplayConnectionSnapshot: Sendable {
    var entries: [DisplayConnectionEntry]
    var issue: DisplayConnectionIssue?
}

/// 系统配置与日志都由同一个 actor 独占；等待状态时允许取消，但不并发提交事务。
actor DisplayConnectionExecutor {
    private let backend: any DisplayConnectionBackend
    private let persistence: DisplayPersistence
    private let sleep: @Sendable () async throws -> Void
    private let systemSleeping: @Sendable () -> Bool
    private let observationAttempts: Int
    private var state = DisplayConnectionState()
    private var issues: [UUID: DisplayConnectionIssue] = [:]
    private var topology: [DisplayConnectionScreen] = []
    private var generation = 0
    private var storageHealthy = true
    private var started = false
    private var quitting = false
    private var configurationAttempts = 0
    private var rediscoveryAttempted = false
    /// 只活在本次进程：停用后内置屏可能从枚举消失，但本会话见过的编号仍可能点得亮。
    private var sessionDisplayIDs: [(DisplayConnectionIdentity, CGDirectDisplayID)] = []
    private var globalIssue: DisplayConnectionIssue?

    init(backend: any DisplayConnectionBackend = DisplayConnectionBridge(), persistence: DisplayPersistence = .shared,
         observationAttempts: Int = 20,
         sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) },
         systemSleeping: @escaping @Sendable () -> Bool = {
             DDCEnvironmentGate.shared.isSystemSleeping || DDCEnvironmentGate.shared.isShuttingDown
         }) {
        self.backend = backend; self.persistence = persistence
        self.observationAttempts = observationAttempts; self.sleep = sleep; self.systemSleeping = systemSleeping
    }

    func boot() async -> DisplayConnectionSnapshot {
        guard !started else { return await refresh(recoverIfNeeded: false) }
        started = true
        do { state = try persistence.loadConnectionState() }
        catch { storageHealthy = false; state.automaticPaused = true; globalIssue = .storage }
        // wantsDisabled 在启动时清空。各屏开关保持现状；没有可用物理屏时才救援已停用的内置屏。
        for i in state.records.indices { state.records[i].wantsDisabled = false }
        state.operationPending = false
        state.runActive = true
        if storageHealthy { state.automaticPaused = false; globalIssue = nil }
        save(); readTopology()
        if !systemSleeping(), backend.isAvailable, !topology.contains(where: \.isUsable),
           state.records.contains(where: { $0.ownedDisabled && $0.identity.isBuiltIn }) {
            await restore(clearPreferences: true, ownedOnly: true)
        }
        return snapshot()
    }

    func refresh(recoverIfNeeded: Bool) async -> DisplayConnectionSnapshot {
        readTopology()
        if recoverIfNeeded && started && !quitting { await reconcile() }
        return snapshot()
    }

    func toggle(_ recordID: UUID) async -> DisplayConnectionSnapshot {
        generation += 1
        readTopology()
        guard let record = state.records.first(where: { $0.id == recordID }) else { return snapshot() }
        let connected = DisplayConnectionPolicy.observation(record, in: topology) == .connected
        if !connected { rediscoveryAttempted = false }
        await set(recordID, enabled: !connected, changePreference: true, request: generation)
        return snapshot()
    }

    func setEnabled(_ enabled: Bool, for recordID: UUID) async -> DisplayConnectionSnapshot {
        generation += 1
        if enabled { rediscoveryAttempted = false }
        await set(recordID, enabled: enabled, changePreference: true, request: generation)
        return snapshot()
    }

    func safetyProbe() -> (DisplayConnectionSnapshot, Bool) {
        readTopology()
        let needsRecovery = started && !quitting && !systemSleeping() && backend.isAvailable
            && state.records.contains(where: \.ownedDisabled) && !topology.contains(where: \.isUsable)
        return (snapshot(), needsRecovery)
    }

    func checkSafety(forceRestore: Bool = false) async -> (DisplayConnectionSnapshot, Bool) {
        readTopology()
        DisplayConnectionDiagnostics.trace("safety force=\(forceRestore) sleeping=\(systemSleeping()) owned=\(state.records.filter(\.ownedDisabled).map(\.identity))")
        let before = configurationAttempts
        if started, !quitting, !systemSleeping(), backend.isAvailable,
           forceRestore || !topology.contains(where: \.isUsable) {
            await restore(clearPreferences: true, ownedOnly: true)
        }
        return (snapshot(), configurationAttempts != before)
    }

    func prepareToQuit() async -> Bool {
        generation += 1
        quitting = true
        // 退出时停止救援，各屏开关保持现状。
        state.operationPending = false
        state.automaticPaused = false
        state.runActive = false
        save()
        return storageHealthy
    }

    func invalidate() { generation += 1 }

    func cache(_ information: [DisplayInfo], identities: [CGDirectDisplayID: DisplayConnectionIdentity]) -> DisplayConnectionSnapshot {
        guard started else { return snapshot() }
        readTopology()
        for info in information {
            guard let screen = topology.first(where: { $0.id == info.id }),
                  identities[info.id]?.matches(screen.identity) == true,
                  let index = state.records.firstIndex(where: {
                      DisplayConnectionPolicy.resolve($0.identity, in: topology)?.id == screen.id
                  }), screen.isOnline else { continue }
            // 只存内容发生变化的快照，普通面板刷新不反复写盘。
            if state.records[index].archive?.info != info {
                state.records[index].archive = .init(info: info, capturedAt: Date())
                save()
            }
        }
        return snapshot()
    }

    func cacheControls(_ displays: [ControlledDisplay]) {
        guard started else { return }
        for display in displays {
            guard let screen = topology.first(where: { $0.id == display.id }),
                  let identity = display.connectionIdentity, identity.matches(screen.identity),
                  let i = state.records.firstIndex(where: { $0.identity.matches(screen.identity) }) else { continue }
            state.records[i].brightness = display.knownValue(for: .brightness)
            state.records[i].volume = display.knownValue(for: .volume)
            state.records[i].contrast = display.knownValue(for: .contrast)
        }
        save()
    }

    private func readTopology() {
        do {
            topology = try backend.screens()
            if topology.contains(where: \.isUsable) { rediscoveryAttempted = false }
            for screen in topology where screen.isPhysical {
                sessionDisplayIDs.removeAll { $0.0.matches(screen.identity) }
                sessionDisplayIDs.append((screen.identity, screen.id))
                let matching = state.records.indices.filter { state.records[$0].identity.matches(screen.identity) }
                if matching.count == 1,
                   DisplayConnectionPolicy.resolve(state.records[matching[0]].identity, in: topology) != nil {
                    if screen.isOnline { state.records[matching[0]].name = screen.name }
                    if screen.isOnline, screen.hasDesktop, !state.operationPending, state.records[matching[0]].ownedDisabled {
                        state.records[matching[0]].ownedDisabled = false
                        state.records[matching[0]].wantsDisabled = false
                        issues[state.records[matching[0]].id] = nil
                        save()
                    }
                } else if matching.isEmpty,
                          DisplayConnectionPolicy.resolve(screen.identity, in: topology)?.id == screen.id {
                    // 新出现且能唯一对应的物理屏补进记录，之后可以单独启用。
                    state.records.append(.init(identity: screen.identity, name: screen.name))
                }
            }
            if globalIssue == .unavailable, backend.isAvailable { globalIssue = nil }
        } catch {
            topology = []
            globalIssue = backend.isAvailable ? .unconfirmed : .unavailable
        }
    }

    private func save() {
        guard storageHealthy else { return }
        do { try persistence.saveConnectionState(state) }
        catch { storageHealthy = false; globalIssue = .storage; state.automaticPaused = true }
    }

    private func snapshot() -> DisplayConnectionSnapshot {
        .init(entries: state.records.filter { record in
            record.ownedDisabled || record.wantsDisabled || record.mirror != nil
                || topology.contains { record.identity.matches($0.identity) }
        }.map { record in
            let screen = DisplayConnectionPolicy.resolve(record.identity, in: topology)
            return DisplayConnectionEntry(record: record, screen: screen,
                observation: DisplayConnectionPolicy.observation(record, in: topology),
                issue: issues[record.id],
                canDisable: backend.isAvailable && storageHealthy && screen.map { DisplayConnectionPolicy.canDisable($0, in: topology) } == true)
        }, issue: backend.isAvailable ? globalIssue : .unavailable)
    }

    private func reconcile() async {
        guard !systemSleeping(), backend.isAvailable else { return }
        if !topology.contains(where: \.isUsable) {
            await restore(clearPreferences: true, ownedOnly: true)
            readTopology()
            return
        }
        // 连接变化时处理镜像还原和救援，不按历史偏好关闭屏幕。
        for index in state.records.indices where state.records[index].mirror != nil && !state.records[index].ownedDisabled {
            do { try restoreMirror(index); save() }
            catch { issues[state.records[index].id] = (error as? DisplayConnectionIssue) ?? .failed }
        }
    }

    private func restore(clearPreferences: Bool, ownedOnly: Bool) async {
        if clearPreferences {
            for i in state.records.indices { state.records[i].wantsDisabled = false }
            state.automaticPaused = false
            globalIssue = storageHealthy ? nil : .storage
            save()
        }
        readTopology()
        let request = generation
        if !topology.contains(where: \.isUsable) {
            await recoverMissingOwnedDisplays(request: request)
        }
        let ids = state.records.filter { !ownedOnly || $0.ownedDisabled || $0.mirror != nil }
            .sorted { restorationPriority($0) < restorationPriority($1) }.map(\.id)
        for id in ids {
            guard !Task.isCancelled, request == generation else { return }
            await set(id, enabled: true, changePreference: clearPreferences, request: request, allowEmergency: false)
        }
    }

    /// 内置屏从私有列表消失时，先用本会话编号抢在句柄失效前点亮；仍无可用屏才做一次睡眠唤醒。
    private func recoverMissingOwnedDisplays(request: Int) async {
        guard !quitting, !systemSleeping(), backend.lidAllowsRecovery, backend.isAvailable else { return }
        guard request == generation, !Task.isCancelled else { return }
        let current = (try? backend.screens()) ?? topology
        let ids = sessionIDsForMissingOwnedDisplays(in: current)
        if !ids.isEmpty {
            DisplayConnectionDiagnostics.trace("force-enable session ids=\(ids)")
            backend.forceEnableRemembered(ids)
            if await waitUntilUsable(request: request, attempts: 6) { return }
        }
        let latest = (try? backend.screens()) ?? topology
        let builtinMissing = state.records.contains {
            $0.ownedDisabled && $0.identity.isBuiltIn && DisplayConnectionPolicy.resolve($0.identity, in: latest) == nil
        }
        guard !rediscoveryAttempted, builtinMissing, !latest.contains(where: \.isUsable) else { return }
        rediscoveryAttempted = true
        guard await backend.rediscoverPhysicalDisplays() else { rediscoveryAttempted = false; return }
        _ = await waitUntilUsable(request: request, attempts: 16)
    }

    private func waitUntilUsable(request: Int, attempts: Int) async -> Bool {
        for attempt in 0..<attempts {
            guard request == generation, !Task.isCancelled else { return false }
            readTopology()
            if topology.contains(where: \.isUsable) { return true }
            if attempt + 1 < attempts {
                do { try await sleep() } catch { return false }
            }
        }
        return false
    }

    private func sessionIDsForMissingOwnedDisplays(in screens: [DisplayConnectionScreen]) -> [CGDirectDisplayID] {
        state.records.filter(\.ownedDisabled)
            .sorted { ($0.identity.isBuiltIn ? 0 : 1) < ($1.identity.isBuiltIn ? 0 : 1) }
            .compactMap { record in
                guard DisplayConnectionPolicy.resolve(record.identity, in: screens) == nil,
                      let id = sessionDisplayIDs.last(where: { $0.0.matches(record.identity) })?.1 else { return nil }
                if let occupant = screens.first(where: { $0.id == id }), !occupant.identity.matches(record.identity) {
                    return nil
                }
                return id
            }
    }

    private func restorationPriority(_ record: DisplayConnectionRecord) -> Int {
        guard let screen = DisplayConnectionPolicy.resolve(record.identity, in: topology) else { return 3 }
        if screen.isVisible { return record.identity.isBuiltIn ? 0 : 1 }
        return 2
    }

    private func set(_ id: UUID, enabled: Bool, changePreference: Bool, request: Int, allowEmergency: Bool = true) async {
        guard !Task.isCancelled, request == generation else { return }
        readTopology()
        guard let index = state.records.firstIndex(where: { $0.id == id }) else { return }
        let record = state.records[index]
        guard backend.isAvailable else { issues[id] = .unavailable; return }
        guard !systemSleeping() else { issues[id] = .waiting; return }
        guard let target = DisplayConnectionPolicy.resolve(record.identity, in: topology), target.isPhysical else {
            if enabled, allowEmergency, record.ownedDisabled {
                await recoverMissingOwnedDisplays(request: request)
                guard request == generation, !Task.isCancelled else { return }
                await set(id, enabled: enabled, changePreference: changePreference, request: request, allowEmergency: false)
                return
            }
            DisplayConnectionDiagnostics.trace("unresolved enabled=\(enabled) identity=\(record.identity) topology=\(topology)")
            issues[id] = .ambiguous; return
        }
        let wasConnected = target.isOnline && target.hasDesktop
        if !enabled && !wasConnected { issues[id] = nil; return }
        if !enabled {
            guard storageHealthy else { issues[id] = .storage; return }
            guard DisplayConnectionPolicy.canDisable(target, in: topology) else { issues[id] = .lastScreen; return }
        }
        issues[id] = nil
        // 启用前严格核对外部修改；自身启用主屏造成的全局原点平移不算布局冲突。
        let mirrorWasUnchanged = record.mirror?.expected.map {
            DisplayConnectionPolicy.mirrorsMatch($0, current: topology)
        } ?? false
        do {
            if !enabled {
                let original = DisplayConnectionPolicy.mirrorGroup(for: target, in: topology)
                if !original.isEmpty, state.records[index].mirror == nil {
                    state.records[index].mirror = .init(original: original)
                }
                // 先写拥有权与基线；中断也能找到本应用可能已停用的目标。
                state.records[index].ownedDisabled = true
            }
            state.operationPending = true; save()
            if !enabled && !storageHealthy { throw DisplayConnectionIssue.storage }
            if !enabled, let mirror = state.records[index].mirror {
                let members = mirror.original.compactMap { DisplayConnectionPolicy.resolve($0.identity, in: topology) }
                try configure(members.filter { $0.mirrorTarget != nil }.map { .mirror($0.identity, nil) })
                readTopology()
                let changedMembers = mirror.original.compactMap { DisplayConnectionPolicy.resolve($0.identity, in: topology) }
                state.records[index].mirror?.expected = DisplayConnectionPolicy.members(changedMembers, all: topology)
                save()
                // 镜像调整后重新检查目标与幸存屏，不使用事务前的旧 ID。
                guard let fresh = DisplayConnectionPolicy.resolve(record.identity, in: topology),
                      DisplayConnectionPolicy.canDisable(fresh, in: topology) else { throw DisplayConnectionIssue.lastScreen }
            }
            if enabled != wasConnected {
                try Task.checkCancellation()
                guard request == generation else { return }
                try configure([.enabled(record.identity, enabled)])
                try await verify(record.identity, enabled: enabled, request: request)
            }
            guard request == generation, !Task.isCancelled else { return }
            readTopology()
            if enabled {
                state.records[index].ownedDisabled = false
                try restoreMirror(index, allowTranslation: mirrorWasUnchanged && !wasConnected)
            } else if let mirror = state.records[index].mirror {
                let remaining = mirror.original.filter { $0.identity != record.identity }
                    .compactMap { DisplayConnectionPolicy.resolve($0.identity, in: topology) }
                state.records[index].mirror?.expected = DisplayConnectionPolicy.members(remaining, all: topology)
            }
            if changePreference { state.records[index].wantsDisabled = false }
            state.operationPending = false; save()
        } catch is CancellationError {
            // 保留待恢复日志，新的操作负责接手，不发布过期成功。
        } catch {
            guard request == generation else { return }
            let failure = (error as? DisplayConnectionIssue) ?? .failed
            issues[id] = failure
            AppLogger.ui.error("Display connection request failed: \(String(describing: error), privacy: .public)")
            readTopology()
            // 停用未生效时不写入偏好。目标仍在线且没有待恢复镜像时，释放这次拥有权。
            if !enabled, DisplayConnectionPolicy.resolve(record.identity, in: topology)?.isOnline == true {
                try? restoreMirror(index)
                if state.records[index].mirror == nil { state.records[index].ownedDisabled = false }
            }
            issues[id] = failure
            save()
        }
    }

    private func configure(_ commands: [DisplayConnectionCommand]) throws {
        guard !commands.isEmpty else { return }
        configurationAttempts += 1
        try backend.configure(commands)
    }

    private func verify(_ identity: DisplayConnectionIdentity, enabled: Bool, request: Int) async throws {
        for attempt in 0..<observationAttempts {
            try Task.checkCancellation()
            guard generation == request else { throw CancellationError() }
            let screens = try backend.screens()
            guard let target = DisplayConnectionPolicy.resolve(identity, in: screens) else { throw DisplayConnectionIssue.ambiguous }
            if (target.isOnline && target.hasDesktop) == enabled { topology = screens; return }
            if attempt + 1 < observationAttempts { try await sleep() }
        }
        throw DisplayConnectionIssue.unconfirmed
    }

    private func restoreMirror(_ index: Int, allowTranslation: Bool = false) throws {
        guard let saved = state.records[index].mirror else { return }
        let original = saved.original
        guard original.allSatisfy({ DisplayConnectionPolicy.resolve($0.identity, in: topology)?.isOnline == true }) else {
            issues[state.records[index].id] = .waiting; return
        }
        if DisplayConnectionPolicy.mirrorsMatch(original, current: topology) {
            state.records[index].mirror = nil; issues[state.records[index].id] = nil; return
        }
        guard let expected = saved.expected,
              DisplayConnectionPolicy.mirrorsMatch(expected, current: topology, allowTranslation: allowTranslation) else {
            issues[state.records[index].id] = .mirrorConflict
            // 外部布局已经不同，放弃保存的镜像，后续按当前布局继续。
            state.records[index].mirror = nil
            return
        }
        try configure(original.map { .mirror($0.identity, $0.target) })
        readTopology()
        guard original.allSatisfy({ member in
            guard let screen = DisplayConnectionPolicy.resolve(member.identity, in: topology) else { return false }
            let actual = screen.mirrorTarget.flatMap { target in topology.first { $0.id == target }?.identity }
            return actual == member.target
        }) else { throw DisplayConnectionIssue.unconfirmed }
        state.records[index].mirror = nil
        issues[state.records[index].id] = nil
    }
}

/// AppKit 只收到一次终止答复；等待上限不假装取消尚未返回的系统调用。
@MainActor
final class DisplayConnectionTermination {
    private var requested = false
    private(set) var hasReplied = false
    private var recoveryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func begin(restore: @escaping @MainActor () async -> Bool,
               wait: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(8)) },
               reply: @escaping @MainActor () -> Void) {
        guard !requested else { return }
        requested = true
        recoveryTask = Task { [weak self] in
            _ = await restore()
            self?.finish(reply)
        }
        timeoutTask = Task { [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled else { return }
            self?.finish(reply)
        }
    }

    private func finish(_ reply: () -> Void) {
        guard !hasReplied else { return }
        hasReplied = true
        timeoutTask?.cancel(); timeoutTask = nil
        recoveryTask = nil
        reply()
    }
}

@MainActor
final class DisplayConnectionCoordinator: ObservableObject {
    @Published private(set) var entries: [DisplayConnectionEntry] = []
    @Published private(set) var issue: DisplayConnectionIssue?
    @Published private(set) var isBusy = false
    private let executor: DisplayConnectionExecutor
    private let safetyDelay: @Sendable () async throws -> Void
    private var operation: Task<Void, Never>?
    private var safetyCheck: Task<Void, Never>?
    private var safetyWatchdog: Task<Void, Never>?
    private var version = 0
    private var pendingSafety = false
    private var started = false
    private var quitting = false
    var hasStarted: Bool { started }
    var revision: Int { version }
    var willChange: ((UUID?) async -> Bool)?
    var willRecover: (() -> Void)?
    var didChange: (() -> Void)?

    init(executor: DisplayConnectionExecutor = DisplayConnectionExecutor(),
         safetyDelay: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) {
        self.executor = executor; self.safetyDelay = safetyDelay
    }

    func start() {
        guard !started else { return }; started = true
        run(preparing: true) { await self.executor.boot() }
    }

    func refresh(recoverIfNeeded: Bool = false) {
        guard started, !quitting else { return }
        guard !isBusy else { pendingSafety = pendingSafety || recoverIfNeeded; return }
        run(preparing: recoverIfNeeded) { await self.executor.refresh(recoverIfNeeded: recoverIfNeeded) }
    }

    func topologyChanged(displayID: CGDirectDisplayID?, flags: CGDisplayChangeSummaryFlags) {
        DisplayConnectionDiagnostics.trace("event id=\(String(describing: displayID)) flags=\(flags.rawValue)")
        // 其他物理屏被移除时先恢复本应用停用的屏；不依赖系统列表先删掉旧条目。
        let removedSurvivor = flags.contains(.removeFlag) && entries.contains {
            $0.screen?.id == displayID && $0.screen?.isPhysical == true && !$0.record.ownedDisabled && !$0.isBusy
        }
        requestSafetyCheck(forceRestore: removedSurvivor)
    }

    func toggle(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        setEnabled(entry.observation != .connected, for: id)
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard !isBusy, !quitting else { return }
        run(target: id, preparing: true) { await self.executor.setEnabled(enabled, for: id) }
    }

    func cache(_ info: [DisplayInfo], identities: [CGDirectDisplayID: DisplayConnectionIdentity]) {
        guard started else { return }
        Task {
            let capturedVersion = version
            let snapshot = await executor.cache(info, identities: identities)
            guard capturedVersion == version, !isBusy else { return }
            apply(snapshot)
        }
    }

    func cacheControls(_ displays: [ControlledDisplay]) async { await executor.cacheControls(displays) }

    func prepareToQuit() async -> Bool {
        quitting = true; isBusy = true
        safetyWatchdog?.cancel(); safetyWatchdog = nil
        safetyCheck?.cancel(); safetyCheck = nil
        operation?.cancel(); version += 1; pendingSafety = false
        await executor.invalidate()
        if let willChange, !(await willChange(nil)) { return false }
        return await executor.prepareToQuit()
    }

    private func requestSafetyCheck(forceRestore: Bool = false) {
        guard started, !quitting else { return }
        if forceRestore {
            operation?.cancel(); safetyCheck?.cancel(); safetyCheck = nil
            pendingSafety = false
            // 无桌面时连接恢复优先，不等待可能已经卡住的 DDC I/O。
            willRecover?()
            run(replacing: true) {
                await self.executor.invalidate()
                let (snapshot, _) = await self.executor.checkSafety(forceRestore: true)
                return snapshot
            }
            return
        }
        guard !isBusy, safetyCheck == nil else { pendingSafety = true; return }
        let request = version
        safetyCheck = Task { [weak self] in
            guard let self else { return }
            let (snapshot, needsRecovery) = await executor.safetyProbe()
            guard !Task.isCancelled, request == version, !quitting else { return }
            safetyCheck = nil
            apply(snapshot)
            if needsRecovery { requestSafetyCheck(forceRestore: true) }
            else if pendingSafety { pendingSafety = false; requestSafetyCheck() }
        }
    }

    private func run(target: UUID? = nil, replacing: Bool = false, preparing: Bool = false,
                     _ body: @escaping @MainActor () async -> DisplayConnectionSnapshot) {
        if isBusy && !replacing { return }
        safetyCheck?.cancel(); safetyCheck = nil
        version += 1; let request = version
        isBusy = true
        for i in entries.indices { entries[i].isBusy = target == nil || entries[i].id == target }
        operation = Task {
            if preparing, let willChange, !(await willChange(target)) {
                guard request == version else { return }
                isBusy = false; issue = .waiting
                for i in entries.indices { entries[i].isBusy = false }
                didChange?()
                if pendingSafety { pendingSafety = false; requestSafetyCheck() }
                return
            }
            guard !Task.isCancelled, request == version else { return }
            let snapshot = await body()
            guard !Task.isCancelled, request == version else { return }
            apply(snapshot); isBusy = false; operation = nil
            didChange?()
            if pendingSafety { pendingSafety = false; requestSafetyCheck() }
        }
    }

    private func apply(_ snapshot: DisplayConnectionSnapshot) {
        if entries != snapshot.entries { entries = snapshot.entries }
        if issue != snapshot.issue { issue = snapshot.issue }
        let needsMonitor = entries.contains { $0.record.ownedDisabled }
        if needsMonitor, safetyWatchdog == nil, !quitting {
            let delay = safetyDelay
            safetyWatchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await delay() } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    self.requestSafetyCheck()
                }
            }
        } else if !needsMonitor || quitting {
            safetyWatchdog?.cancel(); safetyWatchdog = nil
        }
    }
}
