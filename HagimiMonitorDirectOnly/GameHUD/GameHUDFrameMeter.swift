import Foundation
import OSLog
import ScreenCaptureKit
import CoreMedia
import Combine

/// 一份帧率统计快照(最近 60 秒窗口)。
nonisolated struct GameHUDFPSStats: Equatable, Sendable {
    /// 当前瞬时或最新 1 秒帧率。
    let currentFPS: Double?
    /// 滑动窗口(最近 60 秒)平均帧率。
    let averageFPS: Double?
    /// 1% 最低帧率 (1% Low FPS)。
    let onePercentLow: Double?
    /// 实时帧生成时间 (毫秒 ms)。
    let frameTimeMs: Double?

    init(currentFPS: Double?, averageFPS: Double?, onePercentLow: Double?, frameTimeMs: Double? = nil) {
        self.currentFPS = currentFPS
        self.averageFPS = averageFPS
        self.onePercentLow = onePercentLow
        if let frameTimeMs {
            self.frameTimeMs = frameTimeMs
        } else if let fps = currentFPS ?? averageFPS, fps > 0 {
            self.frameTimeMs = 1000.0 / fps
        } else {
            self.frameTimeMs = nil
        }
    }

    /// 用于 HUD 显示的核心 FPS 值(优先 averageFPS,其次 currentFPS)。
    var displayFPS: Double? {
        averageFPS ?? currentFPS
    }
}

/// 游戏帧率测速器:
/// 1. 优先使用系统 `metalperftrace` 探针:免屏幕录制授权、开销极低,
///    直接读取系统合成器产出的 Frame-On-Glass Interval Stats 计算 1% Low 与 FPS;
/// 2. 降级支持 `ScreenCaptureKit` 窗口捕获测帧:对目标窗口开微型流,
///    每帧计算 FNV-1a 像素哈希判定真实上屏,计算平均 FPS 与 1% Low。
@MainActor
final class GameHUDFrameMeter: NSObject, ObservableObject {

    /// 帧率统计结果发布(有数据才发布)。
    @Published private(set) var stats: GameHUDFPSStats?

    /// 首选探针: metalperftrace 监听器。
    private let metalTraceMeter = MetalPerfTraceMeter()
    private var metalTraceCancellable: AnyCancellable?
    private var sckFallbackTask: Task<Void, Never>?

    /// SCK 捕获会话:generation 隔离 start/stop 竞态。
    private struct Session {
        let generation: Int
        let bundleID: String
        let pid: pid_t
        var stream: SCStream?
    }

    private struct FrameSample {
        let presentation: Double
        let interval: Double
    }

    private var session: Session?
    private var nextGeneration: Int = 0

    /// 当前会话 generation（供测试与竞态防卫观测）。
    var currentGeneration: Int {
        session?.generation ?? 0
    }
    nonisolated(unsafe) private var samples: [FrameSample] = []
    nonisolated(unsafe) private var lastPresentation: Double?
    nonisolated(unsafe) private var lastSignature: UInt64 = 0
    nonisolated(unsafe) private var hasLastSignature = false
    nonisolated(unsafe) private var lastPublishTime: Double = 0
    nonisolated private static let stallThreshold: Double = 2.0
    nonisolated private static let windowDuration: Double = 60.0
    nonisolated private static let minimumSamples = 30
    private static let captureWidth = 64
    private static let captureHeight = 36

    private let captureQueue = DispatchQueue(label: "gamehud.framemeter", qos: .utility)

    override init() {
        super.init()
        metalTraceCancellable = metalTraceMeter.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metalStats in
                guard let self else { return }
                if let metalStats {
                    self.stats = metalStats
                    // 系统探针已产生有效数据，若 SCK 降级捕获流在运行则及时停止以节约开销
                    if let stream = self.session?.stream {
                        self.session?.stream = nil
                        Task { [stream] in
                            try? await stream.stopCapture()
                        }
                    }
                }
            }
    }

    /// 对目标游戏进程开启测帧。
    func start(target app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        let pid = app.processIdentifier
        guard !bundleID.isEmpty, pid > 0 else { return }

        // 同一目标已在测:不重复重启
        if let session, session.bundleID == bundleID, session.pid == pid {
            return
        }

        stopSession(keepStats: false)
        nextGeneration += 1
        let generation = nextGeneration
        session = Session(generation: generation, bundleID: bundleID, pid: pid, stream: nil)

        // 1. 优先尝试系统 metalperftrace (Metal 游戏免录屏授权)
        metalTraceMeter.start(pid: pid)

        // 2. 降级定时器:若 2.5 秒后 metalperftrace 未产生数据,且已授权录屏,启用 SCK
        sckFallbackTask?.cancel()
        sckFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled, let current = self.session, current.generation == generation else { return }
            if !self.metalTraceMeter.hasReceivedValidSample {
                if ScreenCapturePermissionService.shared.isTrusted {
                    AppLogger.diagnostics.info("metalperftrace inactive for \(bundleID, privacy: .public), falling back to ScreenCaptureKit")
                    await self.attach(generation: generation, appBundleID: bundleID)
                }
            }
        }
    }

    func stop() {
        stopSession(keepStats: false)
    }

    private func stopSession(keepStats: Bool) {
        sckFallbackTask?.cancel()
        sckFallbackTask = nil
        metalTraceMeter.stop()

        let stale = session
        session = nil
        if let stream = stale?.stream {
            Task { [stream] in
                try? await stream.stopCapture()
            }
        }
        captureQueue.async { [weak self] in
            self?.resetSamples()
        }
        if !keepStats, stats != nil {
            stats = nil
        }
    }

    private nonisolated func resetSamples() {
        samples = []
        lastPresentation = nil
        hasLastSignature = false
        lastSignature = 0
        lastPublishTime = 0
    }

    // MARK: - ScreenCaptureKit 降级实现

    private func attach(generation: Int, appBundleID: String) async {
        guard ScreenCapturePermissionService.shared.isTrusted else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows
                .filter({ $0.owningApplication?.bundleIdentifier == appBundleID && $0.frame.width > 200 })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Self.captureWidth
            config.height = Self.captureHeight
            config.minimumFrameInterval = CMTime(value: 1, timescale: 240)
            config.queueDepth = 8
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try await stream.startCapture()

            if await !self.registerStreamIfCurrent(generation: generation, stream: stream) {
                try? await stream.stopCapture()
            } else {
                AppLogger.diagnostics.info("GameHUD SCK frame meter started, bundle=\(appBundleID, privacy: .public)")
            }
        } catch {
            AppLogger.diagnostics.info("GameHUD SCK frame meter unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private func registerStreamIfCurrent(generation: Int, stream: SCStream) -> Bool {
        if var current = session, current.generation == generation {
            current.stream = stream
            session = current
            return true
        }
        return false
    }
}

