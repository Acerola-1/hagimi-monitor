import CoreGraphics
import Foundation
import OSLog

private let engineLog = Logger(subsystem: "com.acerola.hagimi-monitor.direct", category: "DisplayEngine")

/// 显示器控制编排引擎(D1/D2/D3/D4 的执行基座)。
///
/// 值状态按 observed/desired/historical/applied 分离,未知值显式为 nil;
/// 每次显式操作至少产生一次最终发送,每 (连接, 属性) 只保留一个最新目标;
/// 全局单 in-flight transaction 使底层请求有界,门禁抑制的目标留在调度器槽内并在恢复后重放;
/// 传输、时钟均可注入,测试不触碰真实显示器。
///
/// 线程模型:引擎状态由单串行队列独占;快照发布走主线程外的主消费方。
nonisolated final class DisplayControlEngine {
    let clock: MonotonicClock
    private let transport: DDCTransport
    private let queue = DispatchQueue(label: "hagimi.ddc.engine")
    /// 阻塞 I/O 等待期限(等待 transport 返回),不是底层取消。
    private let callDeadline: TimeInterval

    // MARK: - 连接与状态

    private var connections: [UUID: DisplayConnection] = [:]
    private var attributeStates: [UUID: [DisplayControlKind: AttributeValueState]] = [:]
    /// 待写槽:每 (连接, 属性) 至多一个最新目标。门禁抑制时槽保留(状态转 deferred)。
    private var pendingWrites: [UUID: [DisplayControlKind: PendingWrite]] = [:]
    private var pendingReads: Set<UUID> = []
    private var pendingReadAttributes: [UUID: Set<DisplayControlKind>] = [:]
    private var throttleTimers: [UUID: [DisplayControlKind: ScheduledWorkHandle]] = [:]
    private var confirmTimers: [UUID: [DisplayControlKind: ScheduledWorkHandle]] = [:]
    /// 全局 in-flight:底层尚未返回时不再提交新 transaction。
    private var inFlight: InFlightTransaction?
    /// 超时等待后通道 stalled:不再提交新事务,直到真实返回。
    private var channelStalled = false
    private var recoveryAttempt = 0
    private var recoveryTimer: ScheduledWorkHandle?
    /// 每 (连接, 属性) 的 raw 最大值(探测/读回获得),默认 100。
    private var maxValues: [UUID: [DisplayControlKind: UInt16]] = [:]

    private struct PendingWrite {
        let value: Double
    }

    private struct InFlightTransaction {
        let token: UUID
        let requestID: UInt64
        let kind: TransactionKind
        var timedOut = false
    }

    private enum TransactionKind {
        case write(value: Double, control: DisplayControlKind, raw: UInt16)
        case read(control: DisplayControlKind)
        case confirm(control: DisplayControlKind, target: Double, attemptsLeft: Int)
    }

    private var nextRequestID: UInt64 = 0

    // MARK: - 快照输出

    nonisolated struct Snapshot: Sendable {
        var connections: [DisplayConnection] = []
        var states: [UUID: [DisplayControlKind: AttributeValueState]] = [:]
        var channelStalled = false
    }

    private var onSnapshot: ((Snapshot) -> Void)?

    func setSnapshotHandler(_ handler: @escaping (Snapshot) -> Void) {
        queue.async {
            self.onSnapshot = handler
        }
    }

    private func publishSnapshot() {
        guard let onSnapshot else { return }
        onSnapshot(Snapshot(
            connections: Array(connections.values),
            states: attributeStates,
            channelStalled: channelStalled
        ))
    }

    init(
        clock: MonotonicClock = DispatchMonotonicClock(),
        transport: DDCTransport,
        callDeadline: TimeInterval = DisplayControlTiming.callDeadline
    ) {
        self.clock = clock
        self.transport = transport
        self.callDeadline = callDeadline
    }

    // MARK: - 连接生命周期(D1/2.3)

    /// 拓扑更新:整体替换连接集合。失效 token 的瞬时会话状态全部清理;
    /// 同 token 但服务对象替换同样视为失效,迟到回调不会改变当前连接。
    func replaceConnections(_ newConnections: [DisplayConnection]) {
        queue.async {
            let oldTokens = Set(self.connections.keys)
            let newTokens = Set(newConnections.map { $0.token })
            for token in oldTokens.subtracting(newTokens) {
                self.clearTransientState(for: token)
            }
            for connection in newConnections {
                if let old = self.connections[connection.token], old.service != connection.service {
                    self.clearTransientState(for: connection.token)
                }
                self.connections[connection.token] = connection
                self.attributeStates[connection.token, default: [:]] = self.attributeStates[connection.token] ?? [:]
            }
            for token in oldTokens.subtracting(newTokens) {
                self.connections.removeValue(forKey: token)
            }
            self.publishSnapshot()
        }
    }

    func removeConnection(token: UUID) {
        queue.async {
            self.clearTransientState(for: token)
            self.connections.removeValue(forKey: token)
            self.publishSnapshot()
        }
    }

    private func clearTransientState(for token: UUID) {
        pendingWrites[token] = nil
        pendingReads.remove(token)
        pendingReadAttributes[token] = nil
        attributeStates[token] = nil
        if let timers = throttleTimers[token] {
            for timer in timers.values { timer.cancel() }
            throttleTimers[token] = nil
        }
        if let timers = confirmTimers[token] {
            for timer in timers.values { timer.cancel() }
            confirmTimers[token] = nil
        }
        maxValues[token] = nil
    }

    // MARK: - 用户写入(D2/3.2/3.3)

    /// 用户显式操作:进入待写槽并节流提交。每次显式操作至少产生一次最终发送。
    func enqueueWrite(token: UUID, control: DisplayControlKind, value: Double, final: Bool) {
        guard value.isFinite else { return }
        let clamped = min(100, Swift.max(0, value))
        queue.async {
            guard self.connections[token] != nil else { return }
            self.nextRequestID += 1
            let requestID = self.nextRequestID
            self.pendingWrites[token, default: [:]][control] = PendingWrite(value: clamped)

            var state = self.attributeStates[token]?[control] ?? AttributeValueState()
            state.desired = clamped
            state.source = .desired
            state.writeStatus = .pending
            state.activeRequestID = requestID
            self.attributeStates[token, default: [:]][control] = state

            // 连续输入合并:非 final 输入在已有节流 timer 时**不重置**——固定窗口到点
            // 提交当时槽内的最新目标,而非"每次输入取消定时器直到停手"的无限尾部 debounce。
            // final(松手)用短 grace 立即落槽。
            if final {
                self.throttleTimers[token]?[control]?.cancel()
                self.throttleTimers[token, default: [:]][control] = self.clock.schedule(
                    after: DisplayControlTiming.finalCommitGrace
                ) { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        self.throttleTimers[token]?[control] = nil
                        self.drain()
                    }
                }
            } else if self.throttleTimers[token]?[control] == nil {
                self.throttleTimers[token, default: [:]][control] = self.clock.schedule(
                    after: DisplayControlTiming.throttleInterval
                ) { [weak self] in
                    guard let self else { return }
                    self.queue.async {
                        self.throttleTimers[token]?[control] = nil
                        self.drain()
                    }
                }
            }
            self.publishSnapshot()
        }
    }

    // MARK: - 读数(D2/D7)

    /// 请求读取(合并:同一连接只保留一个待执行读 + 属性并集)。
    func enqueueRead(token: UUID, controls: Set<DisplayControlKind>) {
        queue.async {
            guard self.connections[token] != nil else { return }
            self.pendingReads.insert(token)
            self.pendingReadAttributes[token, default: []].formUnion(controls)
            self.drain()
        }
    }

    // MARK: - 门禁(D4/5.x)

    private var gateProvider: (() -> Bool)?
    func setGateProvider(_ provider: @escaping () -> Bool) {
        queue.async {
            self.gateProvider = provider
        }
    }

    /// 门禁解除:核验状态后重放槽内最新目标。stalled 通道保留目标等待真实恢复。
    func handleGateRecovery() {
        queue.async {
            guard !self.channelStalled else { return }
            self.recoveryAttempt = 0
            self.recoveryTimer?.cancel()
            self.recoveryTimer = nil
            self.drain()
        }
    }

    // MARK: - 调度核心(D3)

    /// 推进调度:写优先于读;全局单 in-flight;stalled 通道不提交。
    private func drain() {
        if channelStalled || recoveryTimer != nil { return }
        guard inFlight == nil else { return }

        if let (token, control, write) = nextPendingWrite() {
            attemptWrite(token: token, control: control, write: write)
            return
        }
        if let token = pendingReads.first, !(pendingReadAttributes[token] ?? []).isEmpty {
            attemptRead(token: token, controls: pendingReadAttributes[token] ?? [])
            return
        }
    }

    /// 连接间 round-robin:优先服务与上次不同的连接,避免单屏拖动饿死其他屏。
    private func nextPendingWrite() -> (UUID, DisplayControlKind, PendingWrite)? {
        let tokens = pendingWrites.keys.filter { pendingWrites[$0]?.isEmpty == false }
        guard !tokens.isEmpty else { return nil }
        let ordered = tokens.sorted { lhs, rhs in
            if (lhs == lastServedToken) != (rhs == lastServedToken) {
                return lhs != lastServedToken
            }
            return lhs.uuidString < rhs.uuidString
        }
        for token in ordered {
            guard let controls = pendingWrites[token] else { continue }
            if let (control, write) = controls.sorted(by: { $0.key.storageKey < $1.key.storageKey }).first {
                lastServedToken = token
                return (token, control, write)
            }
        }
        return nil
    }

    private var lastServedToken: UUID?

    private func attemptWrite(token: UUID, control: DisplayControlKind, write: PendingWrite) {
        guard let connection = connections[token] else {
            pendingWrites[token]?[control] = nil
            return
        }
        // 门禁抑制:目标留在槽内,状态转 deferred;恢复后重放。
        if gateProvider?() == true {
            var state = attributeStates[token]?[control] ?? AttributeValueState()
            state.writeStatus = .deferred
            attributeStates[token, default: [:]][control] = state
            publishSnapshot()
            return
        }
        let max = maxValues[token]?[control] ?? 100
        guard let raw = DDCRawConversion.ddcRaw(percent: write.value, max: max) else {
            return
        }

        nextRequestID += 1
        let requestID = nextRequestID
        inFlight = InFlightTransaction(token: token, requestID: requestID, kind: .write(value: write.value, control: control, raw: raw))

        // 等待期限:超时只放弃等待并标记 stalled,保留 in-flight 直到真实返回。
        _ = clock.schedule(after: callDeadline) { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard let flight = self.inFlight, flight.requestID == requestID, !flight.timedOut else { return }
                self.channelStalled = true
                self.inFlight?.timedOut = true
                var state = self.attributeStates[token]?[control] ?? AttributeValueState()
                state.writeStatus = .sentUnverified
                self.attributeStates[token, default: [:]][control] = state
                self.publishSnapshot()
                engineLog.warning("DDC call deadline exceeded; channel stalled, awaiting real return")
            }
        }

        transport.write(service: connection.service, vcpCode: vcpCode(for: control), value: raw) { [weak self] success in
            guard let self else { return }
            self.queue.async {
                self.handleWriteReturn(token: token, requestID: requestID, success: success)
            }
        }
    }

    private func handleWriteReturn(token: UUID, requestID: UInt64, success: Bool) {
        guard let flight = inFlight, flight.requestID == requestID else {
            // 已失效连接或请求的迟到返回不发布,避免覆盖当前会话状态。
            return
        }
        inFlight = nil
        channelStalled = false

        guard connections[token] != nil else {
            drain()
            return
        }

        guard case let .write(value, control, _) = flight.kind else { return }

        var state = attributeStates[token]?[control] ?? AttributeValueState()
        if success {
            if pendingWrites[token]?[control]?.value == value {
                pendingWrites[token]?[control] = nil
            }
            state.lastApplied = value
            // 写入回调只证明报文已返回;设备值仍由确认读对齐。
            state.writeStatus = .sentUnverified
            // 仅当目标仍为当前值时安排确认,让确认读取对应最新目标。
            let stillCurrent = state.activeRequestID == requestID || state.desired == value
            if stillCurrent {
                scheduleConfirmation(token: token, control: control, target: value, attemptsLeft: 2)
            }
        } else {
            state.writeStatus = .failed
            scheduleRecoveryBackoff()
        }
        attributeStates[token, default: [:]][control] = state
        publishSnapshot()
        drain()
    }

    private func attemptRead(token: UUID, controls: Set<DisplayControlKind>) {
        guard let connection = connections[token] else {
            pendingReads.remove(token)
            return
        }
        pendingReads.remove(token)
        pendingReadAttributes[token] = nil

        if gateProvider?() == true {
            // 抑制期间读让位:不执行;恢复后的周期/重放重新发起。
            return
        }

        let control = controls.first ?? .brightness
        nextRequestID += 1
        let requestID = nextRequestID
        inFlight = InFlightTransaction(token: token, requestID: requestID, kind: .read(control: control))

        armDeadline(token: token, control: control, requestID: requestID)

        transport.read(service: connection.service, vcpCode: vcpCode(for: control)) { [weak self] reply in
            guard let self else { return }
            self.queue.async {
                self.handleReadReturn(token: token, requestID: requestID, reply: reply, controls: controls)
            }
        }
    }

    private func handleReadReturn(token: UUID, requestID: UInt64, reply: DDCTransportReply?, controls: Set<DisplayControlKind>) {
        guard let flight = inFlight, flight.requestID == requestID else { return }
        inFlight = nil
        channelStalled = false
        defer { drain() }

        guard connections[token] != nil else { return }

        guard let reply, reply.resultCode == 0x00, DDCRawConversion.isValidRange(max: reply.max),
              let percent = DDCRawConversion.percent(raw: reply.current, max: reply.max) else {
            return
        }
        // 记录探测到的范围,后续写转换用。
        let control = controls.first ?? .brightness
        maxValues[token, default: [:]][control] = reply.max
        var state = attributeStates[token]?[control] ?? AttributeValueState()
        state.observed = percent
        state.source = .observed
        // 读数晚于目标:observed 更新,但 desired 保留(displayValue 目标优先);
        // 达容差 → verified。
        if let desired = state.desired, attributeValueMatches(observed: percent, desired: desired, max: reply.max) {
            state.writeStatus = .verified
            state.desired = nil
        }
        attributeStates[token, default: [:]][control] = state
        publishSnapshot()

        // 合并读剩余属性继续(单 in-flight 约束下逐个完成)。
        let rest = controls.subtracting([control])
        if !rest.isEmpty {
            pendingReads.insert(token)
            pendingReadAttributes[token] = rest
            drain()
        }
    }

    // MARK: - 确认回读(D2/7.4)

    private func scheduleConfirmation(token: UUID, control: DisplayControlKind, target: Double, attemptsLeft: Int) {
        confirmTimers[token]?[control]?.cancel()
        let handle = clock.schedule(after: DisplayControlTiming.confirmReadDelay) { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.confirmTimers[token]?[control] = nil
                self.performConfirmation(token: token, control: control, target: target, attemptsLeft: attemptsLeft)
            }
        }
        confirmTimers[token, default: [:]][control] = handle
    }

    private func performConfirmation(token: UUID, control: DisplayControlKind, target: Double, attemptsLeft: Int) {
        // 目标已变化时,当前确认读取不再对应目标值。
        if let state = attributeStates[token]?[control], let desired = state.desired, abs(desired - target) > 0.001 {
            return
        }
        guard let connection = connections[token], gateProvider?() != true else { return }
        guard inFlight == nil, !channelStalled else { return }

        nextRequestID += 1
        let requestID = nextRequestID
        inFlight = InFlightTransaction(token: token, requestID: requestID, kind: .confirm(control: control, target: target, attemptsLeft: attemptsLeft))
        armDeadline(token: token, control: control, requestID: requestID)
        transport.read(service: connection.service, vcpCode: vcpCode(for: control)) { [weak self] reply in
            guard let self else { return }
            self.queue.async {
                self.handleConfirmReturn(token: token, control: control, requestID: requestID, target: target, attemptsLeft: attemptsLeft, reply: reply)
            }
        }
    }

    private func handleConfirmReturn(token: UUID, control: DisplayControlKind, requestID: UInt64, target: Double, attemptsLeft: Int, reply: DDCTransportReply?) {
        guard let flight = inFlight, flight.requestID == requestID else { return }
        inFlight = nil
        channelStalled = false
        defer { drain() }

        guard let reply, reply.resultCode == 0x00, DDCRawConversion.isValidRange(max: reply.max),
              let percent = DDCRawConversion.percent(raw: reply.current, max: reply.max) else {
            // 无有效读数:有限次重试。
            if attemptsLeft > 0 {
                scheduleConfirmationRetry(token: token, control: control, target: target, attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        var state = attributeStates[token]?[control] ?? AttributeValueState()
        state.observed = percent
        state.source = .observed
        maxValues[token, default: [:]][control] = reply.max
        if attributeValueMatches(observed: percent, desired: target, max: reply.max) {
            state.writeStatus = .verified
            if state.desired == target { state.desired = nil }
        } else if attemptsLeft > 0 {
            scheduleConfirmationRetry(token: token, control: control, target: target, attemptsLeft: attemptsLeft - 1)
            attributeStates[token, default: [:]][control] = state
            publishSnapshot()
            return
        } else {
            // 持续不一致:保留未确认与真实读数,不伪造成功。
            state.writeStatus = .sentUnverified
        }
        attributeStates[token, default: [:]][control] = state
        publishSnapshot()
    }

    private func scheduleConfirmationRetry(token: UUID, control: DisplayControlKind, target: Double, attemptsLeft: Int) {
        let handle = clock.schedule(after: DisplayControlTiming.confirmRetryDelay) { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.confirmTimers[token]?[control] = nil
                self.performConfirmation(token: token, control: control, target: target, attemptsLeft: attemptsLeft)
            }
        }
        confirmTimers[token, default: [:]][control] = handle
    }

    // MARK: - 故障退避(D3/4.4)

    private func scheduleRecoveryBackoff() {
        guard recoveryAttempt < DisplayControlTiming.recoveryBackoff.count else { return }
        let delay = DisplayControlTiming.recoveryBackoff[recoveryAttempt]
        recoveryAttempt += 1
        recoveryTimer?.cancel()
        recoveryTimer = clock.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.recoveryTimer = nil
                self.drain()
            }
        }
    }

    /// 手动重新检测/连接事件:清退避与 stalled,允许重新提交。
    func resetRecoveryState() {
        queue.async {
            self.recoveryAttempt = 0
            if self.inFlight == nil {
                self.channelStalled = false
            }
            self.recoveryTimer?.cancel()
            self.recoveryTimer = nil
            self.drain()
        }
    }

    private func armDeadline(token: UUID, control: DisplayControlKind, requestID: UInt64) {
        _ = clock.schedule(after: callDeadline) { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard let flight = self.inFlight,
                      flight.requestID == requestID,
                      flight.token == token,
                      !flight.timedOut else { return }
                self.channelStalled = true
                self.inFlight?.timedOut = true
                var state = self.attributeStates[token]?[control] ?? AttributeValueState()
                state.writeStatus = .sentUnverified
                self.attributeStates[token, default: [:]][control] = state
                self.publishSnapshot()
            }
        }
    }

    private func vcpCode(for control: DisplayControlKind) -> UInt8 {
        switch control {
        case .brightness: 0x10
        case .volume: 0x62
        case .contrast: 0x12
        }
    }

    // MARK: - 测试辅助(@testable 专用)

    /// 等待引擎队列消费完当前积压(测试同步点)。
    func __waitForIdleForTesting() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
    }

    /// 取当前状态快照(测试断言用)。
    func __snapshotForTesting() async -> Snapshot {
        await withCheckedContinuation { (continuation: CheckedContinuation<Snapshot, Never>) in
            queue.async {
                continuation.resume(returning: Snapshot(
                    connections: Array(self.connections.values),
                    states: self.attributeStates,
                    channelStalled: self.channelStalled
                ))
            }
        }
    }
}
