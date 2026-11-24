import Combine
import Darwin
import Foundation
import OSLog

/// 每次探针会话独立持有缓冲区；仅在 readerQueue 上访问其内容。
nonisolated private final class MetalTraceJSONBuffer: @unchecked Sendable {
    var data = Data()
}

@MainActor
protocol GameHUDMetalTraceProbing: AnyObject {
    var statsPublisher: AnyPublisher<GameHUDFPSStats?, Never> { get }
    var currentPID: pid_t? { get }
    var isRunning: Bool { get }
    var onUnexpectedExit: ((pid_t) -> Void)? { get set }
    func start(pid: pid_t)
    func stop()
}

/// 通过系统 `metalperftrace` 命令行工具监听目标 Metal 进程的上屏帧率统计。
///
/// 直接读取系统报告的呈现 FPS；帧间隔统计可能缺失，此时不估算帧时间与 1% Low。
/// 不使用屏幕录制或像素捕获。
@MainActor
final class MetalPerfTraceMeter: ObservableObject, GameHUDMetalTraceProbing {

    typealias ProcessTreeProvider = @Sendable (pid_t) -> [pid_t]
    typealias ProbeLauncher = @MainActor ([pid_t]) -> Bool

    private nonisolated static let executablePath = "/usr/bin/metalperftrace"
    private nonisolated static let maximumMonitoredPIDs = 8
    private static let defaultPIDRefreshInterval: Duration = .seconds(3)

