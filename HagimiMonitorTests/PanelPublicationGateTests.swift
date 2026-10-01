import Combine
import Foundation
import Testing
@testable import HagimiMonitorDirect

@MainActor
struct PanelPublicationGateTests {
    private final class Scheduler {
        var time = Date(timeIntervalSince1970: 100)
        var callbacks: [() -> Void] = []
        var delays: [TimeInterval] = []
        func schedule(_ delay: TimeInterval, _ callback: @escaping () -> Void) -> AnyCancellable {
            callbacks.append(callback); delays.append(delay)
            // 模拟一个会送达已取消回调的调度器，验证门控自身的代际检查。
            return AnyCancellable {}
        }
        func gate() -> PanelPublicationGate { PanelPublicationGate(now: { self.time }, schedule: schedule) }
    }

    @Test func coalescesEachSliceAndKeepsLatestChronologicalOrder() {
        let scheduler = Scheduler(); let gate = scheduler.gate()
        var values: [String] = []
        gate.pause(until: scheduler.time.addingTimeInterval(1))
        gate.submit(key: "modules") { values.append("old modules") }
        gate.submit(key: "fan") { values.append("fan") }
        gate.submit(key: "modules") { values.append("latest modules") }
        #expect(values.isEmpty)
        #expect(scheduler.callbacks.count == 1)
        scheduler.time += 1
        scheduler.callbacks[0]()
        #expect(values == ["fan", "latest modules"])
    }

    @Test func repeatedReversalCannotReleaseDataAtAnOldDeadline() {
        let scheduler = Scheduler(); let gate = scheduler.gate()
        var updates = 0
        gate.pause(until: scheduler.time.addingTimeInterval(1))
        gate.submit(key: "modules") { updates += 1 }
        for _ in 0..<5 {
            scheduler.time += 0.2
            gate.pause(until: scheduler.time.addingTimeInterval(1))
        }
        for callback in scheduler.callbacks { callback() }
        #expect(updates == 0)
        scheduler.time += 1
        scheduler.callbacks.last?()
        #expect(updates == 1)
    }

    @Test func hiddenResumeFlushesOnceAndStaleCallbackCannotWriteNewSession() {
        let scheduler = Scheduler(); let gate = scheduler.gate()
        var values: [Int] = []
        gate.pause(until: scheduler.time.addingTimeInterval(1))
        gate.submit(key: "modules") { values.append(1) }
        let old = scheduler.callbacks[0]
        gate.resume()
        gate.pause(until: scheduler.time.addingTimeInterval(2))
        gate.submit(key: "modules") { values.append(2) }
        old()
        #expect(values == [1])
        scheduler.time += 2
        scheduler.callbacks.last?()
        #expect(values == [1, 2])
    }

    @Test func schedulerCallbacksDoNotRetainGate() {
        let scheduler = Scheduler()
        var gate: PanelPublicationGate? = scheduler.gate()
        weak var weakGate = gate
        gate?.pause(until: scheduler.time.addingTimeInterval(1))
        gate?.submit(key: "modules") {}
        gate = nil
        #expect(weakGate == nil)
        scheduler.callbacks[0]()
    }

    @Test func newResultArrivingBeforeDelayedTimerCannotBeOverwritten() {
        let scheduler = Scheduler(); let gate = scheduler.gate()
        var values: [Int] = []
        gate.pause(until: scheduler.time.addingTimeInterval(1))
        gate.submit(key: "modules") { values.append(1) }
        let old = scheduler.callbacks[0]
        scheduler.time += 2
        gate.submit(key: "modules") { values.append(2) }
        old()
        #expect(values == [2])
    }
}
