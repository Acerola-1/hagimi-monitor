import CoreGraphics

enum MetricGridMetrics {
    /// 逐格内衬网格的列间距。
    static let columnSpacing: CGFloat = 8
    /// 逐格内衬网格的行间距:小于列距——行高本身已含格内上下内衬,
    /// 行距同宽会显松。
    static let gridRowGap: CGFloat = 5
    static let rowSpacing: CGFloat = 6
    static let cellHStackSpacing: CGFloat = 6
    static let cellSpacerMinLength: CGFloat = 4
}
