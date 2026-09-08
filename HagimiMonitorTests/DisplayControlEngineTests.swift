import Testing
@testable import HagimiMonitorDirect
import CoreGraphics
import Foundation

@Suite(.serialized)
@MainActor
struct DisplayControlEngineTests {
    private let service = DDCServiceHandle(identity: "svc-1", chipAddress: 0x37)

    private func makeConnection(token: UUID = UUID(), displayID: CGDirectDisplayID = 1) -> DisplayConnection {
        DisplayConnection(
            token: token,
            displayID: displayID,
            identity: DisplayIdentity(vendorID: 0x1234, productID: 0x5678, serialNumber: "42", edidUUID: nil, isBuiltIn: false),
            service: service,
            isUserBound: false
        )
    }

    /// 等待引擎串行队列消费完当前积压。
    private func settle(_ engine: DisplayControlEngine) async {
        await engine.__waitForIdleForTesting()
    }

    /// 提交一次写入并推进虚拟时钟:先 settle 让 enqueue 落定并调度 timer,
    /// 再 advance 触发节流/终值提交,再 settle 消化 transport 回调。避免
    /// queue.async 未及时执行导致 timer 错过推进窗口的时序竞争。
    private func runWrite(
        _ engine: DisplayControlEngine,
        clock: VirtualMonotonicClock,
        token: UUID,
        control: DisplayControlKind,
        value: Double,
        final: Bool = true,
        advance: TimeInterval = 0.5
    ) async {
        await settle(engine)
        engine.enqueueWrite(token: token, control: control, value: value, final: final)
        await settle(engine)
        clock.advance(by: advance)
        await settle(engine)
    }

    // MARK: - 1.4/A2 回归:外部改值后设回

