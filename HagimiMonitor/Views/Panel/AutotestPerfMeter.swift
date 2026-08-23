import AppKit
import Darwin.Mach

/// 展开动画的调试度量器（**仅 autotest 构建生效**）。
///
/// 由 `HAGIMI_PANEL_AUTOTEST` 环境变量门控：未设置时所有方法首条即 return，
/// 生产环境零开销。每次 `setExpansion` 展开前调 `beginExpand()`，在动画时长
/// （+0.08s settle 尾巴）结束后汇总一行 `[autotest] expand ...`，输出：
/// - `main`：主线程在该窗口内消耗的 CPU 时间（ms），反映 SwiftUI body/布局/
///   行级毛玻璃等 **app 进程内**的工作量；
/// - `proc`：整个进程同窗口 CPU 时间（ms），与 main 的差值可暴露后台采样队列；
/// - `slowframes`：窗口内主线程打卡间隔 > 半帧(8.3ms) 的次数（掉帧体感）；
/// - `wall`：墙钟时长（ms），应为 ~230ms。
///
/// 关键诊断：若 main 不高、slowframes≈0 但活动监视器里 WindowServer 在展开时
/// 明显冲高，则高 CPU 来自窗口 `.behindWindow` 毛玻璃在逐帧 resize 时的背景
/// 重采样（计入 WindowServer、不计入本进程），主线程埋点无法直接量到。
@MainActor
final class AutotestPerfMeter {
    static let shared = AutotestPerfMeter()

    /// 仅 autotest 运行时启用（与各处 HAGIMI_PANEL_AUTOTEST 门控一致）。
    private let enabled = ProcessInfo.processInfo.environment["HAGIMI_PANEL_AUTOTEST"] != nil

    /// 主线程端口，初始化时捕获一次即可（主线程恒定，无需每帧取）。
    /// `mach_thread_self()` 返回 +1 发送权，init 里取完立即 `mach_port_deallocate`
    /// 平衡引用；端口归线程自身所有，随后读取仍有效。
    private let mainThread: mach_port_t

    private init() {
        let port = mach_thread_self()
        mainThread = port
        mach_port_deallocate(mach_task_self_, port)
    }

    /// 每次 beginExpand 自增的代号；finish 时比对，丢弃被二次 toggle 打断的半窗读数。
    private var epoch: UInt = 0
    /// 当前是否在度量窗口内（供帧探针决定是否计 slowframe、是否打逐帧日志）。
    private(set) var isMeasuring = false

    // 起始快照。
    private var startMainCPU: TimeInterval = 0
    private var startProcCPU: TimeInterval = 0
    private var startWall: CFTimeInterval = 0
    private var slowFrameCount = 0

    /// 展开动画起点打快照。必须在 `setExpansion` 最前（`beginExpansionAnimation()`
    /// 与 `withAnimation` 之前）调用，使度量窗口包住整段动画。
    func beginExpand(label: String = "expand") {
        guard enabled else { return }
        epoch &+= 1
        let token = epoch
        isMeasuring = true
        slowFrameCount = 0
        startMainCPU = threadCPUTime()
        startProcCPU = processCPUTime()
        startWall = CACurrentMediaTime()

        let window = MonitorConstants.panelExpansionDuration + 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + window) { [weak self] in
            MainActor.assumeIsolated {
                self?.finish(label: label, token: token)
            }
        }
    }

    /// 帧探针在打卡间隔 > 半帧时调用，仅累计当前度量窗口内的掉帧。
    func noteSlowFrame(gap ms: Double) {
        guard enabled, isMeasuring else { return }
        slowFrameCount += 1
        // 逐帧卡顿分布也只在动画窗口内打，避免窗口静止期的无关间隔刷屏。
        NSLog("[autotest] slowframe gap=%.1fms", ms)
    }

    private func finish(label: String, token: UInt) {
        guard enabled, token == epoch else { return }
        let wall = (CACurrentMediaTime() - startWall) * 1000
        let main = (threadCPUTime() - startMainCPU) * 1000
        let proc = (processCPUTime() - startProcCPU) * 1000
        isMeasuring = false
        NSLog("[autotest] %@ main=%.1fms proc=%.1fms slowframes=%d wall=%.1fms",
              label, main, proc, slowFrameCount, wall)
    }

    // MARK: - CPU 时间采样

    /// 主线程 CPU 时间（user + system），秒。
    private func threadCPUTime() -> TimeInterval {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / 4)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return TimeInterval(info.user_time.seconds + info.system_time.seconds)
             + TimeInterval(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
    }

    /// 整个进程 CPU 时间（user + system），秒。
    private func processCPUTime() -> TimeInterval {
        var ru = rusage()
        _ = getrusage(RUSAGE_SELF, &ru)
        return TimeInterval(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec)
             + TimeInterval(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1_000_000
    }
}
