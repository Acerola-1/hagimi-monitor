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
