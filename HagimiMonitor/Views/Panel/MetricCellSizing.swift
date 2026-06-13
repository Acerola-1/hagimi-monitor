import AppKit
import CoreGraphics

/// 用 AppKit `NSAttributedString` 测量 metric cell 在面板字号下的自然宽度。
/// 返回值 = label 自然宽 + 6（HStack spacing）+ value 自然宽，高度取较高者。
/// 与 SwiftUI 实际渲染可能有 1-2pt 偏差，是可接受的——`MetricFlowPlacer`
/// 在 halfWidth 边界时按"超过即整行"判定，偏差不会改变宏观行型分布。
enum MetricCellSizing {
    /// SwiftUI `.footnote` 在系统中对应 11pt（实际渲染受动态字号影响，
    /// 这里取标准值用于测量）。
    private static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    /// 计算单个 metric cell 的自然 (label + 6 + value) 尺寸。
    static func naturalSize(label: String, value: String) -> CGSize {
        let labelSize = (label as NSString).size(withAttributes: [.font: captionFont])
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
        return CGSize(
            width: ceil(labelSize.width) + 6 + ceil(valueSize.width),
            height: ceil(max(labelSize.height, valueSize.height))
        )
    }
}
