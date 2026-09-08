import Testing
@testable import HagimiMonitorDirect
import CoreGraphics
import Foundation

/// 端到端编排测试(11.1):用脚本化 fake 后端串起完整流程,
/// 不触碰真实显示器。
/// 发现→调节→外部改值→重配置→重放→断开→编号复用。
struct DisplayControlIntegrationTests {
    private func makeConnection(token: UUID, displayID: CGDirectDisplayID, serial: String) -> DisplayConnection {
        DisplayConnection(
            token: token,
            displayID: displayID,
            identity: DisplayIdentity(vendorID: 0x1234, productID: 0x5678, serialNumber: serial, edidUUID: nil, isBuiltIn: false),
            service: DDCServiceHandle(identity: "svc-\(serial)", chipAddress: 0x37),
            isUserBound: false
        )
    }

    private func settle(_ engine: DisplayControlEngine) async {
        await engine.__waitForIdleForTesting()
    }

    private func write(
        _ engine: DisplayControlEngine, clock: VirtualMonotonicClock,
        token: UUID, value: Double
    ) async {
        await settle(engine)
        engine.enqueueWrite(token: token, control: .brightness, value: value, final: true)
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)
    }

    /// 完整流程:发现两台 → 各自调节 → 外部改 A 的值 → A 重配置抑制 →
    /// 恢复重放 → 断开 B → A 编号复用为不同设备。
    @Test func fullLifecycleOrchestration() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)

        // 发现:两台显示器。
        let tokenA = UUID()
        let tokenB = UUID()
        engine.replaceConnections([makeConnection(token: tokenA, displayID: 1, serial: "A"), makeConnection(token: tokenB, displayID: 2, serial: "B")])
        await settle(engine)

        // 各自调节。
        await write(engine, clock: clock, token: tokenA, value: 60)
        await write(engine, clock: clock, token: tokenB, value: 30)
        #expect(transport.writeCount() == 2)
        #expect(transport.writes.contains { $0.value == 60 })
        #expect(transport.writes.contains { $0.value == 30 })

        // 外部把 A 改成 80:读回观测到。
        transport.setReadReply(current: 80, max: 100)
        await settle(engine)
        engine.enqueueRead(token: tokenA, controls: [.brightness])
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)

        // 用户再设 A 为 50(外部改值后设回,永久去重会吞掉——必须再发)。
        await write(engine, clock: clock, token: tokenA, value: 50)
        #expect(transport.writes.filter { $0.value == 50 }.count >= 1)

        // A 重配置抑制:设 40 被抑制。
        var gateSuppressed = true
        engine.setGateProvider { gateSuppressed }
        await settle(engine)
        await write(engine, clock: clock, token: tokenA, value: 40)
        let beforeReplay = transport.writeCount()

        // 门禁解除:重放最新目标 40。
        gateSuppressed = false
        await settle(engine)
        engine.handleGateRecovery()
        await settle(engine)
        clock.advance(by: 0.5)
        await settle(engine)
        #expect(transport.writeCount() > beforeReplay, "恢复后重放最新目标")
        #expect(transport.writes.last?.value == 40)

        // 断开 B:旧连接不再接收写入。
        engine.replaceConnections([makeConnection(token: tokenA, displayID: 1, serial: "A")])
        await settle(engine)

        // 编号复用:B 的编号(2)被新设备 C 复用;旧 tokenB 的写不作用于新屏。
        let tokenC = UUID()
        engine.replaceConnections([
            makeConnection(token: tokenA, displayID: 1, serial: "A"),
            makeConnection(token: tokenC, displayID: 2, serial: "C"),
        ])
        await settle(engine)
        // 旧 tokenB 的任何残留写被丢弃。
        let snapshot = await engine.__snapshotForTesting()
        #expect(snapshot.states[tokenB] == nil, "旧连接状态清理")
        #expect(snapshot.connections.contains { $0.token == tokenC })
    }

    /// 资源有界:整条流程后引擎缓冲不随操作次数膨胀。
    @Test func resourcesStayBoundedThroughLifecycle() async throws {
        let transport = FakeDDCTransport()
        let clock = VirtualMonotonicClock()
        let engine = DisplayControlEngine(clock: clock, transport: transport)
        let tokenA = UUID()
        engine.replaceConnections([makeConnection(token: tokenA, displayID: 1, serial: "A")])
        await settle(engine)

        for i in 0..<50 {
            await write(engine, clock: clock, token: tokenA, value: Double(i % 100))
        }
        let snapshot = await engine.__snapshotForTesting()
        // 待写槽有界:只保留最新目标。
        #expect(snapshot.states[tokenA]?[.brightness] != nil)
        #expect(transport.writeCount() <= 100, "50 次写不应产生无限缓冲")
    }
}
