import Testing
@testable import HagimiMonitor
import CoreGraphics
import Foundation

/// 门禁是本模块可靠性的第一道防线:在睡眠/唤醒/重配置这些内核 I2C 调用极易 hang
/// 的危险窗口内直接抑制所有 DDC I/O。用可注入的短时长 + 手动触发事件验证状态机,
/// 不依赖真实系统通知,也不注册系统观察者(registerSystemObservers: false)。
struct DDCEnvironmentGateTests {
    private func makeGate(wake: TimeInterval = 0.3, settle: TimeInterval = 0.3, safety: TimeInterval = 5) -> DDCEnvironmentGate {
        DDCEnvironmentGate(
            wakeSuppressSeconds: wake,
            reconfigureSettleSeconds: settle,
            reconfigureSafetySeconds: safety,
            registerSystemObservers: false
        )
    }

    @Test func freshGateIsNotSuppressed() {
        let gate = makeGate()
        #expect(gate.isSuppressed == false)
    }

    @Test func sleepSuppresses() {
        let gate = makeGate()
        gate.handleWillSleep()
        #expect(gate.isSuppressed == true)
    }

    /// 唤醒后应立即保持抑制(显示器需要时间恢复),并在 wakeSuppressSeconds 后自动解除。
    @Test func wakeSuppressesThenReleasesAfterDelay() async throws {
        let gate = makeGate(wake: 0.3)
        gate.handleWillSleep()
        gate.handleDidWake()
        // asleep 已清除,但仍处于唤醒沉降窗口内。
        #expect(gate.isSuppressed == true)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(gate.isSuppressed == false)
    }

    /// 重配置 begin(beginConfigurationFlag)期间必须抑制。
    @Test func reconfigureBeginSuppresses() {
        let gate = makeGate()
        gate.handleReconfigure(flags: .beginConfigurationFlag)
        #expect(gate.isSuppressed == true)
    }

    /// 重配置完成后仍抑制一小段沉降时间,随后自动解除。
    @Test func reconfigureCompleteReleasesAfterSettle() async throws {
        let gate = makeGate(settle: 0.3)
        gate.handleReconfigure(flags: .beginConfigurationFlag)
        // 完成回调(非 begin):清除 reconfiguring,进入沉降窗口。
        gate.handleReconfigure(flags: .setModeFlag)
        #expect(gate.isSuppressed == true)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(gate.isSuppressed == false)
    }

    /// begin 之后即使完成回调迟迟不来,也不会永久卡死:safety 兜底时长后自动解除。
    @Test func reconfigureBeginHasSafetyTimeout() async throws {
        let gate = makeGate(safety: 0.3)
        gate.handleReconfigure(flags: .beginConfigurationFlag)
        #expect(gate.isSuppressed == true)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(gate.isSuppressed == false)
    }
}
