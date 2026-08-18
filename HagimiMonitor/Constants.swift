import Foundation

enum MonitorConstants {
    // MARK: - Severity Thresholds
    static let criticalThreshold = 88.0
    static let warningThreshold = 72.0
    static let networkWarningThreshold = 85.0
    static let batteryCriticalThreshold = 12.0
    static let batteryWarningThreshold = 25.0

    // MARK: - Animation
    static let menuBarLoadChangeThreshold = 5.0
    // 缓动系数：每帧向目标靠拢的比例
    // 0.10 ⇒ 约 0.95s 缓缓到位；softmax 目标跳变更大，故取较柔和的值
    static let menuBarLoadSmoothFactor = 0.10
    // 每帧最小步进，保证大缓动尾段也能稳定收敛、不会无限逼近
    static let menuBarLoadSmoothMinStep = 0.6
    static let menuBarLoadSmoothStopThreshold = 0.5
    // 收敛后定时器停止，静止时零开销
    static let menuBarLoadSmoothFrameInterval = 1.0 / 30.0

    // MARK: - Panel Dimensions
    static let panelMinWidth: Double = 300
    static let panelIdealWidth: Double = 340
    static let panelMaxWidth: Double = 460
    static let rowCornerRadius = 14.0

    // MARK: - Row Glass Tint Fade
    // 活力配色行 tint 的垂直衰减参数:行头 plateau 高度内保持满浓度承载模块辨识度,
    // 其后线性衰减至 faint 不透明度,展开区小字落在近中性底上;收起的行高度小于
    // plateau,整卡处于满浓度段,外观与均布 tint 无异。
    static let rowTintPlateau = 46.0
    static let rowTintFadeEnd = 128.0
    static let rowTintFaintOpacity = 0.02

    // MARK: - Panel Expansion
    // 子栏目展开/收起动画时长。内容(SwiftUI `CollapsibleDetail` 的 frame 高度补间)
    // 与窗口层(`FluidPanelController` 的 setFrame 动画)必须用这一同一时长与
    // easeInOut 曲线并行动画到同一终值——外层 GeometryReader 只上报一次终值、无法
    // 逐帧跟随,只有两边同时同速才能边框与内容严丝合缝一起伸缩。
    static let panelExpansionDuration: TimeInterval = 0.15

    // MARK: - Animation Durations
    static let cpuAnimationDuration = 0.30
    static let batteryAnimationDuration = 2.20
    static let gpuAnimationDuration = 0.85
    static let defaultAnimationDuration = 1.65

    // MARK: - Sampling
    static let maxSamples = 28
    static let sparklineMaxPoints = 24

    // MARK: - Compute Load Aggregation
    // softmax(归一化 LSE)锐度 k：越大越接近 max(突出瓶颈)，越小越接近均值。
    // 1/k≈12.5 ⇒ 子系统差距 >12 分时由瓶颈主导，<12 分时融合。
    static let computeLoadSoftmaxSharpness = 0.08
}
