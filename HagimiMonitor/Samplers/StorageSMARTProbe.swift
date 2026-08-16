import Foundation

/// S.M.A.R.T. 状态探针。
///
/// 取证结论(2026-08):IORegistry 不向用户态暴露 SMART 信息,macOS 上唯一公开
/// 通道是 `system_profiler SPNVMeDataType -json`,其中 `smart_status` 键名
/// 机器稳定、不随系统语言变化(值可能本地化,故只认语义匹配)。
///
/// 成本与缓存:system_profiler 启动约数百毫秒,绝不能随每秒采样拉起——
/// 探针结果缓存 60s;调用发生在采样后台队列,不触主线程。
/// 失败/无数据一律返 nil,UI 显"--"。
final class StorageSMARTProbe {
    private static let cacheInterval: TimeInterval = 60
    /// system_profiler 正常数百毫秒返回,但个别存储控制器无响应时可能挂起;
    /// 超过此时长终止进程并返 nil,绝不让探针卡死串行采样队列。
    private static let probeTimeout: DispatchTimeInterval = .seconds(8)

    private let lock = NSLock()
    private var cache: (status: String?, timestamp: Date)?

    /// 状态 id:"verified" / "failing";无法确定时返 nil。
    func status() -> String? {
        lock.lock()
        let cached = cache
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.timestamp) < Self.cacheInterval {
            return cached.status
        }
        let fresh = probe()
        lock.lock()
        cache = (fresh, Date())
        lock.unlock()
        return fresh
    }

    private func probe() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPNVMeDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        // readDataToEndOfFile 会阻塞到进程退出,若 system_profiler 挂起则永久不返。
        // 读输出放到后台线程,本线程用信号量等待,超时后终止进程并放弃本次结果。
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

        guard task.terminationStatus == 0,
              let output,
              let root = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any],
              let raw = findSmartStatus(in: root) else {
            return nil
        }
        return normalize(raw)
    }

    /// 值可能随系统语言本地化,只做语义匹配;无法识别的按 nil 处理。
    private func normalize(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        if lowered.contains("verif") || lowered == "ok" || lowered.contains("正常") || lowered.contains("検証済み") {
            return "verified"
        }
        if lowered.contains("fail") || lowered.contains("异常") || lowered.contains("障害") {
            return "failing"
        }
        return nil
    }

    /// 深度优先找第一个 smart_status 标量(JSON 可能嵌在控制器层)。
    private func findSmartStatus(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let value = dict["smart_status"] as? String {
                return value
            }
            for value in dict.values {
                if let found = findSmartStatus(in: value) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                if let found = findSmartStatus(in: item) {
                    return found
                }
            }
        }
        return nil
    }
}
