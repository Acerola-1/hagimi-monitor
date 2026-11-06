import Foundation

/// 全部物理句柄消失时，仅重建显示器电源周期，不向旧编号写配置或重置用户布局。
actor DisplayConnectionRediscovery {
    private var inFlight: Task<Bool, Never>?
    private var lastAttempt = -Double.infinity
    private let clock: @Sendable () -> TimeInterval
    private let sleepDisplays: @Sendable () async -> Bool
    private let settle: @Sendable () async -> Void
    private let wakeDisplays: @Sendable () async -> Bool

    init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         sleepDisplays: @escaping @Sendable () async -> Bool = {
             await DisplayConnectionRediscovery.run("/usr/bin/pmset", ["displaysleepnow"])
         },
         settle: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(3)) },
         wakeDisplays: @escaping @Sendable () async -> Bool = {
             guard !DDCEnvironmentGate.shared.isSystemSleeping,
                   !DDCEnvironmentGate.shared.isShuttingDown,
                   DisplayConnectionBridge.lidIsClosed() == false else { return false }
             return await DisplayConnectionRediscovery.run("/usr/bin/caffeinate", ["-u", "-t", "2"])
         }) {
        self.clock = clock; self.sleepDisplays = sleepDisplays
        self.settle = settle; self.wakeDisplays = wakeDisplays
    }

    func recover(allowed: @escaping @Sendable () -> Bool) async -> Bool {
        if let inFlight { return await inFlight.value }
        guard clock() - lastAttempt >= 30, allowed() else { return false }
        lastAttempt = clock()
        let task = Task { [sleepDisplays, settle, wakeDisplays] in
            guard allowed() else { return false }
            DisplayConnectionDiagnostics.trace("rediscovery display sleep starting")
            // 独立任务确保调用方被拓扑通知取消后，已开始的屏幕睡眠仍有配对唤醒。
            let slept = await sleepDisplays()
            await settle()
            let woke = await wakeDisplays()
            DisplayConnectionDiagnostics.trace("rediscovery display wake completed sleep=\(slept) wake=\(woke)")
            // 返回“已尝试”，结果仍由新鲜拓扑确认；同一无输出故障不循环电源操作。
            return true
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private nonisolated static func run(_ path: String, _ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
