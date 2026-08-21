import AppKit
import Combine

/// 面板展开动画的唯一进度驱动器。
///
/// 内容侧(`CollapsibleDetail`)与窗口层从同一个相位推导高度:驱动器在主 RunLoop
/// 上以 60Hz 推进缓动进度,把每个 tick 的相位整体发布为 `phase[key]`
/// (0=收起,1=展开);`CollapsibleDetail` 按各自 key 读取相位设布局高度,内容尺寸
/// 随之逐帧变化,窗口层被动跟随--高度动画只有驱动器这一个时间源,边框与内容
/// 天然同相,不存在两套补间各自计时造成的毫秒级相位漂移(观感「边框与内容像
/// 两层」)。chevron 旋转等次级动效仍走 SwiftUI 隐式动画,与本驱动器同时长
/// 同曲线,端点对齐。
///
/// 相位是每个展开区的当前快照,跨多次展开持续累积;同一次 `animate` 推入的多个
/// key 共享计时起点与缓动曲线,同步走到目标(整体展开/收起时行列一致)。
/// 动画中途再次 `animate` 与在途 key 合并推进,不会打断未完成的补间。
@MainActor
final class PanelExpansionDriver: ObservableObject {
    /// 各展开区当前相位,0=完全收起,1=完全展开。非动画期间等于目标的 0 或 1。
    /// 每个 tick 整体赋值一次,单帧只发布一回,避免多 key 各赋值一次引发多次失效。
    @Published private(set) var phase: [String: CGFloat] = [:]

    /// 单次补间的时长,由面板常量统一控制。
    private let duration = MonitorConstants.panelExpansionDuration

    /// 驱动定时器;仅动画期间的 ~0.15s 内存在,平时为 nil(零开销)。
    private var timer: Timer?

    /// 驱动定时器的触发间隔:60Hz 已覆盖普通显示器的显示帧率;
    /// 高刷屏上以 60fps 推进同样平滑,且避免 120Hz 定时器在 60Hz 屏上
    /// 每个显示帧做两遍全链路工作。
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    /// 在途补间:key → 起止相位与各自的计时起点。各自起点使中途重新定向
    /// (如展开一半收起)从当前相位平滑续接,不打断其它在途 key。
    private var running: [String: (from: CGFloat, to: CGFloat, start: CFTimeInterval)] = [:]

    /// 把一批展开区动画到各自目标相位(0 或 1),与在途补间合并推进。
    /// 同批 key 共享计时起点,同步走到目标。
    func animate(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        let now = CACurrentMediaTime()
        for (key, target) in targets {
            // 尚无相位的 key 从目标的反向稳态起步:展开从 0、收起从 1
            // (未被动画过的视图体恰停在 toggle 方向的来路上)。
            running[key] = (from: phase[key] ?? (target > 0.5 ? 0 : 1), to: target, start: now)
        }
        startTimer()
        // 立即推一帧,避免首帧要等下一个 tick 才动。
        tick()
    }

    /// 不补间、立即把相位设到目标。用于面板隐藏期/初始化阶段同步最终布局状态。
    func setInstantly(targets: [String: CGFloat]) {
        guard !targets.isEmpty else { return }
        for key in targets.keys {
            running.removeValue(forKey: key)
        }
        if running.isEmpty {
            stopTimer()
        }
        var next = phase
        for (key, value) in targets {
            next[key] = value
        }
        phase = next
    }

    /// 单 key 版 `setInstantly`:同步语义调用方(初始化/隐藏重置)的便捷入口。
    func setInstantly(_ key: String, _ value: CGFloat) {
        setInstantly(targets: [key: value])
    }

    /// 单 key 版 `animate`:toggle 单个展开区的便捷入口。
    func animate(_ key: String, _ target: CGFloat) {
        animate(targets: [key: target])
    }

    /// 定时器回调:按各自的计时起点与缓动曲线推进在途进度,
    /// 整批相位一次性发布。
    private func tick() {
        guard !running.isEmpty else { return }
        let now = CACurrentMediaTime()
        var next = phase
        for (key, spec) in running {
            let t = min(1, (now - spec.start) / duration)
            next[key] = spec.from + (spec.to - spec.from) * easeInOut(t)
            if t >= 1 {
                next[key] = spec.to
                running.removeValue(forKey: key)
            }
        }
        phase = next
        if running.isEmpty {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            // 定时器挂在主 RunLoop,@MainActor 隔离下用 assumeIsolated 切到驱动器。
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 标准 cubic easeInOut,与 SwiftUI `.easeInOut` / `CAMediaTimingFunction`
    /// 的 easeInEaseOut 同型,保证中间帧观感统一。
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        if t < 0.5 { return 4 * t * t * t }
        return 1 - pow(-2 * t + 2, 3) / 2
    }
}
