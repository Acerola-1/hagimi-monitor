import Foundation
import Testing
@testable import HagimiMonitorDirect

/// E01–E06：持续资格由有效覆盖决定，恢复必须有证据，中断不补时长。
/// 时间由注入推进，测试不真实等待。
struct AppResourceEventStateMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func high(_ seconds: TimeInterval, value: Double = 70, interval: TimeInterval? = nil) -> AppResourceEventStateMachine.Observation {
        AppResourceEventStateMachine.Observation(
            signal: .high(value: value),
            at: at(seconds),
            coveredInterval: interval.map { DateInterval(start: at(seconds), duration: $0) }
        )
    }

    private func low(_ seconds: TimeInterval) -> AppResourceEventStateMachine.Observation {
        AppResourceEventStateMachine.Observation(signal: .low(value: 5), at: at(seconds))
    }

    private func unknown(_ seconds: TimeInterval) -> AppResourceEventStateMachine.Observation {
        AppResourceEventStateMachine.Observation(signal: .unknown, at: at(seconds))
    }

    // MARK: - E01 首个瞬时样本不增加一分钟

    @Test func firstInstantSampleAddsNoDuration() {
        let first = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0))
        #expect(first.state.isRunning)
        #expect(first.state.continuousHighSeconds == 0)
        #expect(first.state.isConfirmed == false)
        #expect(first.finishedEvent == nil)
    }

    // MARK: - 两次瞬时观测最多 60 秒，未达 120 秒资格

    @Test func twoInstantSamplesReachOnlySixtySeconds() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        let second = AppResourceEventStateMachine.reduce(state: state, observation: high(60, value: 80))
        state = second.state
        #expect(state.continuousHighSeconds == 60)
        #expect(state.isConfirmed == false)   // 120 秒资格未达到
        #expect(state.highObservationCount == 2)
    }

    @Test func threeInstantSamplesConfirmAtOneHundredTwentySeconds() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        let third = AppResourceEventStateMachine.reduce(state: state, observation: high(120))
        #expect(third.state.continuousHighSeconds == 120)
        #expect(third.state.isConfirmed)
    }

    @Test func averageUsesValidSecondsNotSampleCount() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0, value: 100)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60, value: 20)).state
        // 首个样本没有覆盖秒数，不参与加权；只有 60 秒的 20% 计入均值。
        #expect(state.averageUsage == 20)
        #expect(state.peakUsage == 100)
    }

    // MARK: - E02 有效低值确认恢复

    @Test func lowObservationConfirmsRecovery() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        let third = AppResourceEventStateMachine.reduce(state: state, observation: high(120))
        state = third.state
        #expect(state.isConfirmed)

        let recovered = AppResourceEventStateMachine.reduce(state: state, observation: low(180))
        let outcome = try? #require(recovered.finishedEvent)
        #expect(outcome?.reason == .recovered)
        #expect(outcome?.continuousHighSeconds == 120)
        // 结束端点停在最后一次有效高覆盖，不外推到低值观测时刻。
        #expect(outcome?.endedAt == at(120))
    }

    @Test func unconfirmedSpikeIsNotRecordedAsAnEvent() {
        let first = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0))
        let ended = AppResourceEventStateMachine.reduce(state: first.state, observation: low(30))
        #expect(ended.finishedEvent == nil)
    }

    // MARK: - E04 长中断

    @Test func longGapInterruptsAndDoesNotAccumulateMissingTime() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(120)).state

        // 下一次观测在 3600 秒，远超 90 秒允许间隔。
        let late = AppResourceEventStateMachine.reduce(state: state, observation: high(3600, value: 90))
        let outcome = try? #require(late.finishedEvent)
        #expect(outcome?.reason == .observationGap)
        #expect(outcome?.endedAt == at(120))          // 停在最后有效覆盖
        // 59 分钟没有被补进来。
        #expect((outcome?.continuousHighSeconds ?? 0) < 200)
        // 新样本建立新基线，不延续旧事件。
        #expect(late.state.continuousHighSeconds == 0)
        #expect(late.state.startedAt == at(3600))
    }

    // MARK: - E05 未知不宣告恢复

    @Test func unknownDoesNotAnnounceRecovery() {
        let state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        let stillUnknown = AppResourceEventStateMachine.reduce(state: state, observation: unknown(60))
        // 未超过允许间隔：既不算高，也不算已恢复。
        #expect(stillUnknown.finishedEvent == nil)
        #expect(stillUnknown.state.isRunning)
        #expect(stillUnknown.state.continuousHighSeconds == 0)
    }

    @Test func unknownBeyondGapEndsAsInterruptedNotRecovered() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(120)).state

        let dropped = AppResourceEventStateMachine.reduce(state: state, observation: unknown(600))
        let outcome = try? #require(dropped.finishedEvent)
        #expect(outcome?.reason == .observationGap)
        #expect(outcome?.reason != .recovered)
    }

    // MARK: - E06 生命周期结束原因

    @Test func processExitEndsAsInterruptedReason() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(120)).state

        let ended = AppResourceEventStateMachine.reduce(
            state: state,
            observation: AppResourceEventStateMachine.Observation(signal: .ended(reason: .processExited), at: at(150))
        )
        let outcome = try? #require(ended.finishedEvent)
        #expect(outcome?.reason == .processExited)
        #expect(outcome?.endedAt == at(120))
    }

    @Test func suspendEndsOngoingEvent() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(120)).state

        let suspended = AppResourceEventStateMachine.reduce(
            state: state,
            observation: AppResourceEventStateMachine.Observation(signal: .ended(reason: .suspended), at: at(130))
        )
        #expect(suspended.finishedEvent?.reason == .suspended)
        #expect(suspended.state.isRunning == false)
    }

    @Test func pidReuseEndsPreviousEvidence() {
        var state = AppResourceEventStateMachine.reduce(state: .init(), observation: high(0)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(60)).state
        state = AppResourceEventStateMachine.reduce(state: state, observation: high(120)).state

        let replaced = AppResourceEventStateMachine.reduce(
            state: state,
            observation: AppResourceEventStateMachine.Observation(signal: .ended(reason: .replaced), at: at(125))
        )
        #expect(replaced.finishedEvent?.reason == .replaced)
    }

    // MARK: - 来源给出真实区间时不靠间隔估算

    @Test func explicitCoverageIntervalIsPreferredOverGapEstimate() {
        // 观测间隔 60 秒，但来源声明的覆盖区间是 30 秒。
        let first = AppResourceEventStateMachine.reduce(
            state: .init(), observation: high(0, value: 60, interval: 30))
        var state = first.state
        let second = AppResourceEventStateMachine.reduce(
            state: state, observation: high(60, value: 60, interval: 30))
        state = second.state
        #expect(state.continuousHighSeconds == 30)
    }

    // MARK: - E03 多指标并集

    @Test func overlappingMetricIntervalsCountOnceForTheApp() {
        let cpu = (start: at(0), end: at(120))
        let memory = (start: at(60), end: at(180))
        let union = AppResourceEventStateMachine.unionSeconds(of: [cpu, memory])
        #expect(union == 180)     // 不是 120 + 120 = 240

        let disjoint = AppResourceEventStateMachine.unionSeconds(of: [
            (start: at(0), end: at(60)),
            (start: at(120), end: at(180)),
        ])
        #expect(disjoint == 120)
    }

    @Test func unionIgnoresEmptyAndUnsortedIntervals() {
        let union = AppResourceEventStateMachine.unionSeconds(of: [
            (start: at(60), end: at(120)),
            (start: at(0), end: at(60)),
            (start: at(200), end: at(200)),
        ])
        #expect(union == 120)
        #expect(AppResourceEventStateMachine.unionSeconds(of: []) == 0)
    }
}
