import Testing
@testable import HagimiMonitorDirect
import Foundation

/// 门禁纯状态模型测试(D4/5.1)。
/// 核心:独立维护系统睡眠、屏幕睡眠、唤醒期限、重配置期限;更短的重配置结束
/// 不缩短唤醒抑制;旧 timer 不解除后来的睡眠。
struct GateStateModelTests {
    /// 时间单位:MonotonicInstant 以纳秒存储,这里统一用"秒"构造便于语义阅读。
    private func sec(_ s: Double) -> MonotonicInstant {
        MonotonicInstant(nanoseconds: UInt64(s * 1_000_000_000))
    }

    @Test func freshModelNotSuppressed() {
        var model = GateStateModel()
        #expect(!model.isSuppressed(at: sec(0)))
    }

    @Test func systemSleepSuppressesUntilWake() {
        var model = GateStateModel()
        model.systemSleepStarted()
        #expect(model.isSuppressed(at: sec(1)))
        model.systemWakeStarted(now: sec(1), settle: 3)
        #expect(model.isSuppressed(at: sec(2)), "唤醒沉降窗口内仍抑制")
        #expect(model.isSuppressed(at: sec(3.9)))
        #expect(!model.isSuppressed(at: sec(4.0)), "3s 沉降结束后解除")
    }

    /// 重配置 begin→complete 只影响 reconfigureUntil,不影响 wakeUntil。
    @Test func shorterReconfigureDoesNotShortenWakeSuppression() {
        var model = GateStateModel()
        model.systemSleepStarted()
        model.systemWakeStarted(now: sec(1), settle: 10)
        // 重配置 begin + 更短的 complete。
        model.reconfigureStarted(now: sec(2), safety: 5)
        model.reconfigureCompleted(now: sec(2), settle: 0.5)
        #expect(model.isSuppressed(at: sec(2.2)), "重配置结算前抑制")
        #expect(model.isSuppressed(at: sec(3)), "重配置(2.5s)已结束但唤醒沉降(11s)仍在,必须继续抑制")
        #expect(model.isSuppressed(at: sec(10.5)))
        #expect(!model.isSuppressed(at: sec(11.1)), "唤醒沉降 10s 后才解除")
    }

    /// 重配置完成只缩短自身期限,不触碰唤醒期限。
    @Test func reconfigureCompleteOnlyTouchesReconfigureUntil() {
        var model = GateStateModel()
        model.systemWakeStarted(now: sec(1), settle: 100)
        model.reconfigureStarted(now: sec(2), safety: 5)
        model.reconfigureCompleted(now: sec(2), settle: 0.5)
        model.expireDeadlines(now: sec(3))
        // 唤醒期限(101s)未到期 → 仍抑制;重配置期限(2.5s)已过期清理。
        #expect(model.isSuppressed(at: sec(3)))
    }

    /// 屏幕睡眠与唤醒。
    @Test func displaySleepAndWake() {
        var model = GateStateModel()
        model.displaySleepStarted()
        #expect(model.isSuppressed(at: sec(0)))
        model.displayWakeStarted(now: sec(0), settle: 2)
        #expect(model.isSuppressed(at: sec(1)))
        #expect(!model.isSuppressed(at: sec(2.1)))
    }

    /// 到期后再次睡眠:旧期限清理不能解除新睡眠。
    @Test func staleDeadlineDoesNotClearNewSleep() {
        var model = GateStateModel()
        model.reconfigureStarted(now: sec(0), safety: 5)
        model.expireDeadlines(now: sec(6))
        #expect(!model.isSuppressed(at: sec(6)))
        model.systemSleepStarted()
        #expect(model.isSuppressed(at: sec(6.1)), "新睡眠必须继续抑制,旧期限清理无效")
    }

    /// begin-only safety 到期后自动解除,无需完成回调。
    @Test func beginOnlySafetyExpiryReleases() {
        var model = GateStateModel()
        model.reconfigureStarted(now: sec(0), safety: 5)
        model.expireDeadlines(now: sec(6))
        #expect(!model.isSuppressed(at: sec(6)))
        model.expireDeadlines(now: sec(6))
        #expect(model.nextDeadline() == nil, "过期期限清理后不应再返回过去时刻")
    }
}
