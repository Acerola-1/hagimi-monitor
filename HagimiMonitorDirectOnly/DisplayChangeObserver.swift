import Foundation

/// 显示器/电源变化的订阅者。实际的 CG 重配置回调与睡眠/唤醒监听已统一收敛到
/// `DDCEnvironmentGate`(避免重复注册两套 CG 回调);此类只负责把 `onChange`
/// 挂到门禁上,并在停止/析构时摘除。回调由门禁在主线程、且在抑制窗口结束后触发。
@MainActor
final class DisplayChangeObserver {
    private let cleanupBox = DisplayChangeObserverCleanupBox()

    func start(onChange: @escaping @Sendable () -> Void) {
        guard cleanupBox.token == nil else { return }
        cleanupBox.token = DDCEnvironmentGate.shared.addChangeHandler(onChange)
    }

    func stop() {
        cleanupBox.cleanup()
    }
}

/// 线程安全清理容器：在 deinit 阶段注销 DDCEnvironmentGate 的变更监听。
private nonisolated final class DisplayChangeObserverCleanupBox: @unchecked Sendable {
    var token: UUID?

    nonisolated func cleanup() {
        if let token {
            DDCEnvironmentGate.shared.removeChangeHandler(token)
        }
        self.token = nil
    }

    deinit {
        cleanup()
    }
}
