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
    /// 顶层模块行头的统一高度，保证不同尾部控件不会改变卡片基线。
    /// 有意锁死:面板走固定字号排版,不随系统动态字体缩放,避免行高被撑破。
    static let panelRowHeaderHeight: CGFloat = 34
    /// 行头尾部可视化槽位:sparkline/进度条统一落在 56×18 盒内(细条居中),
    /// 与胶囊行(高 20)共用行头垂直中线,右缘视觉节奏一致。
    static let trailingSlotWidth: CGFloat = 56
    static let trailingSlotHeight: CGFloat = 18
    static let rowCornerRadius = 14.0
    /// 面板外框圆角:与行卡片/底部按钮同值,外轮廓弧度统一、观感更利落。
    /// 留白 6pt 下转角间隙略宽于直边(约 8.5pt),为有意取舍,不遵循同心圆角 R_outer = R_inner + padding。
    static let panelCornerRadius = 14.0

    // MARK: - Row Glass Tint Fade
    // 活力配色行 tint 的垂直衰减参数:行头 plateau 高度内保持满浓度承载模块辨识度,
    // 其后线性衰减至 faint 不透明度,展开区小字落在近中性底上;收起的行高度小于
    // plateau,整卡处于满浓度段,外观与均布 tint 无异。
    static let rowTintPlateau = 46.0
    static let rowTintFadeEnd = 128.0
    static let rowTintFaintOpacity = 0.02

    // MARK: - Panel Expansion
    // SwiftUI 弹簧参数:内容高度 / chevron / 滚动揭示等所有展开相关动画。
    // 弹簧在中断时保持当前速度重定向,不像 easeInOut 从零重启,
    // 快速连点展开/收起时内容平滑过渡、无重启顿挫。
    static let panelExpansionSpringResponse: TimeInterval = 0.32
    static let panelExpansionSpringDamping: Double = 0.82
    // 弹簧衰减到不可察觉的时间。采样推迟 / 校准 / 负载环暂停均以此为窗口,
    // 覆盖弹簧尾段微振,避免校准过早捕获中间态。
    static let panelExpansionSettleTime: TimeInterval = 0.50

    // MARK: - Sampling
    static let sparklineMaxPoints = 24

    // MARK: - Compute Load Aggregation
    // softmax(归一化 LSE)锐度 k：越大越接近 max(突出瓶颈)，越小越接近均值。
    // 1/k≈12.5 ⇒ 子系统差距 >12 分时由瓶颈主导，<12 分时融合。
    static let computeLoadSoftmaxSharpness = 0.08
}
