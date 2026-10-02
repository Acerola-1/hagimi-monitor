import Combine
import Foundation

/// 运动只延迟界面发布，同一数据切片保留最新动作；采样与统计在门控之外继续执行。
@MainActor
final class PanelPublicationGate {
    private struct Pending {
        let order: UInt
        let apply: () -> Void
    }
    private var pending: [String: Pending] = [:]
    private var deadline = Date.distantPast
    private var generation: UInt = 0
    private var order: UInt = 0
    private var timer: AnyCancellable?
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> AnyCancellable

    init(now: @escaping () -> Date = Date.init,
         schedule: ((TimeInterval, @escaping () -> Void) -> AnyCancellable)? = nil) {
        self.now = now
        self.schedule = schedule ?? { delay, callback in
            let work = DispatchWorkItem(block: callback)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return AnyCancellable { work.cancel() }
        }
    }

    func pause(until deadline: Date) {
        self.deadline = deadline
        if !pending.isEmpty { reschedule() }
    }

    func submit(key: String, _ apply: @escaping () -> Void) {
        guard now() < deadline else {
            // 主队列延迟可能使新结果先于到期回调到达；旧的同切片结果已经失效。
            pending.removeValue(forKey: key)
            if !pending.isEmpty || timer != nil { resume() }
            apply()
            return
        }
        order &+= 1
        pending[key] = Pending(order: order, apply: apply)
        if timer == nil { reschedule() }
    }

    func resume() {
        deadline = .distantPast
        generation &+= 1
        timer?.cancel(); timer = nil
        let actions = pending.values.sorted { $0.order < $1.order }
        pending.removeAll()
        for action in actions { action.apply() }
    }

    private func reschedule() {
        generation &+= 1
        let token = generation
        timer?.cancel(); timer = nil
        let delay = max(0, deadline.timeIntervalSince(now()))
        timer = schedule(delay) { [weak self] in
            guard let self, self.generation == token else { return }
            self.timer = nil
            if self.now() < self.deadline { self.reschedule() }
            else { self.resume() }
        }
    }
}