extension GameHUDFrameMeter: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.diagnostics.info("GameHUD SCK frame meter stream stopped: \(String(describing: error), privacy: .public)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.session = nil
            self.stopSession(keepStats: false)
        }
    }
}

extension GameHUDFrameMeter: SCStreamOutput, @unchecked Sendable {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let signature = pixelHash(imageBuffer) else {
            captureQueue.async { [weak self] in
                self?.handleInvalidFrame()
            }
            return
        }
        captureQueue.async { [weak self] in
            self?.handleFrame(signature: signature, at: t)
        }
    }

    private nonisolated func pixelHash(_ buffer: CVPixelBuffer) -> UInt64? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        var hash: UInt64 = 1_469_598_103_934_665_6037
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            let line = ptr + row * bytesPerRow
            for b in 0..<(width * 4) {
                hash = (hash ^ UInt64(line[b])) &* 1_099_511_628_211
            }
        }
        return hash
    }

    private nonisolated func handleFrame(signature: UInt64, at t: Double) {
        guard !hasLastSignature || signature != lastSignature else { return }
        if hasLastSignature, let last = lastPresentation {
            let interval = t - last
            if interval > 0, interval < Self.stallThreshold {
                samples.append(FrameSample(presentation: t, interval: interval))
                pruneIfNeeded(now: t)
                // 1Hz 节流: 限制 SCK 降级发布频率与主采样同步，避免 60-120Hz 逐帧排序与重绘
                if t - lastPublishTime >= 1.0 {
                    lastPublishTime = t
                    publishStatsIfNeeded()
                }
            }
        }
        lastPresentation = t
        lastSignature = signature
        hasLastSignature = true
    }

    private nonisolated func handleInvalidFrame() {
        lastPresentation = nil
        hasLastSignature = false
        lastPublishTime = 0
    }

    private nonisolated func pruneIfNeeded(now: Double) {
        let cutoff = now - Self.windowDuration - 2.0
        if let first = samples.first, first.presentation < cutoff {
            samples.removeFirst(max(0, samples.firstIndex(where: { $0.presentation >= cutoff }) ?? 0))
        }
    }

    private nonisolated func publishStatsIfNeeded() {
        guard samples.count >= Self.minimumSamples else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.metalTraceMeter.hasReceivedValidSample && self.stats != nil {
                    self.stats = nil
                }
            }
            return
        }

        let total = samples.reduce(0) { $0 + $1.interval }
        guard total > 0 else { return }
        let avg = Double(samples.count) / total
        let sorted = samples.sorted { $0.interval > $1.interval }
        let worstCount = max(1, sorted.count / 100)
        let worst = sorted.prefix(worstCount)
        let worstTotal = worst.reduce(0) { $0 + $1.interval }
        let low = worstTotal > 0 ? Double(worst.count) / worstTotal : avg

        let recentCutoff = (samples.last?.presentation ?? 0) - 1.0
        let recent = samples.filter { $0.presentation >= recentCutoff }
        let recentTotal = recent.reduce(0) { $0 + $1.interval }
        let current = recentTotal > 0 ? Double(recent.count) / recentTotal : avg
        let ft = current > 0 ? (1000.0 / current) : (avg > 0 ? (1000.0 / avg) : nil)

        let new = GameHUDFPSStats(currentFPS: current, averageFPS: avg, onePercentLow: low, frameTimeMs: ft)

        Task { @MainActor [weak self] in
            guard let self else { return }
            // 若系统探针已在采真实数据,以系统探针优先
            if !self.metalTraceMeter.hasReceivedValidSample {
                if self.stats != new {
                    self.stats = new
                }
            }
        }
    }
}
