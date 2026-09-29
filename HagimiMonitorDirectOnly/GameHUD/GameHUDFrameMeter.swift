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

/// 仅转发目标进程的系统 Metal 呈现统计；探针无数据时保持缺值。
@MainActor
final class GameHUDFrameMeter: ObservableObject {
    @Published private(set) var stats: GameHUDFPSStats?

    private let metalTraceMeter = MetalPerfTraceMeter()
    private var metalTraceCancellable: AnyCancellable?

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
                guard let self, let session = self.session,
                      self.metalTraceMeter.currentPID == session.pid else { return }
                self.stats = metalStats
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
            return
        }

        stop()
        nextGeneration += 1
        session = Session(generation: nextGeneration, bundleID: bundleID, pid: pid)
        metalTraceMeter.start(pid: pid)
    }

    func stop() {
        session = nil
        metalTraceMeter.stop()
        stats = nil
    }
}
