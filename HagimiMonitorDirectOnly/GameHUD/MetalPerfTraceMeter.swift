import Foundation
import OSLog
import Combine

/// 通过系统 `metalperftrace` 命令行工具监听目标 Metal 进程的上屏帧率统计。
///
/// 核心优势:
/// - 无需「屏幕录制」授权即可直读 Metal 渲染/呈现指标;
/// - 由系统 Metal/合成器直接产出 Frame-On-Glass Interval Stats (Min/Average/Max/StdDev/Count);
/// - 开销极低,无额外像素捕获与内存拷贝。
@MainActor
final class MetalPerfTraceMeter: ObservableObject {

    struct SecondSample: Sendable {
        let timestamp: TimeInterval
        let fps: Double
        let frameCount: Int
        let avgMs: Double
        let stdDevMs: Double
        let maxMs: Double
        let minMs: Double
        let totalMs: Double
    }

    @Published private(set) var stats: GameHUDFPSStats?
    private(set) var hasReceivedValidSample = false

    private var process: Process?
    private var pipe: Pipe?
    private(set) var currentPID: pid_t?
    private var samples: [SecondSample] = []
    private static let windowDuration: TimeInterval = 60.0
    private let readerQueue = DispatchQueue(label: "gamehud.metalperftrace.reader", qos: .utility)

    /// 启动对指定 PID 进程的 Metal 帧统计监听。
    func start(pid: pid_t) {
        guard pid > 0 else { return }
        if currentPID == pid, process != nil, process?.isRunning == true {
            return
        }

        stop()

        let executablePath = "/usr/bin/metalperftrace"
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            AppLogger.diagnostics.info("metalperftrace not executable at \(executablePath, privacy: .public)")
            return
        }

        currentPID = pid
        hasReceivedValidSample = false
        samples.removeAll()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = ["listen", "--json", "--interval", "1", "--pid", "\(pid)"]

        let stdoutPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = FileHandle.nullDevice

        self.pipe = stdoutPipe
        self.process = p

        var buffer = ""
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self, readerQueue] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                try? handle.close()
                return
            }
            readerQueue.async { [weak self] in
                guard let self, let str = String(data: data, encoding: .utf8) else { return }
                buffer.append(str)

                let jsonObjects = Self.extractJSONObjects(from: &buffer)
                for jsonStr in jsonObjects {
                    if let sample = Self.parseSample(from: jsonStr) {
                        Task { @MainActor [weak self] in
                            self?.recordSample(sample)
                        }
                    }
                }

                if buffer.count > 512 * 1024 {
                    buffer = ""
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentPID == pid else { return }
                self.stop()
            }
        }

        do {
            try p.run()
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
        hasReceivedValidSample = false
        stats = nil
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
            let presented = perfStats["Presented Frame Stats"] as? [String: Any]
            let interval = perfStats["Frame-On-Glass Interval Stats"] as? [String: Any]
            let count = (presented?["Frame Count"] as? Int) ?? (interval?["Count"] as? Int) ?? 0
            if count > maxCount {
                maxCount = count
                bestPresented = presented
                bestInterval = interval
            }
        }

        guard let presented = bestPresented, let interval = bestInterval else { return nil }

        let fps = presented["FPS"] as? Double ?? 0
        let frameCount = presented["Frame Count"] as? Int ?? interval["Count"] as? Int ?? 0
        let avgMs = interval["Average (ms)"] as? Double ?? 0
        let stdDevMs = interval["StdDev (ms)"] as? Double ?? 0
        let maxMs = interval["Max (ms)"] as? Double ?? 0
        let minMs = interval["Min (ms)"] as? Double ?? 0
        let totalMs = interval["Total (ms)"] as? Double ?? (avgMs * Double(frameCount))

        guard frameCount > 0 || fps > 0 else { return nil }

        return SecondSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            fps: fps,
            frameCount: frameCount,
            avgMs: avgMs,
            stdDevMs: stdDevMs,
            maxMs: maxMs,
            minMs: minMs,
            totalMs: totalMs
        )
    }

    // MARK: - 指标计算 (FPS & 1% Low FPS)
 
    private func recordSample(_ sample: SecondSample) {
        hasReceivedValidSample = true
        samples.append(sample)

        let now = sample.timestamp
        let cutoff = now - Self.windowDuration
        samples.removeAll { $0.timestamp < cutoff }

        stats = Self.computeFPSStats(from: samples)
    }

    /// 从滑动窗口样本序列中计算当前/平均 FPS 与 1% Low FPS。
    nonisolated static func computeFPSStats(from samples: [SecondSample]) -> GameHUDFPSStats? {
        guard let latest = samples.last else { return nil }
        let currentFPS = latest.fps
        let totalFrames = samples.reduce(0) { $0 + $1.frameCount }
        let totalDurationMs = samples.reduce(0.0) { $0 + $1.totalMs }

        guard totalFrames > 0 else {
            return GameHUDFPSStats(currentFPS: currentFPS, averageFPS: currentFPS, onePercentLow: currentFPS)
        }

        let avgFPS: Double
        if totalDurationMs > 0 {
            avgFPS = Double(totalFrames) / (totalDurationMs / 1000.0)
        } else {
            avgFPS = currentFPS
        }

        // 滑动窗口加权均值帧间隔 (ms)
        let meanInterval = totalDurationMs > 0 ? (totalDurationMs / Double(totalFrames)) : (1000.0 / max(1.0, avgFPS))

        // 滑动窗口合并方差: Var = (1/N) * sum_i [ count_i * (stdDev_i^2 + (avg_i - mean)^2) ]
        let sumVar = samples.reduce(0.0) { acc, s in
            let diff = s.avgMs - meanInterval
            return acc + Double(s.frameCount) * (s.stdDevMs * s.stdDevMs + diff * diff)
        }
        let pooledVariance = sumVar / Double(totalFrames)
        let pooledStdDev = sqrt(max(0.0, pooledVariance))

        // 正态分布 99% 分位数 (1% 最慢帧时间) 连续估计: mean + 2.326 * stdDev
        let normalWorstInterval = meanInterval + 2.326 * pooledStdDev

        // 离散掉帧统计: 收集各采样秒内的最慢帧 Max (ms)
        let sortedMaxIntervals = samples.map(\.maxMs).filter { $0 > 0 }.sorted(by: >)
        let worstCount = max(1, totalFrames / 100)

        // 取前 worstCount 个离散峰值(至多 samples.count 个)的加权均值
        let peakSlice = sortedMaxIntervals.prefix(min(worstCount, sortedMaxIntervals.count))
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
        let ft = latest.avgMs > 0 ? latest.avgMs : meanInterval
        return GameHUDFPSStats(currentFPS: currentFPS, averageFPS: avgFPS, onePercentLow: onePercentLow, frameTimeMs: ft)
    }
}
