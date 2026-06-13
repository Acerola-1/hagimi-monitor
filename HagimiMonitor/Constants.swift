import Foundation

enum MonitorConstants {
    // MARK: Severity Thresholds
    static let criticalThreshold = 88.0
    static let warningThreshold = 72.0
    static let networkWarningThreshold = 85.0
    static let batteryCriticalThreshold = 12.0
    static let batteryWarningThreshold = 25.0

    // MARK: Animation
    static let menuBarLoadChangeThreshold = 5.0
    static let menuBarLoadSmoothStep = 1.25
    static let menuBarLoadSmoothStopThreshold = 0.5

    // MARK: Panel Dimensions
    static let panelMinWidth: Double = 300
    static let panelIdealWidth: Double = 340
    static let panelMaxWidth: Double = 460
    static let rowCornerRadius = 14.0

    // MARK: Animation Durations
    static let cpuAnimationDuration = 0.30
    static let batteryAnimationDuration = 2.20
    static let gpuAnimationDuration = 0.85
    static let defaultAnimationDuration = 1.65

    // MARK: Sampling
    static let maxSamples = 28
    static let sparklineMaxPoints = 24
}
