import SwiftUI

// MARK: - Compatible Tab / Segmented Picker Style

extension View {
    /// 跨版本统一的分段选择器样式。
    /// 遵循 macOS HIG 规范，在设置项与报表筛选中保持原生分段外观与交互质感。
    func compatibleTabPickerStyle() -> some View {
        self.pickerStyle(.segmented)
    }
}
