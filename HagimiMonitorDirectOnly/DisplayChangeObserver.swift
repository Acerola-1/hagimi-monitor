import Foundation

/// 显示器/电源变化的订阅者。实际的 CG 重配置回调与睡眠/唤醒监听已统一收敛到
/// `DDCEnvironmentGate`(避免重复注册两套 CG 回调);此类只负责把 `onChange`
/// 挂到门禁上,并在停止/析构时摘除。回调由门禁在主线程、且在抑制窗口结束后触发。
@MainActor
final class DisplayChangeObserver {
    // deinit 为非隔离上下文,需在其中摘除订阅;token 仅在主线程读写,
    // 标 nonisolated(unsafe) 以规避 Swift 6 严格并发告警(摘除操作本身线程安全)。
    private nonisolated(unsafe) var token: UUID?

    func start(onChange: @escaping () -> Void) {
        guard token == nil else { return }
        token = DDCEnvironmentGate.shared.addChangeHandler(onChange)
    }

    func stop() {
        if let token {
            DDCEnvironmentGate.shared.removeChangeHandler(token)
        }
        token = nil
    }

    deinit {
        if let token {
            DDCEnvironmentGate.shared.removeChangeHandler(token)
        }
    }
}