    /// 应用设 50 → 外部(显示器按钮)改 80 → 应用再设 50:
    /// 第二次 50 必须真正到达底层(旧 lastWrittenValues 永久去重会吞掉这次写)。
    @Test func repeatedSetAfterExternalChangeReachesTransport() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)
        transport.resetRecords()

        // 第一次设 50。
        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 50)
        let firstCount = transport.writeCount()
        #expect(firstCount == 1)
        #expect(transport.writes.first?.value == 50)

        // 外部把显示器改成 80(模拟:一次读回观测到 80)。
        transport.setReadReply(current: 80, max: 100)
        await settle(engine)
        engine.enqueueRead(token: token, controls: [.brightness])
        await settle(engine)
        clock.advance(by: 0.1)
        await settle(engine)

        // 用户再设回 50:必须再次发送。
        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 50)
        #expect(transport.writeCount() == 2, "第二次设 50 必须到达底层,永久去重会吞掉它")
        #expect(transport.writes.last?.value == 50)
    }

    // MARK: - 3.2:两次独立设置同值均到达

    @Test func twoIndependentWritesOfSameValueBothSend() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)
        transport.resetRecords()

        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 50)
        #expect(transport.writeCount() == 1)

        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 50)
        #expect(transport.writeCount() == 2, "两次独立设置 50 均应到达 fake 后端")
    }

    // MARK: - 3.3:连续输入合并

    /// 100 次快速输入:每属性至多一个待写槽,终值正确。
    @Test func rapidInputsCollapseToSinglePendingSlotWithFinalValue() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)
        transport.resetRecords()

        for i in 0..<100 {
            await settle(engine)
            engine.enqueueWrite(token: token, control: .brightness, value: Double(i), final: i == 99)
        }
        await settle(engine)
        // 节流窗口未过:至多一次底层提交。
        clock.advance(by: 0.1)
        await settle(engine)
        let midCount = transport.writeCount()
        #expect(midCount <= 1, "节流窗口内不应多次提交")

        clock.advance(by: 1.1)
        await settle(engine)
        #expect(transport.writes.last?.value == 99, "终值 99 必须提交")
        #expect(transport.writeCount() <= 3, "100 次输入只保留有限提交")
    }

    /// 持续输入不无限等待停手:每个节流窗口到点提交当时的最新目标。
    @Test func continuousInputDoesNotWaitForStop() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)
        transport.resetRecords()

        // 模拟持续拖动:每 100ms 一个新值,拖 1 秒。
        for i in 0..<10 {
            await settle(engine)
            engine.enqueueWrite(token: token, control: .brightness, value: Double(10 + i), final: false)
            await settle(engine)
            clock.advance(by: 0.1)
            await settle(engine)
        }
        #expect(transport.writeCount() >= 3, "持续输入应随节流窗口分批提交,而非等停手")
        #expect(transport.writes.last?.value == 19)
    }

    // MARK: - 3.1:值来源与 requestID

    /// 50→80→50:迟到回调不能把界面目标改回旧值。
    @Test func lateCallbackDoesNotOverrideNewerTarget() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 50, final: true)
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 80, final: true)
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)

        // 目标应为 80(最新),desired 语义生效。
        let snapshot = await engine.__snapshotForTesting()
        let state = snapshot.states[token]?[.brightness]
        #expect(state?.desired == 80)
    }

    /// 读数晚于目标:observed 更新但 desired 保留,展示值仍是目标。
    @Test func readAfterTargetKeepsDesiredSemantics() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        // 先有读数 50。
        transport.setReadReply(current: 50, max: 100)
        await settle(engine)
        engine.enqueueRead(token: token, controls: [.brightness])
        await settle(engine)
        clock.advance(by: 0.1)
        await settle(engine)

        // 用户设 80,目标尚未确认。
        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 80)

        // 读数仍回 50(显示器尚未生效):不能覆盖目标展示。
        transport.setReadReply(current: 50, max: 100)
        await settle(engine)
        engine.enqueueRead(token: token, controls: [.brightness])
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        let state = snapshot.states[token]?[.brightness]
        #expect(state?.desired == 80, "过期读数不能盖掉新目标")
        #expect(state?.observed == 50)
        #expect(state?.displayValue == 80)
    }

    // MARK: - 1.4/A6 回归:门禁重放

    /// 抑制窗口内的写:不被发送;恢复后自动重放最新目标(不依赖面板刷新)。
    @Test func suppressedWriteReplaysAfterGateRecovery() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        var gateSuppressed = true
        engine.setGateProvider { gateSuppressed }
        await settle(engine)

        // 抑制窗口内设 30、再设 60。
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 30, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 60, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        #expect(transport.writeCount() == 0, "抑制窗口内不得触达底层")

        // 门禁解除:恢复后只重放最新目标 60。
        gateSuppressed = false
        engine.handleGateRecovery()
        clock.advance(by: 0.2)
        await settle(engine)
        #expect(transport.writeCount() == 1)
        #expect(transport.writes.first?.value == 60, "只重放最新目标 60,不重放 30")
    }

    /// setMode 门禁(begin→complete):抑制期写延迟,沉降结束后重放。
    @Test func reconfigureGateDefersThenReplays() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        var gateSuppressed = false
        engine.setGateProvider { gateSuppressed }
        await settle(engine)

        gateSuppressed = true
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 40, final: true)
        await settle(engine)
        clock.advance(by: 0.3)
        await settle(engine)
        #expect(transport.writeCount() == 0)

        gateSuppressed = false
        await settle(engine)
        engine.handleGateRecovery()
        await settle(engine)
        clock.advance(by: 0.3)
        await settle(engine)
        #expect(transport.writeCount() == 1)
        #expect(transport.writes.first?.value == 40)
    }

    /// begin-only safety 到期:恢复事件统一触发重放(通知缺失场景)。
    @Test func beginOnlySafetyExpiryTriggersReplay() async throws {
        let virtualClock = VirtualMonotonicClock()
        let gate = DDCGateRuntime(
            clock: virtualClock,
            wakeSettle: 0.1,
            reconfigureSettle: 0.1,
            reconfigureSafety: 0.2
        )
        var recovered = false
        let token = gate.addRecoveryHandler { recovered = true }

        gate.reconfigureStarted()
        #expect(gate.isSuppressed)
        // 只推进到 safety 到期(无完成回调),应自动解除并触发恢复。
        virtualClock.advance(by: 0.3)
        #expect(!gate.isSuppressed, "begin-only safety 到期必须自动解除")
        #expect(recovered, "解除必须发出恢复事件(重放依赖)")
        gate.removeRecoveryHandler(token)
    }

    // MARK: - 2.3:连接替换

    /// 旧连接回调不能改变新屏:token 失效后状态清空。
    @Test func staleTokenCallbacksDoNotAffectNewConnection() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let oldToken = UUID()
        engine.replaceConnections([makeConnection(token: oldToken)])
        await settle(engine)

        await settle(engine)
        engine.enqueueWrite(token: oldToken, control: .brightness, value: 70, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)

        // 拓扑更新:同 displayID 复用编号,但新 token(设备更换)。
        let newToken = UUID()
        engine.replaceConnections([makeConnection(token: newToken, displayID: 1)])
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        #expect(snapshot.states[oldToken] == nil, "旧 token 的瞬时会话状态必须清理")
        #expect(snapshot.states[newToken]?[.brightness]?.desired == nil, "新连接不继承旧目标")
    }

    @Test func removedConnectionRejectsOldTokenWrites() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let oldToken = UUID()
        engine.replaceConnections([makeConnection(token: oldToken)])
        await settle(engine)

        engine.replaceConnections([])
        await settle(engine)
        engine.enqueueWrite(token: oldToken, control: .brightness, value: 55, final: true)
        await settle(engine)
        clock.advance(by: 1)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        #expect(snapshot.connections.isEmpty)
        #expect(transport.writeCount() == 0, "已移除 token 不能再触达底层")
    }

    // MARK: - 4.4:有界退避

    /// 写失败后 1/2/5/15s 四次自动恢复,之后停止。
    @Test func boundedBackoffStopsAfterFourAttempts() async throws {
        let transport = FakeDDCTransport()
        transport.writeSucceeds = false
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 55, final: true)
        await settle(engine)
        // 退避 1+2+5+15 = 23s:推进 60s 应只触发有限次。
        clock.advance(by: 60)
        await settle(engine)
        let count = transport.writeCount()
        #expect(count >= 1)
        #expect(count <= 6, "自动重试应有界(初始 + 四次退避),实际 \(count)")
    }

    @Test func failedWriteIsRetriedAfterBackoff() async throws {
        let transport = FakeDDCTransport()
        transport.writeSucceeds = false
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        engine.enqueueWrite(token: token, control: .brightness, value: 55, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        #expect(transport.writeCount() == 1)

        clock.advance(by: 1.0)
        await settle(engine)
        #expect(transport.writeCount() >= 2, "失败写入必须保留目标并在退避后重试")
    }

    // MARK: - 挂起与迟到返回(4.3)

    /// 底层挂起超时:stalled 通道不再提交新事务;真实返回后恢复。
    @Test func stalledChannelDoesNotSubmitSecondTransaction() async throws {
        let transport = FakeDDCTransport()
        transport.blockWrites = true
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport, callDeadline: 0.1)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 30, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        #expect(transport.writeCount() == 1)

        // stalled 期间再次写:不产生第二次底层提交。
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 40, final: true)
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)
        #expect(transport.writeCount() == 1, "stalled 通道不得并发提交")

        // 真实返回:目标 40 在恢复后送达。
        transport.releaseBlockedCalls()
        transport.blockWrites = false
        clock.advance(by: 0.5)
        await settle(engine)
        #expect(transport.writeCount() == 2, "恢复后最新目标 40 应送达")
        #expect(transport.writes.last?.value == 40)
    }

    @Test func blockedReadReachesStalledStateUntilRealReturn() async throws {
        let transport = FakeDDCTransport()
        transport.blockReads = true
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport, callDeadline: 0.1)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        engine.enqueueRead(token: token, controls: [.brightness])
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        #expect((await engine.__snapshotForTesting()).channelStalled)

        engine.enqueueWrite(token: token, control: .brightness, value: 40, final: true)
        await settle(engine)
        clock.advance(by: 0.2)
        await settle(engine)
        #expect(transport.writeCount() == 0, "读挂起期间不能并发写入")

        transport.blockReads = false
        transport.releaseBlockedCalls()
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)
        #expect(transport.writeCount() == 1, "读真实返回后应解除 stalled 并发送最新写入")
    }

    // MARK: - 7.2:读合并

    /// 多次读请求合并:慢刷新(读挂起)期间不积压重复读。
    @Test func repeatedReadRequestsMerge() async throws {
        let transport = FakeDDCTransport()
        transport.setReadReply(current: 33, max: 100)
        transport.blockReads = true
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        // 读挂起期间连续多次请求:只保留一个待执行读。
        for _ in 0..<10 {
            await settle(engine)
            engine.enqueueRead(token: token, controls: [.brightness])
        }
        await settle(engine)
        #expect(transport.readCount() == 1, "挂起读期间不应累积重复读,实际 \(transport.readCount())")

        // 释放后不产生额外读(请求已合并)。
        transport.releaseBlockedCalls()
        await settle(engine)
        #expect(transport.readCount() <= 2, "合并读应显著少于请求数,实际 \(transport.readCount())")
    }

    // MARK: - 4.5:写优先于读 + 连接间 round-robin

    /// 用户写优先于尚未开始的周期读:待读不阻挡用户最终写。
    @Test func writeTakesPriorityOverPendingRead() async throws {
        let transport = FakeDDCTransport()
        transport.setReadReply(current: 50, max: 100)
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        // 先排队读,再用户写。
        await settle(engine)
        engine.enqueueRead(token: token, controls: [.brightness])
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: 70, final: true)
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)

        // 写先于读执行:transport 记录里第一个应是写。
        let writeIdx = transport.writes.count
        #expect(writeIdx >= 1, "用户写必须到达底层")
        #expect(transport.writes.first?.value == 70, "写优先")
    }

    /// 两连接持续写:round-robin 避免单屏拖动饿死另一屏。
    @Test func roundRobinAvoidsStarvationAcrossConnections() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let tokenA = UUID()
        let tokenB = UUID()
        engine.replaceConnections([makeConnection(token: tokenA), makeConnection(token: tokenB)])
        await settle(engine)

        // A 持续拖动(多次写),B 一次写:应保证 B 不被饿死。
        for i in 0..<5 {
            await settle(engine)
            engine.enqueueWrite(token: tokenA, control: .brightness, value: Double(i), final: false)
            await settle(engine)
            clock.advance(by: 0.2)
            await settle(engine)
        }
        // 让 A 的拖动全部落定后再排 B。
        await settle(engine)
        engine.enqueueWrite(token: tokenB, control: .brightness, value: 60, final: true)
        await settle(engine)
        clock.advance(by: 2.0)
        await settle(engine)

        // B 的 60 必须到达。
        let bWrites = transport.writes.filter { $0.value == 60 }
        #expect(!bWrites.isEmpty, "连接 B 不应被连接 A 的持续拖动饿死")
    }

    // MARK: - 4.1:缓冲量有界

    /// 100 次快速写:待写槽不随操作次数增长(每属性一个槽)。
    @Test func pendingBufferDoesNotGrowWithOperationCount() async throws {
        let transport = FakeDDCTransport()
        transport.blockWrites = true
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport, callDeadline: 0.05)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        // 挂起期间 100 次写。
        for i in 0..<100 {
            await settle(engine)
            engine.enqueueWrite(token: token, control: .brightness, value: Double(i), final: true)
        }
        await settle(engine)
        clock.advance(by: 0.1)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        // 缓冲量:1 个连接 × 1 属性(至多一个待写槽 + 一个 in-flight)。
        #expect(snapshot.states[token]?[.brightness] != nil)
        // 挂起期间只提交了一次(单 in-flight)。
        #expect(transport.writeCount() == 1, "挂起期间不得重复提交,实际 \(transport.writeCount())")
    }

    // MARK: - 7.4 终态确认

    /// 写后延迟确认:回读到目标值(量化容差内) → verified。
    @Test func confirmationSucceedsWhenReadMatchesTarget() async throws {
        let transport = FakeDDCTransport()
        transport.setReadReply(current: 60, max: 100)
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 60)
        // 推进到确认回读触发(0.3s)。
        clock.advance(by: 0.4)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        let state = snapshot.states[token]?[.brightness]
        #expect(state?.writeStatus == .verified, "回读匹配应置 verified")
        #expect(state?.desired == nil, "确认后清除目标")
    }

    /// 偏差 1 raw unit 视为量化容差内。
    @Test func confirmationAllowsOneRawUnitTolerance() async throws {
        let transport = FakeDDCTransport()
        // max=255,目标 50% → raw 128;回读 raw 127 → 50.196% vs 50% 差 0.196 ≤ 0.5。
        transport.setReadReply(current: 127, max: 255)
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 50)
        clock.advance(by: 0.4)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        #expect(snapshot.states[token]?[.brightness]?.writeStatus == .verified)
    }

    /// 持续不一致:确认用尽后保留未确认与真实读数,不伪造成功。
    @Test func confirmationPersistentMismatchKeepsUnverified() async throws {
        let transport = FakeDDCTransport()
        // 目标 80,回读一直是 50(显示器不响应写)。
        transport.setReadReply(current: 50, max: 100)
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let token = UUID()
        engine.replaceConnections([makeConnection(token: token)])
        await settle(engine)

        await runWrite(engine, clock: clock, token: token, control: .brightness, value: 80)
        // 推进足够长,让两次确认重试(0.3 + 0.5 + 0.5)全部执行。
        clock.advance(by: 5.0)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        let state = snapshot.states[token]?[.brightness]
        #expect(state?.writeStatus == .sentUnverified, "持续不一致不能伪造成功")
        #expect(state?.observed == 50, "保留真实读数")
    }

    /// 连接更换:旧连接的确认不作用于新连接。
    @Test func confirmationDoesNotLeakAcrossConnections() async throws {
        let transport = FakeDDCTransport()
        transport.setReadReply(current: 50, max: 100)
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let oldToken = UUID()
        engine.replaceConnections([makeConnection(token: oldToken)])
        await settle(engine)

        await runWrite(engine, clock: clock, token: oldToken, control: .brightness, value: 70)
        // 确认定时器已排(0.3s),但此刻连接被替换。
        let newToken = UUID()
        engine.replaceConnections([makeConnection(token: newToken)])
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)

        let snapshot = await engine.__snapshotForTesting()
        #expect(snapshot.states[newToken]?.isEmpty == true, "确认不应写入新连接")
        #expect(snapshot.states[oldToken] == nil, "旧连接状态已清理")
    }
}
