import Foundation
import OSLog
import Combine

/// 每次探针会话独立持有缓冲区；仅在 readerQueue 上访问其内容。
nonisolated private final class MetalTraceJSONBuffer: @unchecked Sendable {
    var text = ""
}

/// 通过系统 `metalperftrace` 命令行工具监听目标 Metal 进程的上屏帧率统计。
///
/// 直接读取系统报告的呈现 FPS；帧间隔统计可能缺失，此时不估算帧时间与 1% Low。
/// 不使用屏幕录制或像素捕获。
@MainActor
final class MetalPerfTraceMeter: ObservableObject {

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
    private var process: Process?
    private var pipe: Pipe?
    private(set) var currentPID: pid_t?
    private var samples: [SecondSample] = []
    private static let windowDuration: TimeInterval = 60.0
    private static let sampleTimeout: Duration = .seconds(3)
    private var sampleTimeoutTask: Task<Void, Never>?
    private var generation = 0
    private let readerQueue = DispatchQueue(label: "gamehud.metalperftrace.reader", qos: .utility)

    /// 启动对指定 PID 进程的 Metal 帧统计监听。
    func start(pid: pid_t) {
        guard pid > 0 else { return }
        if currentPID == pid, process != nil, process?.isRunning == true {
            return
        }

        stop()
        let sessionGeneration = generation

        let executablePath = "/usr/bin/metalperftrace"
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            AppLogger.diagnostics.info("metalperftrace not executable at \(executablePath, privacy: .public)")
            return
        }

        currentPID = pid
        samples.removeAll()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = ["listen", "--json", "--interval", "1", "--pid", "\(pid)"]

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
                try? handle.close()
                return
            }
            readerQueue.async { [weak self] in
                guard let self, let str = String(data: data, encoding: .utf8) else { return }
                buffer.text.append(str)

                let jsonObjects = Self.extractJSONObjects(from: &buffer.text)
                for jsonStr in jsonObjects {
                    if let sample = Self.parseSample(from: jsonStr) {
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == sessionGeneration else { return }
                            self.recordSample(sample)
                        }
                    }
                }

                if buffer.text.count > 512 * 1024 {
                    buffer.text = ""
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == sessionGeneration else { return }
                self.stop()
            }
        }

        do {
            try p.run()
            scheduleSampleTimeout(for: sessionGeneration)
            AppLogger.diagnostics.info("metalperftrace started for pid=\(pid, privacy: .public)")
            // 动态抑制 Apple 官方 HUD 浮层，避免系统自带 HUD 叠加弹出
            DispatchQueue.global(qos: .utility).async {
                let setup = Process()
                setup.executableURL = URL(fileURLWithPath: executablePath)
                setup.arguments = ["setup", "--disable", "hud", "--pid", "\(pid)"]
                setup.standardOutput = FileHandle.nullDevice
                setup.standardError = FileHandle.nullDevice
                try? setup.run()
                setup.waitUntilExit()
            }
        } catch {
            AppLogger.diagnostics.error("Failed to run metalperftrace: \(error, privacy: .public)")
            stop()
        }
    }

    /// 停止监听并释放外部进程与流。
    func stop() {
        generation += 1
        sampleTimeoutTask?.cancel()
        sampleTimeoutTask = nil
        if let pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        pipe = nil
        currentPID = nil
        samples.removeAll()
        stats = nil
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

        // 正态分布 99% 分位数 (1% 最慢帧时间) 连续估计: mean + 2.326 * stdDev
        let normalWorstInterval = meanInterval + 2.326 * pooledStdDev

        // 离散掉帧统计: 收集各采样秒内的最慢帧 Max (ms)
        let sortedMaxIntervals = intervalSamples.compactMap(\.maxMs).filter { $0 > 0 }.sorted(by: >)
        let worstCount = min(sortedMaxIntervals.count, max(1, totalFrames / 100))

        // 取前 worstCount 个离散峰值(至多 samples.count 个)的加权均值
        let peakSlice = sortedMaxIntervals.prefix(worstCount)
        let peakWorstInterval = peakSlice.isEmpty ? meanInterval : (peakSlice.reduce(0.0, +) / Double(peakSlice.count))

        let worstInterval: Double
        if !sortedMaxIntervals.isEmpty {
            let absoluteMax = sortedMaxIntervals[0]
            // worstInterval 在连续 99% 分位数与离散最差帧均值之间取更保守的较大帧间隔, 并以物理最大峰值为上界
            let estimatedWorst = max(normalWorstInterval, peakWorstInterval)
            worstInterval = min(absoluteMax, max(meanInterval, estimatedWorst))
        } else {
            worstInterval = max(meanInterval, normalWorstInterval)
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