    nonisolated static var isSystemProbeAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executablePath)
    }

    struct SecondSample: Sendable {
        let timestamp: TimeInterval
        let fps: Double
        let frameCount: Int
        let avgMs: Double?
        let stdDevMs: Double?
        let maxMs: Double?
        let minMs: Double?
        let totalMs: Double?
    }

    @Published private(set) var stats: GameHUDFPSStats?
    var statsPublisher: AnyPublisher<GameHUDFPSStats?, Never> { $stats.eraseToAnyPublisher() }
    private var process: Process?
    private var pipe: Pipe?
    private var isCustomProbeRunning = false
    private(set) var currentPID: pid_t?
    private(set) var monitoredPIDs: [pid_t] = []
    var isRunning: Bool { (process?.isRunning == true) || isCustomProbeRunning }
    var onUnexpectedExit: ((pid_t) -> Void)?
    private var samples: [SecondSample] = []
    private static let windowDuration: TimeInterval = 60.0
    private static let sampleTimeout: Duration = .seconds(3)
    private var sampleTimeoutTask: Task<Void, Never>?
    private var pidRefreshTask: Task<Void, Never>?
    private var generation = 0
    private let readerQueue = DispatchQueue(label: "gamehud.metalperftrace.reader", qos: .utility)
    private let processTreeProvider: ProcessTreeProvider
    private let pidRefreshInterval: Duration
    private let customLauncher: ProbeLauncher?

    init(
        processTreeProvider: @escaping ProcessTreeProvider = { MetalPerfTraceMeter.targetProcessTreePIDs(rootPID: $0) },
        pidRefreshInterval: Duration = MetalPerfTraceMeter.defaultPIDRefreshInterval,
        customLauncher: ProbeLauncher? = nil
    ) {
        self.processTreeProvider = processTreeProvider
        self.pidRefreshInterval = pidRefreshInterval
        self.customLauncher = customLauncher
    }

    /// 收集目标进程及其子进程 PID（用于支持启动器/转译器/多进程渲染架构）。
    nonisolated static func targetProcessTreePIDs(rootPID: pid_t, limit: Int = maximumMonitoredPIDs) -> [pid_t] {
        guard rootPID > 0, limit > 0 else { return [] }
        var result: [pid_t] = [rootPID]
        var seen: Set<pid_t> = [rootPID]
        var cursor = 0

        while cursor < result.count, result.count < limit {
            let parent = result[cursor]
            cursor += 1
            let estimated = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parent), nil, 0)
            guard estimated > 0 else { continue }
            let capacity = max(Int(estimated) / MemoryLayout<pid_t>.size + 8, 16)
            var buffer = [pid_t](repeating: 0, count: capacity)
            let bytes = proc_listpids(
                UInt32(PROC_PPID_ONLY),
                UInt32(parent),
                &buffer,
                Int32(buffer.count * MemoryLayout<pid_t>.size)
            )
            guard bytes > 0 else { continue }
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            for child in buffer.prefix(count).sorted() {
                guard child > 0, seen.insert(child).inserted else { continue }
                result.append(child)
                if result.count >= limit { break }
            }
        }
        return result
    }

    private static func probePIDs(rootPID: pid_t, discovered: [pid_t]) -> [pid_t] {
        let children = Set(discovered.filter { $0 > 0 && $0 != rootPID })
        return [rootPID] + children.sorted().prefix(maximumMonitoredPIDs - 1)
    }

    /// 启动对指定 PID 进程及其子进程的 Metal 帧统计监听。
    func start(pid: pid_t) {
        guard pid > 0 else { return }
        if currentPID == pid, isRunning {
            return
        }

        let pids = Self.probePIDs(rootPID: pid, discovered: processTreeProvider(pid))
        launchProbe(rootPID: pid, pids: pids, preserveSamples: false)
    }

    private func launchProbe(rootPID: pid_t, pids: [pid_t], preserveSamples: Bool) {
        tearDownActiveProbe()
        let sessionGeneration = generation

        if !preserveSamples {
            samples.removeAll()
            stats = nil
        }

        if let customLauncher {
            currentPID = rootPID
            monitoredPIDs = pids
            guard customLauncher(pids) else {
                reportProbeFailure(rootPID: rootPID)
                return
            }
            isCustomProbeRunning = true
            schedulePIDRefresh(for: sessionGeneration, rootPID: rootPID)
            return
        }

        let executablePath = Self.executablePath
        guard Self.isSystemProbeAvailable else {
            AppLogger.diagnostics.info("metalperftrace not executable at \(executablePath, privacy: .public)")
            stop()
            return
        }

        currentPID = rootPID
        monitoredPIDs = pids

        var arguments = ["listen", "--json", "--interval", "1"]
        for targetPID in pids {
            arguments.append("--pid")
            arguments.append("\(targetPID)")
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = arguments

        let stdoutPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = FileHandle.nullDevice

        self.pipe = stdoutPipe
        self.process = p

        let buffer = MetalTraceJSONBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self, readerQueue] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                readerQueue.async {
                    try? handle.close()
                }
                return
            }
            readerQueue.async { [weak self] in
                guard let self else { return }
                buffer.data.append(data)

                let jsonObjects = Self.extractJSONObjects(from: &buffer.data)
                for objData in jsonObjects {
                    if let jsonStr = String(data: objData, encoding: .utf8),
                       let sample = Self.parseSample(from: jsonStr) {
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == sessionGeneration else { return }
                            self.recordSample(sample)
                        }
                    }
                }

                if buffer.data.count > 512 * 1024 {
                    buffer.data.removeAll(keepingCapacity: false)
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == sessionGeneration else { return }
                self.reportProbeFailure(rootPID: rootPID)
            }
        }

        do {
            try p.run()
            scheduleSampleTimeout(for: sessionGeneration)
            schedulePIDRefresh(for: sessionGeneration, rootPID: rootPID)
            AppLogger.diagnostics.info("metalperftrace started for pids=\(pids.map(String.init).joined(separator: ","), privacy: .public)")
            // 动态抑制 Apple 官方 HUD 浮层，避免系统自带 HUD 叠加弹出
            DispatchQueue.global(qos: .utility).async {
                let setup = Process()
                setup.executableURL = URL(fileURLWithPath: executablePath)
                var setupArgs = ["setup", "--disable", "hud"]
                for targetPID in pids {
                    setupArgs.append("--pid")
                    setupArgs.append("\(targetPID)")
                }
                setup.arguments = setupArgs
                setup.standardOutput = FileHandle.nullDevice
                setup.standardError = FileHandle.nullDevice
                try? setup.run()
                setup.waitUntilExit()
            }
        } catch {
            AppLogger.diagnostics.error("Failed to run metalperftrace: \(error, privacy: .public)")
            reportProbeFailure(rootPID: rootPID)
        }
    }

    private func reportProbeFailure(rootPID: pid_t) {
        stop()
        onUnexpectedExit?(rootPID)
    }

    /// 定期复核目标进程树；监听集合变化时更新探针，并保留当前游戏会话的采样窗口。
    private func schedulePIDRefresh(for sessionGeneration: Int, rootPID: pid_t) {
        pidRefreshTask?.cancel()
        let interval = pidRefreshInterval
        let provider = processTreeProvider
        pidRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self,
                      self.generation == sessionGeneration,
                      self.currentPID == rootPID,
                      self.isRunning else { return }
                let discovered = await Task.detached(priority: .utility) {
                    provider(rootPID)
                }.value
                guard !Task.isCancelled,
                      self.generation == sessionGeneration,
                      self.currentPID == rootPID,
                      self.isRunning else { return }
                let pids = Self.probePIDs(rootPID: rootPID, discovered: discovered)
                guard pids != self.monitoredPIDs else { continue }
                self.launchProbe(rootPID: rootPID, pids: pids, preserveSamples: true)
                return
            }
        }
    }

    private func tearDownActiveProbe() {
        generation += 1
        sampleTimeoutTask?.cancel()
        sampleTimeoutTask = nil
        pidRefreshTask?.cancel()
        pidRefreshTask = nil
        isCustomProbeRunning = false
        if let pipe {
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            readerQueue.async {
                try? handle.close()
            }
        }
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        pipe = nil
    }

    /// 停止监听并释放外部进程与流。
    func stop() {
        tearDownActiveProbe()
        samples.removeAll()
        stats = nil
        currentPID = nil
        monitoredPIDs = []
    }

    private func scheduleSampleTimeout(for sessionGeneration: Int) {
        sampleTimeoutTask?.cancel()
        sampleTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.sampleTimeout)
            guard !Task.isCancelled, let self, self.generation == sessionGeneration else { return }
            self.samples.removeAll()
            self.stats = nil
        }
    }

    // MARK: - JSON 流式解析

    /// 从字节缓冲区中提取闭合的 JSON 对象，避免多字节 UTF-8 跨块拆包丢数据。
    nonisolated static func extractJSONObjects(from buffer: inout Data) -> [Data] {
        var objects: [Data] = []
        var startIndex: Data.Index?
        var depth = 0
        var inString = false
        var escape = false

        var currentIndex = buffer.startIndex
        while currentIndex < buffer.endIndex {
            let byte = buffer[currentIndex]
            if escape {
                escape = false
            } else if byte == 0x5C && inString { // '\'
                escape = true
            } else if byte == 0x22 { // '"'
                inString.toggle()
            } else if !inString {
                if byte == 0x7B { // '{'
                    if depth == 0 {
                        startIndex = currentIndex
                    }
                    depth += 1
                } else if byte == 0x7D { // '}'
                    if depth > 0 {
                        depth -= 1
                        if depth == 0, let start = startIndex {
                            let endIndex = buffer.index(after: currentIndex)
                            objects.append(Data(buffer[start..<endIndex]))
                            startIndex = nil
                        }
                    }
                }
            }
            currentIndex = buffer.index(after: currentIndex)
        }

        if let start = startIndex {
            buffer = Data(buffer[start...])
        } else {
            buffer.removeAll(keepingCapacity: true)
        }

        return objects
    }

    /// 从缓冲区中提取闭合的 JSON 对象字符串。
    nonisolated static func extractJSONObjects(from buffer: inout String) -> [String] {
        var objects: [String] = []
        var startIndex: String.Index?
        var depth = 0
        var inString = false
        var escape = false

        var currentIndex = buffer.startIndex
        while currentIndex < buffer.endIndex {
            let ch = buffer[currentIndex]
            if escape {
                escape = false
            } else if ch == "\\" && inString {
                escape = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    if depth == 0 {
                        startIndex = currentIndex
                    }
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let endIndex = buffer.index(after: currentIndex)
                        objects.append(String(buffer[start..<endIndex]))
                        startIndex = nil
                    }
                }
            }
            currentIndex = buffer.index(after: currentIndex)
        }

        if let start = startIndex {
            buffer = String(buffer[start...])
        } else {
            buffer = ""
        }

        return objects
    }

    /// 解析单条 NDJSON 报告中的主要 Layer 性能指标。
    nonisolated static func parseSample(from jsonStr: String) -> SecondSample? {
        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = root["Layers"] as? [[String: Any]], !layers.isEmpty else {
            return nil
        }

        var bestPresented: [String: Any]?
        var bestInterval: [String: Any]?
        var maxCount = -1

        for layer in layers {
            guard let perfStats = layer["Performance Stats"] as? [String: Any] else { continue }
            guard let presented = perfStats["Presented Frame Stats"] as? [String: Any],
                  let count = presented["Frame Count"] as? Int, count > 0,
                  let fps = presented["FPS"] as? Double, fps.isFinite, fps > 0 else { continue }
            let interval = perfStats["Frame-On-Glass Interval Stats"] as? [String: Any]
            if count > maxCount {
                maxCount = count
                bestPresented = presented
                bestInterval = interval
            }
        }

        guard let presented = bestPresented,
              let fps = presented["FPS"] as? Double, fps.isFinite, fps > 0,
              let frameCount = presented["Frame Count"] as? Int, frameCount > 0 else { return nil }

        let avgMs = bestInterval?["Average (ms)"] as? Double
        let stdDevMs = bestInterval?["StdDev (ms)"] as? Double
        let maxMs = bestInterval?["Max (ms)"] as? Double
        let minMs = bestInterval?["Min (ms)"] as? Double
        let totalMs = bestInterval?["Total (ms)"] as? Double
        let hasValidIntervals = avgMs.map { $0.isFinite && $0 > 0 } == true
            && stdDevMs.map { $0.isFinite && $0 >= 0 } == true
            && maxMs.map { $0.isFinite && $0 > 0 } == true
            && minMs.map { $0.isFinite && $0 > 0 } == true
            && totalMs.map { $0.isFinite && $0 > 0 } == true
            && (maxMs ?? 0) >= (avgMs ?? 0)
            && (avgMs ?? 0) >= (minMs ?? 0)

        return SecondSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            fps: fps,
            frameCount: frameCount,
            avgMs: hasValidIntervals ? avgMs : nil,
            stdDevMs: hasValidIntervals ? stdDevMs : nil,
            maxMs: hasValidIntervals ? maxMs : nil,
            minMs: hasValidIntervals ? minMs : nil,
            totalMs: hasValidIntervals ? totalMs : nil
        )
    }

    // MARK: - 指标计算 (FPS & 1% Low FPS)
 
    private func recordSample(_ sample: SecondSample) {
        samples.append(sample)

        let now = sample.timestamp
        let cutoff = now - Self.windowDuration
        samples.removeAll { $0.timestamp < cutoff }

        stats = Self.computeFPSStats(from: samples)
        scheduleSampleTimeout(for: generation)
    }

    /// 从滑动窗口样本计算当前/平均 FPS，并由帧间隔统计估算 1% Low。
    nonisolated static func computeFPSStats(from samples: [SecondSample]) -> GameHUDFPSStats? {
        guard let latest = samples.last else { return nil }
        let currentFPS = latest.fps
        guard currentFPS.isFinite, currentFPS > 0 else { return nil }

        let intervalSamples = samples.filter {
            $0.frameCount > 0 && $0.avgMs != nil && $0.stdDevMs != nil
                && $0.maxMs != nil && $0.totalMs != nil
        }
        let totalFrames = intervalSamples.reduce(0) { $0 + $1.frameCount }
        let totalDurationMs = intervalSamples.reduce(0.0) { $0 + ($1.totalMs ?? 0) }
        // 缺少帧间隔的报告只参与呈现 FPS 均值，不反推帧时间。
        let avgFPS = intervalSamples.count == samples.count && totalDurationMs > 0
            ? Double(totalFrames) / (totalDurationMs / 1000.0)
            : samples.reduce(0.0) { $0 + $1.fps } / Double(samples.count)

        guard latest.avgMs != nil, totalFrames > 0, totalDurationMs > 0 else {
            return GameHUDFPSStats(currentFPS: currentFPS, averageFPS: avgFPS, onePercentLow: nil)
        }

        // 滑动窗口加权均值帧间隔 (ms)
        let meanInterval = totalDurationMs / Double(totalFrames)

        // 滑动窗口合并方差: Var = (1/N) * sum_i [ count_i * (stdDev_i^2 + (avg_i - mean)^2) ]
        let sumVar = intervalSamples.reduce(0.0) { acc, s in
            let diff = (s.avgMs ?? meanInterval) - meanInterval
            let stdDev = s.stdDevMs ?? 0
            return acc + Double(s.frameCount) * (stdDev * stdDev + diff * diff)
        }
        let pooledVariance = sumVar / Double(totalFrames)
        let pooledStdDev = sqrt(max(0.0, pooledVariance))

        // 对数正态分布上 1% 条件尾均值: E[X | X >= Q_0.99] = mu * Phi(sigma_ln - z_0.99) / 0.01
        let cv = meanInterval > 0 ? (pooledStdDev / meanInterval) : 0
        let sigmaLn = sqrt(log(1.0 + cv * cv))
        let z99 = 2.3263478740408408
        let phi = 0.5 * erfc(-(sigmaLn - z99) / sqrt(2.0))
        let logNormalWorstInterval = meanInterval * max(1.0, phi / 0.01)

        // 离散掉帧统计: 收集各采样秒内的最慢帧 Max (ms)
        let sortedMaxIntervals = intervalSamples.compactMap(\.maxMs).filter { $0 > 0 }.sorted(by: >)
        let worstCount = min(sortedMaxIntervals.count, max(1, totalFrames / 100))

        // 取前 worstCount 个离散峰值(至多 samples.count 个)的均值，高帧率按样本覆盖率折减权重
        let peakSlice = sortedMaxIntervals.prefix(worstCount)
        let peakWorstInterval = peakSlice.isEmpty ? meanInterval : (peakSlice.reduce(0.0, +) / Double(peakSlice.count))
        let framesPerSample = Double(totalFrames) / Double(intervalSamples.count)
        let peakCoverage = framesPerSample > 100 ? min(1.0, 100.0 / framesPerSample) : 1.0
        let effectivePeak = peakCoverage * peakWorstInterval + (1.0 - peakCoverage) * logNormalWorstInterval

        let worstInterval: Double
        if !sortedMaxIntervals.isEmpty {
            let absoluteMax = sortedMaxIntervals[0]
            // 冷启动单秒且帧数很少时仅用连续分布估计，避免加载毛刺直接锁死 1% Low
            let estimatedWorst = (intervalSamples.count == 1 && totalFrames < 30)
                ? logNormalWorstInterval
                : max(logNormalWorstInterval, effectivePeak)
            worstInterval = min(absoluteMax, max(meanInterval, estimatedWorst))
        } else {
            worstInterval = max(meanInterval, logNormalWorstInterval)
        }

        let onePercentLow: Double
        if worstInterval > 0, !worstInterval.isNaN, !worstInterval.isInfinite {
            onePercentLow = min(avgFPS, 1000.0 / worstInterval)
        } else {
            onePercentLow = avgFPS
        }
        let ft = latest.avgMs
        return GameHUDFPSStats(currentFPS: currentFPS, averageFPS: avgFPS, onePercentLow: onePercentLow, frameTimeMs: ft)
    }
}
