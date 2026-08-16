import CoreGraphics

enum MetricGridMetrics {
    /// 逐格内衬网格的格间距(实验分支第四版):同时充当列间距与行间距,
    /// 色块边界 + 间隙共同划清每个指标。
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 6
    static let cellHStackSpacing: CGFloat = 6
    static let cellSpacerMinLength: CGFloat = 4
}
