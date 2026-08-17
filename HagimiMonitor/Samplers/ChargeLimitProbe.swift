import Foundation

/// 系统充电上限(%)探针。
///
/// 数据源分级:macOS 26.4+ 的充电上限(80/85/90/95/100 五档)与优化电池
/// 充电均由 powerd 管理。部分系统版本的 IORegistry 不向用户态暴露上限键
/// (macOS 27 实测 AppleSmartBattery 子树无 ChargeLimit),`pmset -g battlimit`
/// 是同一数据的公开读通道:chargeSocLimitSoc 给出当前生效上限,
/// Terminated = 0 表示策略仍在执行。
///
/// 成本与缓存:pmset 为常驻进程调用、毫秒级返回;结果缓存 60s,调用发生
/// 在采样后台队列,不触主线程。失败/无数据一律返 nil,UI 显"--"。
final class ChargeLimitProbe {
    private static let cacheInterval: TimeInterval = 60
    /// pmset 正常毫秒级返回;超时则终止进程并返 nil。
    private static let probeTimeout: DispatchTimeInterval = .seconds(4)

    private let lock = NSLock()
    private var cache: (limit: Int?, timestamp: Date)?

    /// 当前生效的充电上限(%);无策略或读取失败返 nil。
    func limit() -> Int? {
        lock.lock()
        let cached = cache
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.timestamp) < Self.cacheInterval {
            return cached.limit
        }
        let fresh = probe()
        lock.lock()
        cache = (fresh, Date())
        lock.unlock()
        return fresh
    }

    private func probe() -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g", "battlimit"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        // 读输出放后台线程,信号量等待,超时终止进程并放弃本次结果。
        nonisolated(unsafe) var output: Data?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }

        if done.wait(timeout: .now() + Self.probeTimeout) == .timedOut {
            task.terminate()
            return nil
        }
        task.waitUntilExit()

        guard task.terminationStatus == 0, let output,
              let text = String(data: output, encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }

    /// 输出为若干策略块(每块以 "{" 开始、"}" 结束);取第一个
    /// Terminated = 0 且含有效 chargeSocLimitSoc 的块。
    private func parse(_ text: String) -> Int? {
        var terminated = true
        var soc: Int?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("{") {
                terminated = true
                soc = nil
            } else if line.hasPrefix("}") {
                if !terminated, let soc { return soc }
            } else if line.hasPrefix("Terminated") {
                terminated = line.hasSuffix("= 1;")
            } else if line.hasPrefix("chargeSocLimitSoc") {
                let digits = line.filter(\.isNumber)
                soc = Int(digits)
            }
        }
        return nil
    }
}
