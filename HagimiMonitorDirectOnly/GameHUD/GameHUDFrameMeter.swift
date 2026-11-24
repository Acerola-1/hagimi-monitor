import AppKit
import Combine

/// 一份帧率统计快照(最近 60 秒窗口)。
nonisolated struct GameHUDFPSStats: Equatable, Sendable {
    /// 当前瞬时或最新 1 秒帧率。
    let currentFPS: Double?
    /// 滑动窗口(最近 60 秒)平均帧率。
    let averageFPS: Double?
    /// 1% 最低帧率 (1% Low FPS)。
    let onePercentLow: Double?
    /// 探针报告的平均上屏帧间隔 (毫秒 ms)。
    let frameTimeMs: Double?

    init(currentFPS: Double?, averageFPS: Double?, onePercentLow: Double?, frameTimeMs: Double? = nil) {
        self.currentFPS = currentFPS
        self.averageFPS = averageFPS
        self.onePercentLow = onePercentLow
        self.frameTimeMs = frameTimeMs
    }

    /// 用于 HUD 显示的核心 FPS 值(优先 averageFPS,其次 currentFPS)。
    var displayFPS: Double? {
        averageFPS ?? currentFPS
    }
}

@MainActor
protocol GameHUDFrameMeasuring: AnyObject {
    var stats: GameHUDFPSStats? { get }
    var statsPublisher: AnyPublisher<GameHUDFPSStats?, Never> { get }
    func start(target app: NSRunningApplication)
    func stop()
}

/// 仅转发目标进程的系统 Metal 呈现统计；探针无数据时保持缺值。
@MainActor
final class GameHUDFrameMeter: ObservableObject, GameHUDFrameMeasuring {
    @Published private(set) var stats: GameHUDFPSStats?
    var statsPublisher: AnyPublisher<GameHUDFPSStats?, Never> { $stats.eraseToAnyPublisher() }

    private let metalTraceMeter = MetalPerfTraceMeter()
    private var metalTraceCancellable: AnyCancellable?
    private static let reconnectDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var needsRestart = false

    /// 记录目标身份与切换代数；探针自身按代数丢弃迟到结果。
    private struct Session {
        let generation: Int
        let bundleID: String
        let pid: pid_t
    }

    private var session: Session?
    private var nextGeneration = 0

    var currentGeneration: Int {
        session?.generation ?? 0
    }

    init() {
        metalTraceCancellable = metalTraceMeter.$stats
            .sink { [weak self] metalStats in
                guard let self, let session = self.session else { return }
                guard metalStats == nil || self.metalTraceMeter.currentPID == session.pid else { return }
                if metalStats != nil {
                    self.reconnectAttempts = 0
                    self.needsRestart = false
                }
                self.stats = metalStats
            }

        metalTraceMeter.onUnexpectedExit = { [weak self] exitedPID in
            self?.handleUnexpectedExit(pid: exitedPID)
        }
    }

    func start(target app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        let pid = app.processIdentifier
        guard !bundleID.isEmpty, pid > 0 else {
            stop()
            return
        }

        if let session, session.bundleID == bundleID, session.pid == pid {
            if needsRestart, !metalTraceMeter.isRunning, reconnectTask == nil {
                needsRestart = false
                metalTraceMeter.start(pid: pid)
            }
            return
        }

        stop()
        nextGeneration += 1
        session = Session(generation: nextGeneration, bundleID: bundleID, pid: pid)
        metalTraceMeter.start(pid: pid)
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        needsRestart = false
        session = nil
        metalTraceMeter.stop()
        stats = nil
    }

    private func handleUnexpectedExit(pid: pid_t) {
        guard let session, session.pid == pid else { return }
        stats = nil
        needsRestart = true
        guard reconnectAttempts < Self.reconnectDelays.count else { return }
        let delay = Self.reconnectDelays[reconnectAttempts]
        reconnectAttempts += 1
        let expectedGeneration = session.generation
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard let current = self.session,
                  current.generation == expectedGeneration,
                  current.pid == pid,
                  NSRunningApplication(processIdentifier: pid)?.isTerminated == false else {
                return
            }
            self.needsRestart = false
            self.metalTraceMeter.start(pid: pid)
        }
    }
}
