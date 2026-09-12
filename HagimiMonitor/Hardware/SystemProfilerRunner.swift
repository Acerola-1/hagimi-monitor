import Foundation

/// `system_profiler` 执行器:硬件清单的主力数据源。
///
/// 调用形态:`/usr/sbin/system_profiler -json -timeout 25 <DataType>`,每个 DataType
/// 一个进程。本机实测 16 个 DataType 串行约 2.1 秒(单个 0.07–0.18 s),所以
/// 「一次性读 + 长缓存」的代价可以忽略,但**绝不能挂在每秒采样路径上**——
/// 与 `StorageSMARTProbe` / `BluetoothBatterySampler` 同一取舍。
///
/// 并发:DataType 之间没有依赖,按上限 6 并发跑(参考项目的做法),把总耗时压到
/// 最慢一个进程的量级。
///
/// 失败语义:进程异常退出、超时、JSON 解析失败都返 nil;「进程成功但返回空清单」
/// 返空数组。两者必须区分——本机 `SPUSBDataType` / `SPSerialATADataType` /
/// `SPEthernetDataType` 就是「成功但空」,那不是读取失败。
final class SystemProfilerRunner {
    /// DataType → 原始条目。键名与 system_profiler 的 JSON 顶层键一致。
    typealias ItemsByType = [String: [[String: Any]]]

    /// 共享实例:报表按需生成时都用它,缓存才真的命中——每次新建实例的话,
    /// 缓存与清缓存都没有意义(一次采集内每个 DataType 只查一次)。
    static let shared = SystemProfilerRunner()

    /// 缓存窗口:硬件规格是准静态的,5 分钟内复用同一份结果,避免频繁拉起进程。
    private static let cacheInterval: TimeInterval = 300
    /// 单次超时。system_profiler 正常数百毫秒返回,个别控制器无响应时可能挂起;
    /// `-timeout 25` 是它自己的上限,这里再兜一层,超时即终止进程。
    private static let probeTimeout: DispatchTimeInterval = .seconds(20)

    private let lock = NSLock()
    private var cache: [String: (items: [[String: Any]], timestamp: Date)] = [:]

    /// 跑一个 DataType。命中缓存直接返回;失败返 nil(不写缓存,下次重试)。
    func items(for dataType: String) -> [[String: Any]]? {
        lock.lock()
        let cached = cache[dataType]
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.timestamp) < Self.cacheInterval {
            return cached.items
        }
        guard let fresh = probe(dataType) else { return nil }
        lock.lock()
        cache[dataType] = (fresh, Date())
        lock.unlock()
        return fresh
    }

    /// 并发跑一批 DataType,返回有结果的那些(失败与空清单都不进结果集)。
    /// 调用方要么在主线程之外的队列调用,要么接受它阻塞当前线程到最慢的进程结束。
    func capture(_ dataTypes: [String], maxConcurrent: Int = 6) -> ItemsByType {
        guard !dataTypes.isEmpty else { return [:] }
        let gate = DispatchSemaphore(value: max(1, maxConcurrent))
        let box = Box()
        DispatchQueue.concurrentPerform(iterations: dataTypes.count) { index in
            gate.wait()
            defer { gate.signal() }
            let dataType = dataTypes[index]
            if let items = items(for: dataType) {
                box.set(dataType, items)
            }
        }
        return box.snapshot()
    }

    // MARK: - 进程执行

    private func probe(_ dataType: String) -> [[String: Any]]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["-json", "-timeout", "25", dataType]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        // readDataToEndOfFile 会阻塞到进程退出:挂起时本线程会永久等待,
        // 所以读取放到后台队列,这里用信号量等,超时即终止进程并放弃本次结果。
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

        guard task.terminationStatus == 0, let output else { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any],
              let items = root[dataType] as? [[String: Any]] else {
            return nil
        }
        return items
    }

    /// 并发写入用的收件箱:`concurrentPerform` 的闭包不保证在主线程,写入必须加锁。
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: ItemsByType = [:]

        func set(_ key: String, _ value: [[String: Any]]) {
            lock.lock()
            storage[key] = value
            lock.unlock()
        }

        func snapshot() -> ItemsByType {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
