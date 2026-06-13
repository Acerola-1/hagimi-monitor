import AppKit
import CoreGraphics

enum MetricGridMetrics {
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    static let cellHStackSpacing: CGFloat = 6
    static let cellSpacerMinLength: CGFloat = 4
}

/// 用 AppKit `NSAttributedString` 测量 metric cell 在面板字号下的自然宽度。
/// 返回值 = label 自然宽 + 2 * HStack spacing + Spacer minLength + value 自然宽，高度取较高者。
/// 与 SwiftUI 实际渲染可能有 1-2pt 偏差，是可接受的——`MetricFlowPlacer`
/// 在 halfWidth 边界时按"超过即整行"判定，偏差不会改变宏观行型分布。
enum MetricCellSizing {
    /// SwiftUI `.footnote` 在系统中对应 11pt（实际渲染受动态字号影响，
    /// 这里取标准值用于测量）。
    private static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    /// 计算单个 metric cell 的半行自然尺寸。
    static func naturalSize(label: String, value: String) -> CGSize {
        let labelSize = (label as NSString).size(withAttributes: [.font: captionFont])
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
        let spacingWidth = MetricGridMetrics.cellHStackSpacing * 2 + MetricGridMetrics.cellSpacerMinLength
        return CGSize(
            width: ceil(labelSize.width) + spacingWidth + ceil(valueSize.width),
            height: ceil(max(labelSize.height, valueSize.height))
        )
    }
}
